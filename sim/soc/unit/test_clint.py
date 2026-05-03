import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

# -----------------------------------------------------------------------------
# Endereços do CLINT (Mapeamento de 5 bits)
# -----------------------------------------------------------------------------
ADDR_MSIP       = 0x00
ADDR_MTIMECMP_L = 0x08
ADDR_MTIMECMP_H = 0x0C
ADDR_MTIME_L    = 0x10
ADDR_MTIME_H    = 0x14

# -----------------------------------------------------------------------------
# Utilitários de Log
# -----------------------------------------------------------------------------
def log_header(msg):
    cocotb.log.info(f"")
    cocotb.log.info(f"=================================================")
    cocotb.log.info(f">>> {msg}")
    cocotb.log.info(f"=================================================")

def log_info(msg):
    cocotb.log.info(f"ℹ️  {msg}")

def log_success(msg):
    cocotb.log.info(f"✅ {msg}")

def log_error(msg):
    cocotb.log.info(f"❌ {msg}")

# -----------------------------------------------------------------------------
# Utilitários de Barramento
# -----------------------------------------------------------------------------
async def bus_write(dut, addr, data):
    """Escrita de 1 ciclo exato no barramento (MMIO)."""
    dut.addr_i.value = addr
    dut.data_i.value = data
    dut.we_i.value = 1
    dut.vld_i.value = 1
    
    await RisingEdge(dut.clk_i)
    
    while dut.rdy_o.value == 0:
        await RisingEdge(dut.clk_i)
        
    dut.vld_i.value = 0
    dut.we_i.value = 0
    await RisingEdge(dut.clk_i)

async def bus_read(dut, addr):
    """Leitura de 1 ciclo exato no barramento (MMIO)."""
    dut.addr_i.value = addr
    dut.we_i.value = 0
    dut.vld_i.value = 1
    
    await RisingEdge(dut.clk_i)
    
    while dut.rdy_o.value == 0:
        await RisingEdge(dut.clk_i)
        
    # No CLINT, data_o é um registrador síncrono. O valor já está 
    # cravado e estável após a borda. Zero necessidade de ReadOnly!
    data = int(dut.data_o.value)
    
    dut.vld_i.value = 0
    await RisingEdge(dut.clk_i)
    
    return data

# -----------------------------------------------------------------------------
# Reset e Setup
# -----------------------------------------------------------------------------
async def setup_dut(dut):
    """Inicializa clock e aplica reset."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    
    dut.rst_i.value = 1
    dut.soc_en_i.value = 0  
    dut.addr_i.value = 0
    dut.data_i.value = 0
    dut.we_i.value = 0
    dut.vld_i.value = 0
    
    for _ in range(3):
        await RisingEdge(dut.clk_i)
        
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

# -----------------------------------------------------------------------------
# Testes Unitários
# -----------------------------------------------------------------------------

@cocotb.test()
async def test_clint_software_irq(dut):
    """Verifica a geração e limpeza da interrupção de software (MSIP)"""
    
    log_header("Teste CLINT: Interrupção de Software (MSIP)")
    await setup_dut(dut)
    
    log_info("Escrevendo 1 no MSIP...")
    await bus_write(dut, ADDR_MSIP, 1)
    
    # Sincroniza a leitura combinacional do pino de IRQ
    await ReadOnly()
    assert dut.irq_soft_o.value == 1, "❌ irq_soft_o não foi a 1 após escrita no MSIP!"
    log_success("irq_soft_o foi levantado com sucesso.")
    
    # IMPORTANTE: Avança o clock para escapar do ReadOnly antes de injetar novos sinais
    await RisingEdge(dut.clk_i)
    
    log_info("Limpando MSIP (escrevendo 0)...")
    await bus_write(dut, ADDR_MSIP, 0)
    
    await ReadOnly()
    assert dut.irq_soft_o.value == 0, "❌ irq_soft_o não baixou após limpar o MSIP!"
    log_success("Interrupção de software limpa com sucesso.")


@cocotb.test()
async def test_clint_timer_irq(dut):
    """Verifica o incremento do MTIME e o disparo via MTIMECMP"""
    
    log_header("Teste CLINT: Interrupção de Timer (MTIME >= MTIMECMP)")
    await setup_dut(dut)
    
    TARGET_TICKS = 15
    
    log_info("Pausando soc_en_i para configurar os registradores de 64 bits...")
    dut.soc_en_i.value = 0
    await RisingEdge(dut.clk_i)
    
    await bus_write(dut, ADDR_MTIME_L, 0)
    await bus_write(dut, ADDR_MTIME_H, 0)
    
    await bus_write(dut, ADDR_MTIMECMP_L, TARGET_TICKS)
    await bus_write(dut, ADDR_MTIMECMP_H, 0)
    
    log_info(f"Ativando soc_en_i. Aguardando {TARGET_TICKS} ciclos de clock...")
    dut.soc_en_i.value = 1
    
    # Loop de avanço do tempo
    for i in range(TARGET_TICKS):
        await RisingEdge(dut.clk_i)
        
        # Sincroniza para checar a lógica combinacional de > e <
        await ReadOnly()
        
        if i < (TARGET_TICKS - 1):
            assert dut.irq_timer_o.value == 0, f"❌ Interrupção disparou prematuramente no tick {i}!"
        else:
            assert dut.irq_timer_o.value == 1, "❌ irq_timer_o não disparou após atingir o target!"
            
    log_success(f"irq_timer_o disparado no tick exato ({TARGET_TICKS}).")
    
    # IMPORTANTE: Destrava o ReadOnly da última iteração do loop
    await RisingEdge(dut.clk_i)
    
    log_info("Empurrando MTIMECMP para o futuro (limpando a IRQ)...")
    dut.soc_en_i.value = 0 
    await bus_write(dut, ADDR_MTIMECMP_L, 0xFFFFFFFF)
    dut.soc_en_i.value = 1
    
    await ReadOnly()
    assert dut.irq_timer_o.value == 0, "❌ irq_timer_o não baixou após estender o MTIMECMP!"
    log_success("Fluxo de Timer validado com sucesso!")


@cocotb.test()
async def test_clint_read_64bit(dut):
    """Verifica se a leitura dos registradores MTIME está retornando os valores certos"""
    
    log_header("Teste CLINT: Leitura de 64 bits (MTIME)")
    await setup_dut(dut)
    
    TEST_VAL_L = 0xCAFEBABE
    TEST_VAL_H = 0xDEADBEEF
    
    log_info("Injetando valor de teste no MTIME...")
    dut.soc_en_i.value = 0 
    await RisingEdge(dut.clk_i) 
    
    await bus_write(dut, ADDR_MTIME_L, TEST_VAL_L)
    await bus_write(dut, ADDR_MTIME_H, TEST_VAL_H)
    
    log_info("Lendo de volta...")
    read_l = await bus_read(dut, ADDR_MTIME_L)
    read_h = await bus_read(dut, ADDR_MTIME_H)
    
    assert read_l == TEST_VAL_L, f"❌ Erro leitura MTIME_L. Exp: {hex(TEST_VAL_L)}, Got: {hex(read_l)}"
    assert read_h == TEST_VAL_H, f"❌ Erro leitura MTIME_H. Exp: {hex(TEST_VAL_H)}, Got: {hex(read_h)}"
    
    log_success("Leitura/Escrita de 64-bits operando perfeitamente!")