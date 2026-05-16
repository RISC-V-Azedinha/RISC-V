# =====================================================================================================================
# File: test_vga_peripheral.py
# =====================================================================================================================
#
# CONSIDERAÇÕES DE VERIFICAÇÃO E COBERTURA:
# 
# 1. Leitura de Status (VSYNC):
#    - Verifica se a CPU consegue ler corretamente o registrador reservado 0x1FFFF.
#    - O bit 0 do dado lido deve refletir perfeitamente o estado do pino físico `vga_vs_o`.
#
# 2. Caminho de Dados de Pixel (CPU -> VRAM -> Monitor):
#    - Simula a gravação de um pixel específico (Cor 0xE3) em um endereço conhecido da VRAM.
#    - Aguarda o varredor interno do VGA (Sync Generator) alcançar a coordenada física correspondente.
#    - Decodifica a saída combinacional dos pinos RGB para garantir que o byte gravado na VRAM 
#      foi corretamente expandido para os 12 bits do padrão VGA do monitor.
#
# 3. Cobertura do Bug de Double Write (Edge Guard):
#   - Focado na correção da anomalia temporal do barramento onde a CPU estende o 'vld_i'.
#   - O teste força o "ciclo cego" e monitora tanto a duração do 'rdy_o' quanto o pulso de 
#     Write Enable da BRAM interna ('s_vram_we'). Ambos devem durar estritamente 1 ciclo.
#
# =====================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge
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
    val = await bus_read(dut, ADDR_VSYNC)
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
    
    target_addr = 50
    color_byte = 0xE3
    aligned_data = color_byte << 16
    
    log_info(f"Escrevendo cor 0x{color_byte:X} na VRAM (Endereço {target_addr})...")
    await bus_write(dut, target_addr, aligned_data)
    log_info("Aguardando o varredor VGA alcançar o Pixel X=100 (aprox. 400 ciclos)...")
    
    pixel_found = False
    for _ in range(1000):
        await RisingEdge(dut.clk)
        await ReadOnly()
        
        r_val = int(dut.vga_r_o.value)
        g_val = int(dut.vga_g_o.value)
        b_val = int(dut.vga_b_o.value)
        
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

@cocotb.test()
async def test_vga_double_write_bug(dut):
    """
    TDD: Verifica se o VGA mantém o Write Enable da VRAM (s_vram_we) 
    ou o rdy_o por 2 ciclos devido à falta do Edge Guard.
    """
    log_header("Teste 3: Double Write no VGA e VRAM (TDD)")
    await setup_dut(dut)
    
    # 1. CPU inicia a transação de escrita na VRAM
    dut.addr_i.value = 0x0
    dut.data_i.value = 0xFFFFFFFF
    dut.we_i.value   = 1
    dut.vld_i.value  = 1
    
    # 2. Aguarda a resposta (Handshake)
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_o.value) == 1:
            break
            
    # 3. COMPORTAMENTO REAL DO MESTRE SÍNCRONO
    # O mestre abaixa os sinais na exata borda de clock em que a transação termina.
    await RisingEdge(dut.clk)
    
    # Alteramos a entrada IMEDIATAMENTE (antes de ler os combinacionais)
    dut.vld_i.value = 0
    dut.we_i.value  = 0
    
    # Agora sim, entramos na fase de leitura estabilizada
    await ReadOnly()
    
    rdy_no_ciclo_cego = int(dut.rdy_o.value)
    we_no_ciclo_cego  = int(dut.s_vram_we.value)
    
    # 4. VERIFICAÇÃO DO BUG
    if rdy_no_ciclo_cego == 1:
        log_error("BUG DETECTADO: O rdy_o durou 2 ciclos seguidos!")
        assert False, "Violação de Handshake: rdy_o estendido indevidamente."
        
    if we_no_ciclo_cego == 1:
        log_error("BUG DETECTADO: O s_vram_we (VRAM Write Enable) durou 2 ciclos seguidos!")
        assert False, "Double Write: A BRAM está sendo gravada duas vezes."
        
    log_success("Edge Guard validado! O rdy_o e o acesso à VRAM duraram exato 1 ciclo.")