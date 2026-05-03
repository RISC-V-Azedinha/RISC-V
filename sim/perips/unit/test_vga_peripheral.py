# ============================================================================================================================================================
# File: test_vga_peripheral.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench de Integração para o Periférico VGA.
#       Verifica o handshake MMIO, leitura do registrador de status (VSYNC) 
#       e o caminho de dados da CPU -> VRAM -> Pinos físicos RGB do monitor.
#
# ============================================================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
from sim.core.single_cycle.include.test_utils import log_header, log_info, log_success, log_error

# =====================================================================================================================
# CONSTANTES (Memory Map & Config)
# =====================================================================================================================

CLK_PERIOD_NS = 10         # 100 MHz
ADDR_VSYNC    = 0x1FFFF    # Endereço reservado para leitura do VSYNC

# =====================================================================================================================
# FUNÇÕES DE BARRAMENTO (MMIO)
# =====================================================================================================================

async def setup_dut(dut):
    """Inicializa clock e sinais do barramento."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    
    dut.rst.value = 1
    dut.vld_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    
    for _ in range(5):
        await RisingEdge(dut.clk)
        
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def bus_write(dut, address, data):
    """Realiza uma escrita no barramento aguardando o handshake (rdy_o)"""
    dut.addr_i.value = address
    dut.data_i.value = data
    dut.vld_i.value  = 1
    dut.we_i.value   = 1
    
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_o.value) == 1:
            break
            
    await RisingEdge(dut.clk)
    
    dut.vld_i.value  = 0
    dut.we_i.value   = 0

async def bus_read(dut, address):
    """Realiza uma leitura no barramento aguardando o handshake (rdy_o)"""
    dut.addr_i.value = address
    dut.vld_i.value  = 1
    dut.we_i.value   = 0
    
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_o.value) == 1:
            val = dut.data_o.value.to_unsigned()
            break
            
    await RisingEdge(dut.clk)
    
    dut.vld_i.value = 0
    return val

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_vga_registers(dut):
    """Verifica a leitura do registrador de status do VSYNC."""
    log_header("Teste 1: Leitura do Registrador VSYNC")
    await setup_dut(dut)
    
    log_info(f"Lendo endereço de status 0x{ADDR_VSYNC:X}...")
    
    # Executa a leitura
    val = await bus_read(dut, ADDR_VSYNC)
    
    # O pino VSYNC físico deve refletir o que foi lido pela CPU no bit 0
    vsync_pin = dut.vga_vs_o.value
    
    if (val & 0x1) != vsync_pin:
        log_error(f"Mismatch! CPU leu {val & 0x1}, mas pino físico é {vsync_pin}")
        assert False
        
    log_success(f"Leitura de Status OK! (VSYNC = {vsync_pin})")


@cocotb.test()
async def test_vga_pixel_output(dut):
    """Escreve um pixel na VRAM e monitora os pinos VGA para validar a saída RGB."""
    log_header("Teste 2: Caminho de Dados CPU -> VRAM -> Pinos RGB")
    await setup_dut(dut)
    
    # Vamos escrever no Endereço 50 da VRAM.
    # Como y_scaled = 0, x_scaled = 50, o pixel vai aparecer fisicamente em X=100.
    target_addr = 50
    
    # Cor escolhida: 0xE3 (Binário: 111_000_11)
    # R (111) -> R_o deve ser "1110" (0xE)
    # G (000) -> G_o deve ser "0000" (0x0)
    # B (11)  -> B_o deve ser "1100" (0xC)
    color_byte = 0xE3
    
    # Devido à lógica de alinhamento: addr_i(1 downto 0) para 50 (b110010) é "10".
    # Logo, o byte precisa estar em data_i(23 downto 16)
    aligned_data = color_byte << 16
    
    log_info(f"Escrevendo cor 0x{color_byte:X} na VRAM (Endereço {target_addr})...")
    await bus_write(dut, target_addr, aligned_data)
    
    log_info("Aguardando o varredor VGA alcançar o Pixel X=100 (aprox. 400 ciclos)...")
    
    pixel_found = False
    
    # Monitora as saídas RGB. A VRAM inicia com 0, então os pinos ficarão zerados 
    # até o varredor passar pelo endereço 50.
    for _ in range(1000): # Timeout de 1000 ciclos (sobra tempo)
        await RisingEdge(dut.clk)
        await ReadOnly()
        
        r_val = int(dut.vga_r_o.value)
        g_val = int(dut.vga_g_o.value)
        b_val = int(dut.vga_b_o.value)
        
        # Se qualquer pino for diferente de 0, o pixel de teste chegou à tela!
        if r_val != 0 or g_val != 0 or b_val != 0:
            if r_val == 0xE and g_val == 0x0 and b_val == 0xC:
                log_success(f"Pixel gerado corretamente nos pinos! (R:0x{r_val:X}, G:0x{g_val:X}, B:0x{b_val:X})")
                pixel_found = True
                break
            else:
                log_error(f"Pixel com cor incorreta! Obtido: R:0x{r_val:X}, G:0x{g_val:X}, B:0x{b_val:X}")
                assert False
                
        # Pequeno passo para sair do ciclo ReadOnly
        await RisingEdge(dut.clk)
                
    if not pixel_found:
        log_error("Timeout: O controlador VGA não gerou os sinais de cor no tempo esperado!")
        assert False