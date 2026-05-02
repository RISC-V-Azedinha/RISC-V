# =====================================================================================================
# File: test_bus_interconnect.py
# =====================================================================================================
#
# >>> Descrição: Testbench avançado para o Bus Interconnect.
#
# >>> Cobertura:
#       1. Functional: Leitura/Escrita básica.
#       2. Harvard Mod.: Acesso simultâneo IMem (Fetch) e DMem (Data).
#       3. Fuzzing: Validação randômica massiva do mapa de memória.
#
# =====================================================================================================

import cocotb
import random
from cocotb.triggers import Timer
from test_utils import log_header, log_success, log_error

# ==============================================================================
# AUXILIARES & GOLDEN MODEL
# ==============================================================================

async def settle():
    """Aguarda propagação combinacional"""
    await Timer(1, "ns")

def model_addr_decode(addr):
    """
    Modelo Python da lógica de decodificação de endereço.
    Retorna uma string identificando o periférico ou 'NONE'.
    """
    # Pega os 4 bits superiores (nibble)
    nibble = (addr >> 28) & 0xF
    
    if nibble == 0x0: return "ROM"
    if nibble == 0x1: return "UART"
    if nibble == 0x2: return "GPIO"
    if nibble == 0x3: return "VGA"
    if nibble == 0x4: return "DMA"
    if nibble == 0x8: return "RAM"
    if nibble == 0x9: return "NPU"
    return "NONE"

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_sanity_check(dut):
    # Teste 1: Verificação Funcional Básica (Sanity Check)
    log_header("Teste 1: Sanity Check (Endereços Conhecidos)")
    
    # Reset
    dut.dmem_vld_i.value = 0
    dut.imem_vld_i.value = 0
    await settle()

    # Caso: Acesso à RAM (0x8000...)
    dut.dmem_addr_i.value = 0x8000AABB
    dut.dmem_vld_i.value  = 1
    await settle()
    
    assert dut.ram_vld_b_o.value == 1, "RAM não foi selecionada!"
    assert dut.rom_vld_b_o.value == 0, "ROM foi selecionada incorretamente!"
    
    log_success("Sanity Check OK")

@cocotb.test()
async def test_harvard_concurrency(dut):
    # Teste 2: Acesso Simultâneo IMem (ROM) e DMem (RAM)
    log_header("Teste 2: Harvard Split (Acesso Simultâneo)")
    
    # Cenário:
    # CPU busca instrução na ROM (0x00001000)
    # CPU escreve dado na RAM (0x80002000) AO MESMO TEMPO
    
    # Constantes Hexadecimais Válidas
    VAL_INSTRUCT = 0x11223344  # Dado vindo da ROM (Instrução)
    VAL_DATA_OLD = 0x55667788  # Dado vindo da RAM (Leitura antiga, ignorado na escrita)
    
    # Configura Dados dos Escravos (Mock)
    dut.rom_data_a_i.value = VAL_INSTRUCT
    dut.ram_data_b_i.value = VAL_DATA_OLD 
    
    # Aplica Estímulos Simultâneos
    dut.imem_addr_i.value = 0x00001000
    dut.imem_vld_i.value  = 1
    
    dut.dmem_addr_i.value = 0x80002000
    dut.dmem_vld_i.value  = 1
    dut.dmem_we_i.value   = 0xF
    
    await settle()
    
    # Verificações
    # 1. Selects Independentes
    assert dut.rom_vld_a_o.value == 1, "IMem não selecionou ROM"
    assert dut.ram_vld_b_o.value == 1, "DMem não selecionou RAM"
    
    # 2. Dados Retornados Independentes
    assert int(dut.imem_data_o.value) == VAL_INSTRUCT, "IMem leu dado errado"
    
    # 3. Cruzamento não deve ocorrer
    assert dut.rom_vld_b_o.value == 0, "DMem selecionou ROM sem querer"
    assert dut.ram_vld_a_o.value == 0, "IMem selecionou RAM sem querer"
    
    log_success("Concorrência Harvard OK")

@cocotb.test()
async def test_fuzzing_map(dut):
    # Teste 3: Fuzzing do Mapa de Memória (1000 Iterações)
    log_header("Teste 3: Fuzzing Completo (Decodificação)")
    
    ITERATIONS = 1000
    
    for i in range(ITERATIONS):
        # 1. Gera Endereço Aleatório (32-bit)
        addr = random.randint(0, 0xFFFFFFFF)
        
        # 2. Aplica ao DUT
        dut.dmem_addr_i.value = addr
        dut.dmem_vld_i.value  = 1
        
        await settle()
        
        # 3. Calcula Esperado (Python Model)
        target = model_addr_decode(addr)
        
        # 4. Verifica Sinais de Seleção (Valids)
        # Cria um dicionário do estado atual dos sinais do DUT
        signals = {
            "ROM":  int(dut.rom_vld_b_o.value),
            "UART": int(dut.uart_vld_o.value),
            "GPIO": int(dut.gpio_vld_o.value),
            "VGA":  int(dut.vga_vld_o.value),
            "DMA":  int(dut.dma_vld_o.value),
            "RAM":  int(dut.ram_vld_b_o.value),
            "NPU":  int(dut.npu_vld_o.value)
        }
        
        # Verifica se APENAS o alvo correto está ativo
        for dev, state in signals.items():
            if dev == target:
                if state != 1:
                    log_error(f"FALHA Fuzz #{i}: {target} deveria estar ativo para addr {hex(addr)}")
                    assert False
            else:
                if state != 0:
                    log_error(f"FALHA Fuzz #{i}: {dev} ativou incorretamente para addr {hex(addr)} (Target era {target})")
                    assert False
                    
        # 5. Verifica Mux de Retorno (Ready e Data)
        # Se for um endereço válido, o DUT deve repassar o dado/ready desse periférico
        # Caso contrário, deve retornar 0 e Ready=1 (default)
        
        if target != "NONE":
            # Injeta um dado simulado na porta de leitura desse device específico
            mock_data = random.randint(0, 0xFFFFFFFF)
            
            if target == "ROM":  
                dut.rom_data_b_i.value = mock_data; dut.rom_rdy_b_i.value = 1
            elif target == "RAM": 
                dut.ram_data_b_i.value = mock_data; dut.ram_rdy_b_i.value = 1
            elif target == "DMA": 
                dut.dma_data_i.value = mock_data;   dut.dma_rdy_i.value = 1
            
            await settle()
            
            # Se testamos ROM, RAM ou DMA, verificamos o data path de volta
            if target in ["ROM", "RAM", "DMA"]:
                assert int(dut.dmem_data_o.value) == mock_data, f"Dado de retorno incorreto para {target}"
                assert int(dut.dmem_rdy_o.value) == 1, f"Ready não retornou para {target}"

        else:
            # Endereço Inválido: Deve retornar Ready=1 e Data=0
            assert int(dut.dmem_rdy_o.value) == 1, "Ready deve ser 1 para endereço inválido (evitar travamento)"
            assert int(dut.dmem_data_o.value) == 0, "Data deve ser 0 para endereço inválido"

    log_success(f"Fuzzing de {ITERATIONS} endereços completado com sucesso!")