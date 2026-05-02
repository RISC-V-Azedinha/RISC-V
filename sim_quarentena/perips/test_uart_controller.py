# =====================================================================================================
# File: test_uart_controller.py
# =====================================================================================================
#
# >>> Descrição: Testbench de Integração para o UART Controller.
#     Dividido em testes específicos para o caminho de TX e RX.
#
# =====================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from test_utils import log_header, log_info, log_success, log_error, log_console

# =====================================================================================================
# CONFIGURAÇÕES GLOBAIS
# =====================================================================================================

CLK_PERIOD_NS = 10
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
    dut.sel_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    dut.uart_rx_pin.value = 1 # Idle High
    
    # Espera Reset
    for _ in range(5): await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def cpu_write(dut, addr, data):
    """Simula escrita no barramento"""
    dut.addr_i.value = addr
    dut.data_i.value = data
    dut.sel_i.value  = 1
    dut.we_i.value   = 1
    await RisingEdge(dut.clk)
    dut.sel_i.value  = 0
    dut.we_i.value   = 0

async def cpu_read(dut, addr):
    """Simula leitura no barramento"""
    dut.addr_i.value = addr
    dut.sel_i.value  = 1
    dut.we_i.value   = 0
    await RisingEdge(dut.clk)
    val = int(dut.data_o.value)
    dut.sel_i.value = 0
    return val

async def sniff_tx_pin(dut):
    """Monitora o pino TX físico"""
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
    """Injeta dados no pino RX físico"""
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
        # Antes era 1000ns, agora vamos esperar 1 bit inteiro (8680ns) para garantir.
        
        await Timer(int(BIT_PERIOD_NS), unit="ns")   # <--- CORREÇÃO AQUI
        
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

        # 5. CPU Checa se Status limpou
        status = await cpu_read(dut, ADDR_STAT)
        if (status & 2):
            log_error("Flag RX_READY não limpou após leitura!")
            assert False
            
        await Timer(1000, unit="ns")

    log_success("Caminho RX verificado com sucesso.")