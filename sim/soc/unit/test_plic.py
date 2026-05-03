import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

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
# Utilitários de Barramento (CORRIGIDOS)
# -----------------------------------------------------------------------------
async def bus_write(dut, addr, data):
    """Realiza uma escrita de 1 ciclo exato no barramento."""
    dut.Addr_i.value = addr
    dut.Data_i.value = data
    dut.We_i.value = 1
    dut.Vld_i.value = 1
    
    # Borda 1: O PLIC enxerga Vld_i=1 e processa a escrita internamente
    await RisingEdge(dut.Clk_i)
    
    # Abaixa Vld_i IMEDIATAMENTE para não disparar a escrita 2 vezes!
    dut.Vld_i.value = 0
    dut.We_i.value = 0
    
    # Borda 2: Sincroniza e libera o simulador para o próximo comando
    await RisingEdge(dut.Clk_i)

async def bus_read(dut, addr):
    """Realiza uma leitura de 1 ciclo exato no barramento."""
    dut.Addr_i.value = addr
    dut.We_i.value = 0
    dut.Vld_i.value = 1
    
    # Borda 1: O PLIC enxerga Vld_i=1 e processa o Claim
    await RisingEdge(dut.Clk_i)
    
    # Abaixa Vld_i IMEDIATAMENTE para não dar um "Double Claim" nas interrupções!
    dut.Vld_i.value = 0
    
    # Espera os delta-cycles do GHDL atualizarem os pinos de saída
    await ReadOnly()
    data = int(dut.Data_o.value)
    
    # Borda 2: Avança o clock para sair do modo ReadOnly (evita crash do Python)
    await RisingEdge(dut.Clk_i)
    
    return data

# -----------------------------------------------------------------------------
# Reset e Setup
# -----------------------------------------------------------------------------
async def setup_dut(dut):
    """Inicializa clock e aplica reset."""
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    
    dut.Reset_i.value = 1
    dut.Addr_i.value = 0
    dut.Data_i.value = 0
    dut.We_i.value = 0
    dut.Vld_i.value = 0
    dut.Irq_Sources_i.value = 0
    
    for _ in range(3):
        await RisingEdge(dut.Clk_i)
        
    dut.Reset_i.value = 0
    await RisingEdge(dut.Clk_i)

# -----------------------------------------------------------------------------
# Testes Unitários
# -----------------------------------------------------------------------------

@cocotb.test()
async def test_plic_basic_flow(dut):
    """Teste do fluxo básico: Setup -> IRQ -> Claim -> Complete"""
    
    log_header("Teste PLIC: Fluxo Básico de Interrupção")
    await setup_dut(dut)
    
    IRQ_ID = 1
    PRIORITY = 5
    THRESHOLD = 2
    
    log_info(f"Configurando Source {IRQ_ID}: Prio={PRIORITY}, Threshold={THRESHOLD}")
    
    await bus_write(dut, 0x000000 + (IRQ_ID * 4), PRIORITY)
    await bus_write(dut, 0x002000, (1 << IRQ_ID))
    await bus_write(dut, 0x200000, THRESHOLD)
    
    log_info("Disparando IRQ_Sources_i[1]...")
    dut.Irq_Sources_i.value = (1 << IRQ_ID)
    await RisingEdge(dut.Clk_i)
    await RisingEdge(dut.Clk_i)
    
    assert dut.Irq_Req_o.value == 1, "❌ PLIC falhou em levantar Irq_Req_o para o Core!"
    log_success("Irq_Req_o levantado corretamente.")
    
    log_info("Simulando Core realizando o Claim...")
    claimed_id = await bus_read(dut, 0x200004)
    assert claimed_id == IRQ_ID, f"❌ Claim retornou ID incorreto. Exp={IRQ_ID}, Got={claimed_id}"
    log_success(f"Claim bem sucedido (ID {claimed_id}).")
    
    assert dut.Irq_Req_o.value == 0, "❌ Irq_Req_o não caiu após o Claim!"
    
    log_info("Simulando ISR apagando a flag de interrupção do periférico...")
    dut.Irq_Sources_i.value = 0
    await RisingEdge(dut.Clk_i)

    log_info("Simulando Core realizando o Complete...")
    await bus_write(dut, 0x200004, claimed_id)
    
    log_success("Fluxo básico validado com sucesso!")


@cocotb.test()
async def test_plic_arbitration(dut):
    """Teste de arbitragem de prioridades simultâneas"""
    
    log_header("Teste PLIC: Arbitragem de Prioridades")
    await setup_dut(dut)
    
    await bus_write(dut, 0x000000 + (2 * 4), 3)
    await bus_write(dut, 0x000000 + (3 * 4), 7)
    
    await bus_write(dut, 0x002000, 0x0C)
    await bus_write(dut, 0x200000, 0)
    
    log_info("Disparando Sources 2 e 3 simultaneamente...")
    dut.Irq_Sources_i.value = 0x0C 
    await RisingEdge(dut.Clk_i)
    await RisingEdge(dut.Clk_i)
    
    claimed_1 = await bus_read(dut, 0x200004)
    assert claimed_1 == 3, f"❌ PLIC arbitrou errado! Esperado ID 3 (Prio 7), mas veio ID {claimed_1}"
    log_success("Primeiro Claim retornou ID 3 (Prioridade mais alta).")
    
    log_info("ISR limpando a flag do periférico 3...")
    dut.Irq_Sources_i.value = 0x04 
    await RisingEdge(dut.Clk_i)
    
    # Complete do ID 3 (O PLIC vai baixar o Gateway Mask e a linha de IRQ do Core vai subir pro ID 2)
    await bus_write(dut, 0x200004, claimed_1)
    
    assert dut.Irq_Req_o.value == 1, "❌ PLIC não gerou IRQ para o Source 2 que ficou pendente!"
    
    claimed_2 = await bus_read(dut, 0x200004)
    assert claimed_2 == 2, f"❌ Segundo claim falhou. Esperado ID 2, veio ID {claimed_2}"
    log_success("Segundo Claim retornou ID 2.")
    
    log_info("ISR limpando a flag do periférico 2...")
    dut.Irq_Sources_i.value = 0
    await RisingEdge(dut.Clk_i)

    # Complete do ID 2
    await bus_write(dut, 0x200004, claimed_2)
    
    assert dut.Irq_Req_o.value == 0, "❌ Irq_Req_o deveria estar em 0 após atuar em todas."
    
    log_success("Arbitragem validada com sucesso!")