# =====================================================================================================================
# File: test_dma_controller.py
# =====================================================================================================================
#
# >>> Descrição: Testbench para o Controlador DMA (Direct Memory Access)
#       Atualizado para a arquitetura Dual-Master (Read/Write desacoplados).
#       Inclui suporte ao protocolo Edge Guard na interface de configuração.
#
# =====================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from sim.core.single_cycle.include.test_utils import log_header, log_success, Colors

# ==============================================================================
# CONSTANTES E MAPA DE REGISTRADORES
# ==============================================================================

REG_SRC  = 0x0    # Registrador de fonte
REG_DST  = 0x4    # Registrador de destino
REG_CNT  = 0x8    # Registrador de contagem
REG_CTRL = 0xC    # Registrador de controle

CTRL_START     = 1 << 0
CTRL_FIXED_DST = 1 << 1
CTRL_BUSY      = 1 << 0

# ==============================================================================
# AUXILIARES DE SIMULAÇÃO (DRIVERS E MONITORES)
# ==============================================================================

async def setup_dut(dut):
    """Inicializa clock e reseta o DUT"""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_i.value = 1
    dut.cfg_vld_i.value = 0
    dut.cfg_we_i.value = 0
    
    # Zera as duas portas do Dual-Master
    dut.m_rd_rdy_i.value = 0
    dut.m_wr_rdy_i.value = 0
    
    await Timer(20, unit="ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

async def cfg_write(dut, addr, data):
    """Escreve nos registradores de configuração do DMA com Handshake Síncrono (Edge Guard)"""
    dut.cfg_addr_i.value = addr
    dut.cfg_data_i.value = data
    dut.cfg_vld_i.value = 1
    dut.cfg_we_i.value = 1
    
    # Aguarda a resposta do Edge Guard garantindo que o comando não seja descartado
    while True:
        await RisingEdge(dut.clk_i)
        if dut.cfg_rdy_o.value == 1:
            break
    
    dut.cfg_vld_i.value = 0
    dut.cfg_we_i.value = 0
    await Timer(1, unit="ns")

async def read_status(dut):
    """Lê o registrador de controle (Status)"""
    dut.cfg_addr_i.value = REG_CTRL
    await Timer(1, unit="ns") 
    return int(dut.cfg_data_o.value)

async def wait_dma_done(dut, timeout_cycles=2000):
    """Espera o bit Busy baixar"""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk_i)
        status = await read_status(dut)
        if (status & CTRL_BUSY) == 0:
            return True
    return False

# ----- Separação do Escravo da Memória para suportar Paralelismo -----

async def bus_slave_read(dut, memory_mock, latency_cycles):
    """Simula o lado de Leitura da Memória (Responde ao Produtor)"""
    dut.m_rd_rdy_i.value = 0
    while True:
        await RisingEdge(dut.clk_i)
        dut.m_rd_rdy_i.value = 0
        await Timer(1, unit="ns")
        
        if dut.m_rd_vld_o.value == 1:
            addr = int(dut.m_rd_addr_o.value)
            
            # Simula Latência
            for _ in range(latency_cycles):
                await RisingEdge(dut.clk_i)
                
            data = memory_mock.get(addr, 0xBADF00D)
            dut.m_rd_data_i.value = data
            dut.m_rd_rdy_i.value = 1

async def bus_slave_write(dut, memory_mock, latency_cycles):
    """Simula o lado de Escrita da Memória/NPU (Responde ao Consumidor)"""
    dut.m_wr_rdy_i.value = 0
    while True:
        await RisingEdge(dut.clk_i)
        dut.m_wr_rdy_i.value = 0
        await Timer(1, unit="ns")
        
        if dut.m_wr_vld_o.value == 1 and dut.m_wr_we_o.value == 1:
            addr = int(dut.m_wr_addr_o.value)
            wdata = int(dut.m_wr_data_o.value)
            
            # Simula Latência
            for _ in range(latency_cycles):
                await RisingEdge(dut.clk_i)
                
            memory_mock[addr] = wdata
            dut.m_wr_rdy_i.value = 1

def start_bus_slave(dut, memory_mock, latency_cycles=1):
    """Inicia as duas rotinas paralelamente."""
    cocotb.start_soon(bus_slave_read(dut, memory_mock, latency_cycles))
    cocotb.start_soon(bus_slave_write(dut, memory_mock, latency_cycles))

# ==============================================================================
# TESTES AUTOMATIZADOS
# ==============================================================================

@cocotb.test()
async def test_basic_memcpy(dut):
    log_header("Iniciando Teste Básico (Memcpy)")
    await setup_dut(dut)
    
    ram = {0x1000: 0xAAAA, 0x1004: 0xBBBB, 0x1008: 0xCCCC}
    start_bus_slave(dut, ram)
    
    await cfg_write(dut, REG_SRC, 0x1000)
    await cfg_write(dut, REG_DST, 0x2000)
    await cfg_write(dut, REG_CNT, 3)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    
    success = await wait_dma_done(dut)
    assert success, "Timeout no DMA!"
    
    assert ram.get(0x2000) == 0xAAAA, "Erro na Word 0"
    assert ram.get(0x2004) == 0xBBBB, "Erro na Word 1"
    assert ram.get(0x2008) == 0xCCCC, "Erro na Word 2"
    
    log_success("Memcpy Simples OK")


@cocotb.test()
async def test_fixed_dst_npu(dut):
    log_header("Iniciando Teste NPU (Fixed Dst)")
    await setup_dut(dut)
    ram = {0x3000: 10, 0x3004: 20, 0x3008: 30}
    
    npu_writes = []
    async def npu_monitor():
        while True:
            await RisingEdge(dut.clk_i)
            await Timer(1, unit="ns")
            if dut.m_wr_vld_o.value == 1 and dut.m_wr_we_o.value == 1 and dut.m_wr_rdy_i.value == 1:
                if int(dut.m_wr_addr_o.value) == 0x9000:
                    npu_writes.append(int(dut.m_wr_data_o.value))
    
    start_bus_slave(dut, ram)
    cocotb.start_soon(npu_monitor())
    
    await cfg_write(dut, REG_SRC, 0x3000)
    await cfg_write(dut, REG_DST, 0x9000)
    await cfg_write(dut, REG_CNT, 3)
    await cfg_write(dut, REG_CTRL, CTRL_START | CTRL_FIXED_DST)
    
    await wait_dma_done(dut)
    
    assert npu_writes == [10, 20, 30], f"NPU recebeu dados errados: {npu_writes}"
    log_success("Modo NPU (Fixed Destination) OK")


@cocotb.test()
async def test_edge_cases(dut):
    log_header("Iniciando Casos de Borda")
    await setup_dut(dut)
    ram = {0x100: 0xDEAD}
    start_bus_slave(dut, ram)
    
    await cfg_write(dut, REG_SRC, 0x100)
    await cfg_write(dut, REG_DST, 0x200)
    await cfg_write(dut, REG_CNT, 0)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    await Timer(50, unit="ns")
    
    assert ram.get(0x200) is None, "Erro: DMA escreveu algo com Count=0"
    log_success("Count 0 OK")
    
    await cfg_write(dut, REG_CNT, 1)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    await wait_dma_done(dut)
    
    assert ram.get(0x200) == 0xDEAD, "Erro: DMA falhou com Count=1"
    log_success("Count 1 OK")


@cocotb.test()
async def test_busy_protection(dut):
    log_header("Iniciando Teste de Proteção (Busy Write)")
    await setup_dut(dut)
    
    ram = {addr: 0 for addr in range(0x1000, 0x1050, 4)}
    start_bus_slave(dut, ram, latency_cycles=2)
    
    await cfg_write(dut, REG_SRC, 0x1000)
    await cfg_write(dut, REG_DST, 0x2000)
    await cfg_write(dut, REG_CNT, 20)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    
    await Timer(20, unit="ns")
    await cfg_write(dut, REG_DST, 0xBAD0)
    
    await wait_dma_done(dut)
    
    assert 0x2000 in ram, "Deveria ter escrito no endereço original"
    assert 0xBAD0 not in ram, "NÃO deveria ter escrito no endereço sabotado"
    log_success("Proteção de Escrita Busy OK")


@cocotb.test()
async def test_fuzzing(dut):
    log_header("Iniciando Fuzzing (50 Iterações)")
    await setup_dut(dut)
    
    ram = {}
    for addr in range(0x10000, 0x11000, 4):
        ram[addr] = random.randint(0, 0xFFFFFFFF)
        
    start_bus_slave(dut, ram, latency_cycles=1) 
    
    ITERATIONS = 50
    for i in range(ITERATIONS):
        src_offset = (random.randint(0, 200) * 4) + 0x10000
        dst_offset = (random.randint(0, 200) * 4) + 0x30000
        count      = random.randint(1, 16) 
        fixed      = random.choice([0, 1])
        
        await cfg_write(dut, REG_SRC, src_offset)
        await cfg_write(dut, REG_DST, dst_offset)
        await cfg_write(dut, REG_CNT, count)
        
        ctrl_val = CTRL_START | (CTRL_FIXED_DST if fixed else 0)
        await cfg_write(dut, REG_CTRL, ctrl_val)
        
        if not await wait_dma_done(dut):
            assert False, f"Fuzz #{i} Timeout!"

        if fixed:
            last_src_addr = src_offset + (count - 1) * 4
            expected_data = ram.get(last_src_addr, 0xBADF00D)
            actual_data   = ram.get(dst_offset)
            
            if actual_data != expected_data:
                msg = f"\n{Colors.FAIL}FALHA Fuzz #{i} (Mode Fixed){Colors.ENDC}\n" \
                      f"SrcAddr (Last): {hex(last_src_addr)}\n" \
                      f"DstAddr: {hex(dst_offset)}\n" \
                      f"Esperado: {hex(expected_data)}\nObtido:   {hex(actual_data)}"
                assert False, msg
        else:
            curr_src = src_offset
            curr_dst = dst_offset
            for k in range(count):
                expected_data = ram.get(curr_src, 0xBADF00D)
                actual_data   = ram.get(curr_dst)
                
                if actual_data != expected_data:
                    msg = f"\n{Colors.FAIL}FALHA Fuzz #{i} (Mode Incr) Index {k}{Colors.ENDC}\n" \
                          f"SrcAddr: {hex(curr_src)}\nDstAddr: {hex(curr_dst)}\n" \
                          f"Esperado: {hex(expected_data)}\nObtido:   {hex(actual_data)}"
                    assert False, msg
                
                curr_src += 4
                curr_dst += 4
                
    log_success(f"Fuzzing Completado: {ITERATIONS} iterações validadas")