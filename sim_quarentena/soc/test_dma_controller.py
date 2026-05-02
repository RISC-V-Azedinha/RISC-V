# =====================================================================================================================
# File: test_dma_controller.py
# =====================================================================================================================
#
# >>> Descrição: Testbench para o Controlador DMA (Direct Memory Access)
#       Verifica transferências de memória, modo NPU (Fixed DST), casos de borda e robustez.
#
# =====================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from test_utils import log_header, log_success, Colors

# ==============================================================================
# CONSTANTES E MAPA DE REGISTRADORES
# ==============================================================================

# CSRs (Control & Status Registers Addr)

REG_SRC  = 0x0    # Registrador de fonte     (source)
REG_DST  = 0x4    # Registrador de destino   (destiny)
REG_CNT  = 0x8    # Registrador de contagem  (qtd de palavras de 32b à transferir)
REG_CTRL = 0xC    # Registrador de controle  (controle e status)

# BITWISE

CTRL_START     = 1 << 0   # Escrita
CTRL_FIXED_DST = 1 << 1   # Modo para burst (destino fixo)
CTRL_BUSY      = 1 << 0   # Leitura

# ==============================================================================
# AUXILIARES DE SIMULAÇÃO (DRIVERS E MONITORES)
# ==============================================================================

async def setup_dut(dut):
    """Inicializa clock e reseta o DUT"""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_i.value = 1
    dut.cfg_vld_i.value = 0
    dut.cfg_we_i.value = 0
    dut.m_rdy_i.value = 0
    
    await Timer(20, unit="ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

async def cfg_write(dut, addr, data):
    """Escreve nos registradores de configuração do DMA"""
    dut.cfg_addr_i.value = addr
    dut.cfg_data_i.value = data
    dut.cfg_vld_i.value = 1
    dut.cfg_we_i.value = 1
    
    await RisingEdge(dut.clk_i)
    
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

async def bus_slave_behavior(dut, memory_mock, latency_cycles=1):
    """
    Simula o comportamento do Barramento/Memória.
    Responde aos pedidos do Mestre (DMA) lendo/escrevendo no 'memory_mock'.
    """
    while True:
        await RisingEdge(dut.clk_i)
        dut.m_rdy_i.value = 0
        
        # Pequeno delay para evitar Race Conditions na simulação
        await Timer(1, unit="ns")
        
        if dut.m_vld_o.value == 1:
            addr = int(dut.m_addr_o.value)
            we   = int(dut.m_we_o.value)
            wdata = int(dut.m_data_o.value)
            
            # Simula Latência da Memória
            for _ in range(latency_cycles):
                await RisingEdge(dut.clk_i)
            
            if we == 0: # Leitura (DMA Lendo da RAM)
                data = memory_mock.get(addr, 0xBADF00D) # Retorna lixo se endereço inválido
                dut.m_data_i.value = data
                dut.m_rdy_i.value = 1
            else: # Escrita (DMA Escrevendo na RAM/NPU)
                memory_mock[addr] = wdata
                dut.m_rdy_i.value = 1

# ==============================================================================
# TESTES AUTOMATIZADOS
# ==============================================================================

@cocotb.test()
async def test_basic_memcpy(dut):
    # Teste 1: Cópia simples de Memória para Memória (Incremento)
    
    log_header("Iniciando Teste Básico (Memcpy)")
    
    await setup_dut(dut)
    
    # Prepara Memória Mock
    ram = {0x1000: 0xAAAA, 0x1004: 0xBBBB, 0x1008: 0xCCCC}
    cocotb.start_soon(bus_slave_behavior(dut, ram))
    
    # Configura Transferência
    await cfg_write(dut, REG_SRC, 0x1000)
    await cfg_write(dut, REG_DST, 0x2000)
    await cfg_write(dut, REG_CNT, 3)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    
    # Espera terminar
    success = await wait_dma_done(dut)
    assert success, "Timeout no DMA!"
    
    # Validação
    assert ram.get(0x2000) == 0xAAAA, "Erro na Word 0"
    assert ram.get(0x2004) == 0xBBBB, "Erro na Word 1"
    assert ram.get(0x2008) == 0xCCCC, "Erro na Word 2"
    
    log_success("Memcpy Simples OK")


@cocotb.test()
async def test_fixed_dst_npu(dut):
    # Teste 2: Modo Destino Fixo (Simulação de Escrita na NPU)
    
    log_header("Iniciando Teste NPU (Fixed Dst)")
    
    await setup_dut(dut)
    ram = {0x3000: 10, 0x3004: 20, 0x3008: 30}
    
    # Monitor específico para verificar escritas na NPU
    npu_writes = []
    async def npu_monitor():
        while True:
            await RisingEdge(dut.clk_i)
            await Timer(1, unit="ns")
            # Captura transação completa (Valid + Ready + Write)
            if dut.m_vld_o.value == 1 and dut.m_we_o.value == 1 and dut.m_rdy_i.value == 1:
                if int(dut.m_addr_o.value) == 0x9000:
                    npu_writes.append(int(dut.m_data_o.value))
    
    cocotb.start_soon(bus_slave_behavior(dut, ram))
    cocotb.start_soon(npu_monitor())
    
    # Configura DMA com Flag FIXED_DST
    await cfg_write(dut, REG_SRC, 0x3000)
    await cfg_write(dut, REG_DST, 0x9000) # Endereço FIFO NPU
    await cfg_write(dut, REG_CNT, 3)
    await cfg_write(dut, REG_CTRL, CTRL_START | CTRL_FIXED_DST)
    
    await wait_dma_done(dut)
    
    # Verifica ordem dos dados
    assert npu_writes == [10, 20, 30], f"NPU recebeu dados errados: {npu_writes}"
    
    log_success("Modo NPU (Fixed Destination) OK")


@cocotb.test()
async def test_edge_cases(dut):
    # Teste 3: Casos de Borda (Count 0, Count 1)
    
    log_header("Iniciando Casos de Borda")
    await setup_dut(dut)
    ram = {0x100: 0xDEAD}
    cocotb.start_soon(bus_slave_behavior(dut, ram))
    
    # Caso A: Count = 0
    await cfg_write(dut, REG_SRC, 0x100)
    await cfg_write(dut, REG_DST, 0x200)
    await cfg_write(dut, REG_CNT, 0)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    await Timer(50, unit="ns")
    
    assert ram.get(0x200) is None, "Erro: DMA escreveu algo com Count=0"
    log_success("Count 0 OK")
    
    # Caso B: Count = 1
    await cfg_write(dut, REG_CNT, 1)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    await wait_dma_done(dut)
    
    assert ram.get(0x200) == 0xDEAD, "Erro: DMA falhou com Count=1"
    log_success("Count 1 OK")


@cocotb.test()
async def test_busy_protection(dut):
    # Teste 4: Proteção de Escrita (Tentativa de sabotagem durante Busy)
    
    log_header("Iniciando Teste de Proteção (Busy Write)")
    await setup_dut(dut)
    
    # Cria transferência longa com latência maior para dar tempo de testar
    ram = {addr: 0 for addr in range(0x1000, 0x1050, 4)}
    cocotb.start_soon(bus_slave_behavior(dut, ram, latency_cycles=2))
    
    await cfg_write(dut, REG_SRC, 0x1000)
    await cfg_write(dut, REG_DST, 0x2000)
    await cfg_write(dut, REG_CNT, 20)
    await cfg_write(dut, REG_CTRL, CTRL_START)
    
    await Timer(20, unit="ns") # Espera começar
    
    # Tenta mudar o endereço de destino enquanto o DMA está rodando
    await cfg_write(dut, REG_DST, 0xBAD0)
    
    await wait_dma_done(dut)
    
    assert 0x2000 in ram, "Deveria ter escrito no endereço original"
    assert 0xBAD0 not in ram, "NÃO deveria ter escrito no endereço sabotado"
    
    log_success("Proteção de Escrita Busy OK")


@cocotb.test()
async def test_fuzzing(dut):
    # Teste 5: Estresse (Fuzzing) com 50 transações aleatórias
    
    log_header("Iniciando Fuzzing (50 Iterações)")
    await setup_dut(dut)
    
    # Mock RAM Gigante
    ram = {}
    for addr in range(0x10000, 0x11000, 4):
        ram[addr] = random.randint(0, 0xFFFFFFFF)
        
    # Latência 1 para simulação robusta
    cocotb.start_soon(bus_slave_behavior(dut, ram, latency_cycles=1)) 
    
    ITERATIONS = 50
    
    for i in range(ITERATIONS):
        # Gera parâmetros aleatórios
        src_offset = (random.randint(0, 200) * 4) + 0x10000
        dst_offset = (random.randint(0, 200) * 4) + 0x30000
        count      = random.randint(1, 16) 
        fixed      = random.choice([0, 1])
        
        # Configura DMA
        await cfg_write(dut, REG_SRC, src_offset)
        await cfg_write(dut, REG_DST, dst_offset)
        await cfg_write(dut, REG_CNT, count)
        
        ctrl_val = CTRL_START | (CTRL_FIXED_DST if fixed else 0)
        await cfg_write(dut, REG_CTRL, ctrl_val)
        
        # Aguarda fim
        if not await wait_dma_done(dut):
            assert False, f"Fuzz #{i} Timeout!"

        # Verificação dos Dados
        if fixed:
            # Em modo fixo, memory_mock[DST] só tem o ÚLTIMO valor escrito
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
            # Em modo incremental, verificamos array completo
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