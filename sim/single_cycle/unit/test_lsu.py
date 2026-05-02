# ==============================================================================
# File: test_lsu.py
# Descrição: Testbench para a Load Store Unit (LSU)
# ==============================================================================

import cocotb   # Biblioteca principal do cocotb

# Importa utilitários compartilhados entre testbenches
from test_utils import log_header, log_info, log_success, settle

# Funct3 Constants (Baseado no RISC-V ISA)
F3_LB  = 0b000
F3_LH  = 0b001
F3_LW  = 0b010
F3_LBU = 0b100
F3_LHU = 0b101
F3_SB  = 0b000
F3_SH  = 0b001
F3_SW  = 0b010

@cocotb.test()
async def test_lsu_passthrough(dut):
    
    # Indica o teste sendo realizado
    log_header("Teste 1: Verifica Endereço e Geração de WE (para SW)")
    
    # Escreve mensagem de inicialização
    log_info("Iniciando Teste de Pass-through...")
    
    # Stimulus
    addr = 0x12345678
    we   = 1
    
    # Configura os sinais do DUT
    dut.Addr_i.value      = addr
    dut.MemWrite_i.value  = we
    dut.WriteData_i.value = 0
    # Usamos SW (Store Word) para garantir que a máscara seja "1111"
    dut.Funct3_i.value    = F3_SW 
    dut.DMem_data_i.value = 0 

    # Aguarda a estabilização dos sinais
    await settle()
    
    # Checks
    assert dut.DMem_addr_o.value == addr, f"Erro Endereço: {hex(dut.DMem_addr_o.value)} != {hex(addr)}"
    
    # Correção: WE agora é 4 bits. Para SW, esperamos 0xF (1111 binário)
    assert dut.DMem_we_o.value   == 0xF,  f"Erro WE: {dut.DMem_we_o.value} != 0xF (Esperado máscara completa para SW)"
    
    # Escreve mensagem de sucesso do teste
    log_success("Pass-through OK!")


@cocotb.test()
async def test_lsu_loads(dut):

    # Indica o teste sendo realizado
    log_header("Teste 2: Verifica a lógica de LOAD (Leitura e Formatação)")
    
    # Escreve mensagem de inicialização
    log_info("Iniciando Teste de Loads...")
    
    # Cenário: Memória contém 0x89ABCDEF
    mem_val = 0x89ABCDEF
    dut.DMem_data_i.value = mem_val
    dut.MemWrite_i.value  = 0         # Leitura

    # Tabela de Testes: (Funct3, Endereço_LSB, Valor_Esperado, Nome)
    test_cases = [
        # LW (Word) - Endereço alinhado
        (F3_LW,  0b00, 0x89ABCDEF, "LW Alinhado"),
        
        # LB (Byte com Sinal) - Extensão de sinal
        (F3_LB,  0b00, 0xFFFFFFEF, "LB Byte 0 (Neg)"),
        (F3_LB,  0b01, 0xFFFFFFCD, "LB Byte 1 (Neg)"),
        (F3_LB,  0b10, 0xFFFFFFAB, "LB Byte 2 (Neg)"),
        (F3_LB,  0b11, 0xFFFFFF89, "LB Byte 3 (Neg)"),
        
        # LBU (Byte Sem Sinal) - Extensão de zero
        (F3_LBU, 0b00, 0x000000EF, "LBU Byte 0"),
        (F3_LBU, 0b11, 0x00000089, "LBU Byte 3"),

        # LH (Half com Sinal)
        (F3_LH,  0b00, 0xFFFFCDEF, "LH Half 0"),
        (F3_LH,  0b10, 0xFFFF89AB, "LH Half 1"),

        # LHU (Half Sem Sinal)
        (F3_LHU, 0b00, 0x0000CDEF, "LHU Half 0"),
    ]

    # Loop de iteração do vetor de testes
    for f3, addr_lsb, expected, name in test_cases:

        dut.Funct3_i.value = f3
        dut.Addr_i.value   = addr_lsb 
        
        await settle()
        
        got = int(dut.LoadData_o.value)
        
        assert got == expected, f"FALHA {name}: Esperado {hex(expected)}, Obtido {hex(got)}"
        log_info(f"OK: {name}")

    log_success("Vetor de testes de LOAD realizado com sucesso!")


@cocotb.test()
async def test_lsu_stores(dut):

    # Indica o teste sendo realizado
    log_header("Teste 3: Verifica a lógica de STORE (Byte Enables e Alinhamento)")
    
    # Escreve mensagem de inicialização
    log_info("Iniciando Teste de Stores...")
    
    # Correção: Não simulamos mais "Old Memory" pois não há leitura (RMW).
    # A LSU apenas posiciona o dado e ativa os bits corretos do WE.
    
    val_to_write = 0x11223344
    
    # Configura os sinais no DUT
    dut.WriteData_i.value = val_to_write
    dut.MemWrite_i.value  = 1
    # dut.DMem_data_i é ignorado pela nova LSU em stores

    # Tabela de Testes
    # (Funct3, Addr_LSB, Esperado_WE_Mask, Esperado_Data_Out, Nome)
    test_cases = [
        # SW: Write Enable "1111" (0xF), Dado completo
        (F3_SW, 0b00, 0xF, 0x11223344, "SW Full"),
        
        # SH: Write Enable "0011" ou "1100"
        # Half Inferior: Pega 16 bits LSB (3344) e joga na saída
        (F3_SH, 0b00, 0x3, 0x00003344, "SH Lower (Bytes 0,1)"),
        # Half Superior: Pega 16 bits LSB (3344) e desloca para cima
        (F3_SH, 0b10, 0xC, 0x33440000, "SH Upper (Bytes 2,3)"),
        
        # SB: Write Enable com 1 bit ativo ("0001", "0010", etc)
        # Byte 0: Pega 8 bits LSB (44)
        (F3_SB, 0b00, 0x1, 0x00000044, "SB Byte 0"),
        # Byte 1: Pega 8 bits LSB (44) e desloca
        (F3_SB, 0b01, 0x2, 0x00004400, "SB Byte 1"),
        # Byte 2
        (F3_SB, 0b10, 0x4, 0x00440000, "SB Byte 2"),
        # Byte 3
        (F3_SB, 0b11, 0x8, 0x44000000, "SB Byte 3"),
    ]

    # Loop de iteração do vetor de testes
    for f3, addr_lsb, exp_we, exp_data, name in test_cases:
        
        dut.Funct3_i.value = f3
        dut.Addr_i.value   = addr_lsb
        
        await settle()
        
        got_we   = int(dut.DMem_we_o.value)
        got_data = int(dut.DMem_data_o.value)

        # Verificação da Máscara de Escrita (WE)
        assert got_we == exp_we, f"FALHA {name} (WE): Esperado {bin(exp_we)}, Obtido {bin(got_we)}"

        # Verificação do Dado (Verificamos apenas os bytes ativos na máscara)
        # Nota: O VHDL atribui '0' aos bytes inativos ou mantém indefinido? 
        # No código sugerido anteriormente: DMem_data_o <= (others => '0') por padrão.
        # Portanto, podemos comparar o valor inteiro exato.
        assert got_data == exp_data, f"FALHA {name} (Data): Esperado {hex(exp_data)}, Obtido {hex(got_data)}"

        log_info(f"OK: {name}")
    
    log_success("Vetor de testes de STORE realizado com sucesso!")