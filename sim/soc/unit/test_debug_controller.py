import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

# -----------------------------------------------------------------------------
# Constantes do Protocolo
# -----------------------------------------------------------------------------
CMD_HALT     = 0x01
CMD_RESUME   = 0x02
CMD_STEP     = 0x03
CMD_RESET    = 0x04
CMD_SET_BKP  = 0x05
CMD_CLR_BKP  = 0x06
CMD_READ_REG = 0x10

MAGIC_SEQ    = [0xCA, 0xFE, 0xBA, 0xBE]

# -----------------------------------------------------------------------------
# Utilitários de Log
# -----------------------------------------------------------------------------
def log_header(msg):
    cocotb.log.info("")
    cocotb.log.info("=================================================")
    cocotb.log.info(f">>> {msg}")
    cocotb.log.info("=================================================")

def log_info(msg):
    cocotb.log.info(f"ℹ️  {msg}")

def log_success(msg):
    cocotb.log.info(f"✅ {msg}")

def log_error(msg):
    cocotb.log.info(f"❌ {msg}")

# -----------------------------------------------------------------------------
# Drivers da UART (Bit-Banging Síncrono)
# -----------------------------------------------------------------------------
async def uart_send_byte(dut, data, bit_period):
    """Envia um byte para o uart_rx_i do DUT via bit-banging."""
    # Start bit (0)
    dut.uart_rx_i.value = 0
    for _ in range(bit_period): await RisingEdge(dut.clk_i)
    
    # Data bits (LSB first)
    for i in range(8):
        bit = (data >> i) & 1
        dut.uart_rx_i.value = bit
        for _ in range(bit_period): await RisingEdge(dut.clk_i)
        
    # Stop bit (1)
    dut.uart_rx_i.value = 1
    for _ in range(bit_period): await RisingEdge(dut.clk_i)

async def uart_recv_byte(dut, bit_period):
    """Recebe um byte do uart_tx_o do DUT via bit-banging."""
    # Aguarda o start bit (descida)
    while dut.uart_tx_o.value == 1:
        await RisingEdge(dut.clk_i)
        
    # Espera metade do período para amostrar no centro do bit
    for _ in range(bit_period // 2): await RisingEdge(dut.clk_i)
    
    data = 0
    # Pula o start bit e lê os 8 bits de dados
    for i in range(8):
        for _ in range(bit_period): await RisingEdge(dut.clk_i)
        bit = int(dut.uart_tx_o.value)
        data |= (bit << i)
        
    # Aguarda o stop bit para finalizar
    for _ in range(bit_period): await RisingEdge(dut.clk_i)
    return data

# -----------------------------------------------------------------------------
# Reset e Setup
# -----------------------------------------------------------------------------
async def setup_dut(dut):
    """Inicializa clock, reset e calcula o bit period."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    
    dut.rst_i.value = 1
    dut.uart_rx_i.value = 1  # Idle state da UART é 1
    dut.uart_rts_i.value = 1 # 1 = Debug Mode, 0 = Normal Mode
    dut.is_fetch_stage_i.value = 1
    dut.reg_data_i.value = 0
    dut.pc_i.value = 0
    
    for _ in range(3):
        await RisingEdge(dut.clk_i)
        
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)
    
    # Calcula o período do bit dinamicamente baseado nos generics do VHDL
    clk_freq = int(dut.CLK_FREQ.value)
    baud_rate = int(dut.BAUD_RATE.value)
    bit_period = clk_freq // baud_rate
    
    return bit_period

# -----------------------------------------------------------------------------
# Testes Unitários
# -----------------------------------------------------------------------------

@cocotb.test()
async def test_debug_entry_and_resume(dut):
    """Testa a sequência mágica de entrada (CA FE BA BE) e o comando RESUME"""
    
    log_header("Teste Debug: Magic Sequence & Resume")
    bit_period = await setup_dut(dut)
    
    assert dut.soc_en_o.value == 1, "❌ CPU deveria iniciar rodando livremente."
    
    log_info("Enviando Magic Sequence (CA FE BA BE)...")
    for byte in MAGIC_SEQ:
        await uart_send_byte(dut, byte, bit_period)
        
    # Dá alguns ciclos para a FSM processar o último byte
    for _ in range(10): await RisingEdge(dut.clk_i)
    
    # Como is_fetch_stage_i já está em 1, a FSM deve congelar a CPU imediatamente
    assert dut.soc_en_o.value == 0, "❌ soc_en_o não foi a 0 após o magic sequence!"
    log_success("CPU interceptada e congelada no estágio de Fetch.")
    
    log_info("Enviando comando RESUME...")
    await uart_send_byte(dut, CMD_RESUME, bit_period)
    
    for _ in range(10): await RisingEdge(dut.clk_i)
    assert dut.soc_en_o.value == 1, "❌ soc_en_o não retornou a 1 após RESUME!"
    log_success("CPU retomou a execução com sucesso.")


@cocotb.test()
async def test_debug_single_step(dut):
    """Testa o comando de passo único (Single Step)"""
    
    log_header("Teste Debug: Single Step")
    bit_period = await setup_dut(dut)
    
    # Entra no modo debug
    for byte in MAGIC_SEQ:
        await uart_send_byte(dut, byte, bit_period)
        
    for _ in range(10): await RisingEdge(dut.clk_i)
    assert dut.soc_en_o.value == 0, "Falha ao entrar no modo debug."
    
    log_info("Enviando comando STEP...")
    await uart_send_byte(dut, CMD_STEP, bit_period)
    for _ in range(10): await RisingEdge(dut.clk_i)
    
    # A CPU deve ser liberada (soc_en_o = 1)
    assert dut.soc_en_o.value == 1, "❌ CPU não foi liberada para o Step."
    log_success("CPU liberada para executar 1 instrução.")
    
    # Simula a CPU executando e indo para o próximo Fetch
    dut.is_fetch_stage_i.value = 0
    await RisingEdge(dut.clk_i)
    dut.is_fetch_stage_i.value = 1
    await RisingEdge(dut.clk_i)
    await ReadOnly()
    
    # Assim que atinge o novo Fetch, a FSM deve congelar a CPU novamente
    assert dut.soc_en_o.value == 0, "❌ CPU não foi recongelada após o Step!"
    log_success("Single Step concluído. CPU congelada no próximo Fetch.")


@cocotb.test()
async def test_debug_hw_breakpoint(dut):
    """Testa a configuração de Breakpoint, o hit e o aviso 0xBB (RTS=0)"""
    
    log_header("Teste Debug: Hardware Breakpoint & Alert")
    bit_period = await setup_dut(dut)
    
    # Entra no modo debug
    for byte in MAGIC_SEQ:
        await uart_send_byte(dut, byte, bit_period)
        
    BKP_ADDR = 0x00001004
    
    log_info(f"Configurando BKP no endereço {hex(BKP_ADDR)}...")
    await uart_send_byte(dut, CMD_SET_BKP, bit_period)
    # Envia o endereço Little Endian (B0, B1, B2, B3)
    await uart_send_byte(dut, (BKP_ADDR & 0xFF), bit_period)
    await uart_send_byte(dut, ((BKP_ADDR >> 8) & 0xFF), bit_period)
    await uart_send_byte(dut, ((BKP_ADDR >> 16) & 0xFF), bit_period)
    await uart_send_byte(dut, ((BKP_ADDR >> 24) & 0xFF), bit_period)
    
    log_info("Enviando RESUME e simulando desconexão do debugger (RTS=0)...")
    await uart_send_byte(dut, CMD_RESUME, bit_period)
    for _ in range(10): await RisingEdge(dut.clk_i)
    
    # Desconecta o cabo de debug (Modo normal de operação do SoC)
    dut.uart_rts_i.value = 0
    await RisingEdge(dut.clk_i)
    
    assert dut.soc_en_o.value == 1, "CPU não está rodando livremente."
    
    log_info("Simulando CPU chegando no endereço do Breakpoint...")
    dut.pc_i.value = BKP_ADDR
    dut.is_fetch_stage_i.value = 1
    
    await RisingEdge(dut.clk_i)
    await ReadOnly()
    
    # Verifica a interceptação de latência zero
    assert dut.soc_en_o.value == 0, "❌ BKP Falhou! A CPU passou reto pela armadilha."
    log_success("Hardware Breakpoint HIT! CPU congelada com latência zero.")
    
    log_info("Aguardando o alerta 0xBB (Isso levará cerca de 1500 ciclos)...")
    # Inicia a corotina de recepção (ela vai travar até chegar o byte)
    alert_byte = await uart_recv_byte(dut, bit_period)
    
    assert alert_byte == 0xBB, f"❌ Alerta incorreto. Esperado 0xBB, recebido {hex(alert_byte)}"
    log_success("Sinal de alerta 0xBB recebido com sucesso no TX!")