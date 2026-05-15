# =====================================================================================================
# File: test_bus_interconnect.py
# =====================================================================================================

import cocotb
import random
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from sim.core.single_cycle.include.test_utils import log_header, log_success, log_error

# ==============================================================================
# AUXILIARES & GOLDEN MODEL
# ==============================================================================

async def setup_dut(dut):
    """Inicializa clock e reset no DUT."""
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    dut.rst_i.value = 1
    await Timer(15, "ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

async def settle():
    """Aguarda propagação combinacional inicial."""
    await Timer(1, "ns")

def model_addr_decode(addr):
    """Modelo Python da decodificação de endereço."""
    nibble = (addr >> 28) & 0xF
    if nibble == 0x0: return "ROM"
    if nibble == 0x1: return "UART"
    if nibble == 0x2: return "GPIO"
    if nibble == 0x3: return "VGA"
    if nibble == 0x4: return "DMA"
    if nibble == 0x5: return "CLINT" 
    if nibble == 0x6: return "PLIC"
    if nibble == 0x8: return "RAM"
    if nibble == 0x9: return "NPU"
    return "NONE"

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_sanity_check(dut):
    log_header("Teste 1: Sanity Check (Endereços Conhecidos via CPU)")
    await setup_dut(dut)
    
    dut.cpu_vld_i.value = 0
    dut.imem_vld_i.value = 0
    await settle()

    dut.cpu_addr_i.value = 0x8000AABB
    dut.cpu_vld_i.value  = 1
    await settle()
    
    assert dut.ram_vld_b_o.value == 1, "RAM não foi selecionada!"
    assert dut.rom_vld_b_o.value == 0, "ROM foi selecionada incorretamente!"
    log_success("Sanity Check OK")

@cocotb.test()
async def test_harvard_concurrency(dut):
    log_header("Teste 2: Harvard Split (Acesso Simultâneo IMem e CPU_DMem)")
    await setup_dut(dut)
    
    VAL_INSTRUCT = 0x11223344  
    VAL_DATA_OLD = 0x55667788  
    
    dut.rom_data_a_i.value = VAL_INSTRUCT
    dut.ram_data_b_i.value = VAL_DATA_OLD 
    
    dut.imem_addr_i.value = 0x00001000
    dut.imem_vld_i.value  = 1
    
    dut.cpu_addr_i.value = 0x80002000
    dut.cpu_vld_i.value  = 1
    dut.cpu_we_i.value   = 0xF
    
    await settle()
    
    assert dut.rom_vld_a_o.value == 1, "IMem não selecionou ROM"
    assert dut.ram_vld_b_o.value == 1, "CPU não selecionou RAM"
    assert int(dut.imem_data_o.value) == VAL_INSTRUCT, "IMem leu dado errado"
    
    log_success("Concorrência Harvard OK")

@cocotb.test()
async def test_fuzzing_map(dut):
    log_header("Teste 3: Fuzzing Completo (Decodificação da porta CPU)")
    await setup_dut(dut)
    ITERATIONS = 1000
    
    for i in range(ITERATIONS):
        addr = random.randint(0, 0xFFFFFFFF)
        
        dut.cpu_addr_i.value = addr
        dut.cpu_vld_i.value  = 1
        await settle()
        
        target = model_addr_decode(addr)
        
        signals = {
            "ROM":  int(dut.rom_vld_b_o.value),
            "UART": int(dut.uart_vld_o.value),
            "GPIO": int(dut.gpio_vld_o.value),
            "VGA":  int(dut.vga_vld_o.value),
            "DMA":  int(dut.dma_vld_o.value),
            "CLINT": int(dut.clint_vld_o.value), 
            "PLIC":  int(dut.plic_vld_o.value),  
            "RAM":  int(dut.ram_vld_b_o.value),
            "NPU":  int(dut.npu_vld_o.value)
        }
        
        for dev, state in signals.items():
            if dev == target:
                assert state == 1, f"FALHA Fuzz #{i}: {target} deveria estar ativo para addr {hex(addr)}"
            else:
                assert state == 0, f"FALHA Fuzz #{i}: {dev} ativou incorretamente para addr {hex(addr)}"
                    
        if target != "NONE":
            mock_data = random.randint(0, 0xFFFFFFFF)
            if target == "ROM":   dut.rom_data_b_i.value = mock_data; dut.rom_rdy_b_i.value = 1
            elif target == "RAM": dut.ram_data_b_i.value = mock_data; dut.ram_rdy_b_i.value = 1
            elif target == "DMA": dut.dma_data_i.value = mock_data;   dut.dma_rdy_i.value = 1
            
            await settle()
            
            if target in ["ROM", "RAM", "DMA"]:
                assert int(dut.cpu_data_o.value) == mock_data, f"Dado de retorno incorreto para {target}"
                assert int(dut.cpu_rdy_o.value) == 1, f"Ready não retornou para {target}"
        else:
            # Com a proteção Bus Fault, o barramento devolve ready forçado com data zero
            assert int(dut.cpu_rdy_o.value) == 1, f"Ready Bus Fault falhou (Unmapped: {hex(addr)})"
            assert int(dut.cpu_data_o.value) == 0, f"Data Bus Fault deveria ser 0 (Unmapped: {hex(addr)})"

    log_success(f"Fuzzing OK ({ITERATIONS} endereços)")

@cocotb.test()
async def test_crossbar_parallelism(dut):
    log_header("Teste 4: Crossbar - Paralelismo Total (Sem Colisão)")
    await setup_dut(dut)
    
    dut.cpu_vld_i.value = 0
    dut.dma_rd_vld_i.value = 0
    dut.dma_wr_vld_i.value = 0
    await settle()

    # CPU -> GPIO | DMA_RD -> RAM | DMA_WR -> NPU
    dut.cpu_addr_i.value = 0x20000000;    dut.cpu_vld_i.value = 1
    dut.dma_rd_addr_i.value = 0x80004000; dut.dma_rd_vld_i.value = 1
    dut.dma_wr_addr_i.value = 0x90000000; dut.dma_wr_vld_i.value = 1
    await settle()
    
    assert dut.gpio_vld_o.value == 1, "CPU não alcançou GPIO"
    assert dut.ram_vld_b_o.value == 1, "DMA_RD não alcançou RAM"
    assert dut.npu_vld_o.value == 1, "DMA_WR não alcançou NPU"
    
    dut.gpio_rdy_i.value = 1; dut.ram_rdy_b_i.value = 1; dut.npu_rdy_i.value = 1
    await settle()
    
    assert dut.cpu_rdy_o.value == 1, "CPU sofreu STALL indevido"
    assert dut.dma_rd_rdy_o.value == 1, "DMA_RD sofreu STALL indevido"
    assert dut.dma_wr_rdy_o.value == 1, "DMA_WR sofreu STALL indevido"
    
    log_success("Paralelismo do Crossbar Validado!")

@cocotb.test()
async def test_slave_arbitration(dut):
    log_header("Teste 5: Crossbar - Arbitragem no Escravo (Colisão)")
    await setup_dut(dut)
    
    # Colisão: CPU e DMA_RD tentam acessar a RAM
    dut.cpu_addr_i.value = 0x80001000;    dut.cpu_vld_i.value = 1
    dut.dma_rd_addr_i.value = 0x80002000; dut.dma_rd_vld_i.value = 1
    dut.ram_rdy_b_i.value = 1
    await settle()
    
    assert dut.ram_vld_b_o.value == 1, "RAM não ativada"
    assert dut.cpu_rdy_o.value == 1, "CPU sofreu STALL indevido (deve ter prioridade)"
    assert dut.dma_rd_rdy_o.value == 0, "DMA não sofreu STALL (Arbitragem falhou)"
    assert int(dut.ram_addr_b_o.value) == 0x80001000, "Mux roteou endereço errado"
    
    log_success("Arbitragem Validada!")