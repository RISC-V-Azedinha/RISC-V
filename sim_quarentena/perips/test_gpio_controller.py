# ============================================================================================================================================================
# File: test_gpio_controller.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para o Controlador de GPIO (General Purpose I/O).
#       Verifica a escrita em registradores de LEDs e a leitura de registradores de Switches.
#       Inclui testes de reset, integridade de dados e testes aleatórios.
#
# ============================================================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# Importa utilitários compartilhados
from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# CONSTANTES (Memory Map)
# =====================================================================================================================

ADDR_LEDS    = 0x0      # Offset 0: Registrador de LEDs (R/W)
ADDR_SWITCHES= 0x4      # Offset 4: Registrador de Switches (RO)
MASK_16_BIT  = 0xFFFF   # Máscara para isoolar os dados úteis dos 32 bits

# =====================================================================================================================
# AUXILIARY FUNCTIONS (Bus Operations)
# =====================================================================================================================

async def reset_dut(dut):
    """Reseta o módulo e inicializa sinais."""
    dut.rst.value = 1
    dut.sel_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    dut.gpio_sw.value = 0
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def bus_write(dut, address, data):
    """Realiza uma escrita no barramento simulado."""
    dut.sel_i.value = 1
    dut.we_i.value  = 1
    dut.addr_i.value = address
    dut.data_i.value = data
    
    await RisingEdge(dut.clk) # A escrita acontece na borda de subida
    
    # Desabilita o barramento no ciclo seguinte
    dut.sel_i.value = 0
    dut.we_i.value  = 0
    
    # Pequeno delay para propagação combinacional
    await settle()

async def bus_read(dut, address):
    """Realiza uma leitura no barramento simulado."""
    dut.sel_i.value = 1
    dut.we_i.value  = 0
    dut.addr_i.value = address
    
    await settle() 

    val = dut.data_o.value.to_unsigned()
    
    await RisingEdge(dut.clk)
    dut.sel_i.value = 0
    
    return val

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):
    """Testes dirigidos para verificar funcionalidade básica dos LEDs e Switches (16 bits)."""
    
    log_header("Testes Dirigidos - GPIO Controller (16-bit)")
    
    # 1. Setup do Clock (100 MHz = 10ns)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    
    # 2. Reset
    await reset_dut(dut)
    log_info("Reset concluído. Verificando estado inicial...")
    
    # Verifica se LEDs iniciaram zerados
    if dut.gpio_leds.value != 0:
        log_error(f"Falha no Reset: LEDs deveriam ser 0, lido {dut.gpio_leds.value}")
        assert False
    log_success("Reset OK: LEDs iniciados em 0")

    # -------------------------------------------------------------------------
    # Teste A: Escrita nos LEDs (Write)
    # -------------------------------------------------------------------------
    # Padrão de 16 bits: 1101_1110_1010_1101 (0xDEAD)
    test_pattern = 0xDEAD 
    log_info(f"Escrevendo padrão 16-bit 0x{test_pattern:X} nos LEDs...")
    
    await bus_write(dut, ADDR_LEDS, test_pattern)
    
    # Verifica pino físico de saída (dut.gpio_leds agora tem 16 bits)
    if dut.gpio_leds.value != test_pattern:
        log_error(f"Falha Escrita LED: Esperado 0x{test_pattern:X}, Pino Físico = 0x{dut.gpio_leds.value}")
        assert False
    log_success(f"Escrita Física nos LEDs OK (0x{test_pattern:X})")

    # -------------------------------------------------------------------------
    # Teste B: Leitura dos LEDs (Read-Back)
    # -------------------------------------------------------------------------
    log_info("Lendo de volta o registrador de LEDs...")
    
    read_val = await bus_read(dut, ADDR_LEDS)
    
    # Mascaramos com 0xFFFF para garantir que estamos comparando apenas os 16 bits úteis
    if (read_val & MASK_16_BIT) != test_pattern:
        log_error(f"Falha Leitura LED: Esperado 0x{test_pattern:X}, Lido 0x{read_val:X}")
        assert False
    log_success("Leitura (Read-Back) dos LEDs OK")

    # -------------------------------------------------------------------------
    # Teste C: Leitura dos Switches (Read Input)
    # -------------------------------------------------------------------------
    # Padrão de 16 bits: 1011_1110_1110_1111 (0xBEEF)
    sw_input = 0xBEEF 
    log_info(f"Simulando entrada física de Switches = 0x{sw_input:X}")
    
    dut.gpio_sw.value = sw_input
    await settle() # Espera propagar
    
    read_val = await bus_read(dut, ADDR_SWITCHES)
    
    if (read_val & MASK_16_BIT) != sw_input:
        log_error(f"Falha Leitura Switches: Esperado 0x{sw_input:X}, Lido 0x{read_val:X}")
        assert False
    log_success(f"Leitura dos Switches OK (0x{sw_input:X})")

@cocotb.test()
async def stress_test_randomized(dut):
    """Stress test aleatório alternando entre escritas e leituras (16 bits)."""
    
    log_header("Stress Test Randomized - GPIO (16-bit)")
    
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    NUM_ITERATIONS = 2000 # Aumentado um pouco para cobrir mais casos
    current_led_state = 0
    
    for i in range(NUM_ITERATIONS):
        
        # Escolhe aleatoriamente uma operação: 
        # 0: Escrever LED, 1: Ler LED, 2: Ler Switch
        op_type = random.randint(0, 2)
        
        if op_type == 0: # --- WRITE LED ---
            # Gera valor aleatório de 16 bits (0 a 65535)
            val_to_write = random.randint(0, 0xFFFF) 
            
            await bus_write(dut, ADDR_LEDS, val_to_write)
            current_led_state = val_to_write
            
            # Verifica saída física imediatamente
            if dut.gpio_leds.value != val_to_write:
                log_error(f"Iter {i}: Falha Escrita LED. Exp: 0x{val_to_write:X}, Obtido: 0x{dut.gpio_leds.value}")
                assert False

        elif op_type == 1: # --- READ LED ---
            read_val = await bus_read(dut, ADDR_LEDS)
            
            # Mascara para 16 bits
            if (read_val & MASK_16_BIT) != current_led_state:
                log_error(f"Iter {i}: Falha Read-Back LED. Exp: 0x{current_led_state:X}, Lido: 0x{read_val & MASK_16_BIT:X}")
                assert False

        elif op_type == 2: # --- READ SWITCH ---
            # Gera um estímulo aleatório no pino (16 bits)
            sw_val = random.randint(0, 0xFFFF)
            dut.gpio_sw.value = sw_val
            await settle()
            
            # Lê via barramento
            read_val = await bus_read(dut, ADDR_SWITCHES)
            
            if (read_val & MASK_16_BIT) != sw_val:
                log_error(f"Iter {i}: Falha Leitura Switch. Exp: 0x{sw_val:X}, Lido: 0x{read_val & MASK_16_BIT:X}")
                assert False

    log_success(f"{NUM_ITERATIONS} Iterações Aleatórias (RW) concluídas com sucesso")