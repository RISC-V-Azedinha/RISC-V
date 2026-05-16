# =====================================================================================================
# File: test_uart_controller.py
# =====================================================================================================
# 
# CONSIDERAÇÕES DE VERIFICAÇÃO E COBERTURA:
# 
# 1. Cobertura do Caminho de Transmissão (TX Path):
#    - Simula a escrita da CPU no registrador de dados (0x0).
#    - Verifica se a flag TX_BUSY levanta imediatamente para impedir sobrescritas acidentais.
#    - Decodifica passivamente a forma de onda serial gerada no pino físico `uart_tx_pin` 
#      (Start bit, 8 bits de dados, Stop bit) respeitando a latência do Baud Rate (115200 bps).
#    - Garante que a flag TX_BUSY é baixada apenas após a transmissão completa do bit de parada.
# 
# 2. Cobertura do Caminho de Recepção (RX Path):
#    - Injeta uma forma de onda serial assíncrona (bit a bit) no pino físico `uart_rx_pin`.
#    - Verifica se o controlador (Over-sampling) identifica o dado e levanta a flag RX_READY.
#    - Valida se a CPU consegue ler o byte exato armazenado na FIFO.
#    - Testa a integridade da FIFO exigindo que a CPU envie o comando de POP (escrita em 0x4) 
#      para limpar a flag, validando a separação entre leitura destrutiva e não-destrutiva.
# 
# 3. Cobertura do Bug de Double Write (Edge Guard):
#    - Focado na correção da anomalia temporal do barramento onde a CPU mantém o 'vld_i' 
#      por um ciclo extra após receber o 'rdy_o' (latência de pipeline).
#    - O teste força esse ciclo "cego". Se a UART for sensível a nível, ela acusará 'rdy_o' = 1 
#      no segundo ciclo e gravará lixo duplicado na FIFO.
#    - A simulação falha estritamente se o pulso de Ready não for atômico (exato 1 ciclo de clock).
# 
# =====================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ReadOnly, FallingEdge
from sim.core.single_cycle.include.test_utils import log_header, log_info, log_success, log_error, log_console

# =====================================================================================================
# CONFIGURAÇÕES GLOBAIS
# =====================================================================================================

CLK_PERIOD_NS  = 10
CYCLES_PER_BIT = 868 # 100 MHz / 115200 baud = 868.055... ciclos 
BIT_PERIOD_NS  = CYCLES_PER_BIT * CLK_PERIOD_NS

ADDR_DATA = 0x0
ADDR_STAT = 0x4

# =====================================================================================================
# HELPER FUNCTIONS (BFM & PHY)
# =====================================================================================================

async def setup_dut(dut):
    """Inicializa clock e sinais para evitar Warnings de Metavalue"""

    # Inicializa o Clock
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    
    # Inicializa entradas ANTES de qualquer borda de clock
    dut.rst.value = 1
    dut.vld_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    dut.uart_rx_pin.value = 1 # Idle High
    
    # Espera Reset
    for _ in range(5): await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def cpu_write(dut, addr, data):
    """Simula escrita no barramento aguardando o handshake (rdy_o)"""
    dut.addr_i.value = addr
    dut.data_i.value = data
    dut.vld_i.value  = 1
    dut.we_i.value   = 1
    
    # Aguarda a borda de clock até que o VHDL sinalize rdy_o = 1
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly() # Entra na fase de leitura segura (sinais estabilizados)
        if int(dut.rdy_o.value) == 1:
            break
            
    # Precisamos sair da fase ReadOnly aguardando o próximo clock 
    # ou usando um trigger como 'NextTimeStep' (vamos usar o clock para manter o ciclo)
    await RisingEdge(dut.clk)
    
    # Agora é seguro alterar os sinais
    dut.vld_i.value  = 0
    dut.we_i.value   = 0

async def cpu_read(dut, addr):
    """Simula leitura no barramento aguardando o handshake (rdy_o)"""
    dut.addr_i.value = addr
    dut.vld_i.value  = 1
    dut.we_i.value   = 0
    
    # Aguarda a borda de clock até que o VHDL sinalize rdy_o = 1
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly() # Entra na fase de leitura segura
        if int(dut.rdy_o.value) == 1:
            # Capturamos o dado ENQUANTO estamos na fase ReadOnly (seguro)
            val = int(dut.data_o.value)
            break
            
    # Saímos da fase ReadOnly
    await RisingEdge(dut.clk)
    
    # Agora é seguro alterar os sinais de controle
    dut.vld_i.value = 0
    
    return val

async def sniff_tx_pin(dut):
    """Monitora passivamente o pino TX físico e decodifica os bits"""
    while dut.uart_tx_pin.value == 1: await RisingEdge(dut.clk)
    
    # Pula para o meio do primeiro bit de dados (Start + 0.5 Data)
    # Start (1 bit) + 0.5 bit = 1.5 bits
    await Timer(int(BIT_PERIOD_NS * 1.5), unit="ns")
    
    byte_val = 0
    for i in range(8):
        byte_val |= (int(dut.uart_tx_pin.value) << i)
        await Timer(BIT_PERIOD_NS, unit="ns")
    return byte_val

async def drive_rx_pin(dut, byte_val):
    """Injeta dados seriais simulando um host externo no pino RX físico"""
    dut.uart_rx_pin.value = 0 # Start
    await Timer(BIT_PERIOD_NS, unit="ns")
    for i in range(8):
        dut.uart_rx_pin.value = (byte_val >> i) & 1
        await Timer(BIT_PERIOD_NS, unit="ns")
    dut.uart_rx_pin.value = 1 # Stop
    await Timer(BIT_PERIOD_NS, unit="ns")

# =====================================================================================================
# TESTE 1: TRANSMISSÃO (TX PATH)
# =====================================================================================================

@cocotb.test()
async def test_uart_tx_path(dut):
    log_header("Teste 1: Caminho de Transmissão (CPU -> TX Pin)")
    await setup_dut(dut)

    # Vetores de teste
    test_chars = [0x41, 0x55, 0xFF]

    for char_tx in test_chars:
        log_console(f"Enviando 0x{char_tx:02X}...")
        
        # 1. Inicia monitoramento
        sniffer = cocotb.start_soon(sniff_tx_pin(dut))
        
        # 2. CPU comanda envio
        await cpu_write(dut, ADDR_DATA, char_tx)
        
        # 3. Verifica Flag Busy (Imediato)
        await RisingEdge(dut.clk)
        status = await cpu_read(dut, ADDR_STAT)
        if not (status & 1):
            log_error("Flag BUSY não subiu!")
            assert False

        # 4. Aguarda resultado físico
        res = await sniffer
        if res != char_tx:
            log_error(f"Mismatch! CPU: 0x{char_tx:02X} -> Pino: 0x{res:02X}")
            assert False
            
        # 5. Espera Busy baixar
        # O sniffer retorna no MEIO do stop bit. Precisamos esperar o resto dele.
        await Timer(int(BIT_PERIOD_NS), unit="ns")
        
        status = await cpu_read(dut, ADDR_STAT)
        if (status & 1):
            log_error(f"Flag BUSY travada em 1 após tempo de guarda! (Status: {status})")
            assert False

        # Pequeno intervalo entre caracteres
        await Timer(2000, unit="ns")

    log_success("Caminho TX verificado com sucesso.")

# =====================================================================================================
# TESTE 2: RECEPÇÃO (RX PATH)
# =====================================================================================================

@cocotb.test()
async def test_uart_rx_path(dut):
    log_header("Teste 2: Caminho de Recepção (RX Pin -> CPU)")
    await setup_dut(dut)

    test_chars = [0x7B, 0x00, 0xAA]

    for char_rx in test_chars:
        log_console(f"Injetando 0x{char_rx:02X}...")

        # 1. Injeta sinal externo
        await drive_rx_pin(dut, char_rx)

        # 2. Espera processamento do HW
        await Timer(2000, unit="ns")

        # 3. CPU Checa Status
        status = await cpu_read(dut, ADDR_STAT)
        if not (status & 2): # Bit 1 = RX Ready
            log_error("Flag RX_READY não subiu!")
            assert False

        # 4. CPU Lê Dados
        val = await cpu_read(dut, ADDR_DATA)
        if val != char_rx:
            log_error(f"Mismatch! Pino: 0x{char_rx:02X} -> CPU: 0x{val:02X}")
            assert False

        # 5. Comando de POP da FIFO
        await cpu_write(dut, ADDR_STAT, 0x01) 

        # 6. CPU Checa se Status limpou
        status = await cpu_read(dut, ADDR_STAT)
        if (status & 2):
            log_error("Flag RX_READY não limpou após leitura e POP!")
            assert False
            
        await Timer(1000, unit="ns")

    log_success("Caminho RX verificado com sucesso.")

# =====================================================================================================
# TESTE 3: VALIDAÇÃO DO HANDSHAKE ATÔMICO (TDD)
# =====================================================================================================

@cocotb.test()
async def test_uart_double_write_bug(dut):
    """
    TDD: Verifica se a UART escreve duas vezes na FIFO de TX
    devido à falta do Edge Guard no handshake.
    """
    log_header("Teste 3: Double Write na FIFO de TX (UART)")
    
    # Inicializa perfeitamente o DUT (Relógio e Reset)
    await setup_dut(dut)
    
    # 1. CPU inicia a transação de escrita (TX) - Offset 0x0
    dut.addr_i.value = 0x0
    dut.data_i.value = 0xAA
    dut.we_i.value   = 1
    dut.vld_i.value  = 1
    
    # 2. CPU aguarda a UART responder
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_o.value) == 1:
            break
            
    # 3. CICLO CEGO: CPU viu RDY=1 nesta borda, mas só vai baixar o VLD no próximo ciclo.
    await RisingEdge(dut.clk)
    await ReadOnly()
    
    # Verifica o tempo que o rdy_o ficou em alto no ciclo "fantasma"
    rdy_no_ciclo_cego = int(dut.rdy_o.value)
    
    await FallingEdge(dut.clk)
    
    # CPU finalmente abaixa o VLD
    dut.vld_i.value = 0
    dut.we_i.value  = 0
    
    # Espera alguns ciclos para a lógica interna acomodar
    for _ in range(3):
        await RisingEdge(dut.clk)
        
    # 4. VERIFICAÇÃO DO BUG
    if rdy_no_ciclo_cego == 1:
        log_error("BUG DETECTADO: O rdy_o durou 2 ciclos seguidos! A FIFO deve ter ingerido 0xAA duplicado.")
        assert False, "Violação de Handshake: rdy_o estendido indevidamente (Level-sensitive)."
        
    log_success("Edge Guard validado na UART! Pulso atômico de 1 ciclo confirmado.")