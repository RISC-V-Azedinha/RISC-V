# =====================================================================================================================
# File: test_alu.py (Testbench para a ALU)
# =====================================================================================================================
#
# >>> Descrição: TESTBENCH em Python usando cocotb (COroutine COmmand-based TestBench)
# >>> Objetivo:  Testar automaticamente o componente VHDL: ALU (alu.vhd)
#
#  Por que Python? O cocotb permite escrever testes de hardware em Python,
#  que é mais simples e legível que VHDL puro!
#
# >>> Como funciona? O Python se conecta ao simulador VHDL (GHDL) e:
#  1. Envia valores para os sinais de entrada do componente VHDL
#  2. Espera um tempo para a simulação processar
#  3. Lê os valores de saída
#  4. Verifica se os resultados estão corretos (assertions)
#
# =====================================================================================================================

import cocotb   # Biblioteca principal do cocotb
import random   # Para gerar valores aleatórios nos testes

# Importa todas as utilidades compartilhadas entre testbenches 
# Isso inclui: constantes, funções de log e utilitárias, etc.

from test_utils import (
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND,
    settle, log_header, log_success, Colors, 
    to_signed, to_unsigned
)

# =====================================================================================================================
# GOLDEN MODEL - Modelo de referência em Python
# =====================================================================================================================
#
# Def. Formal: Para todo (a, b, opcode) ∈ Domínio_Especificado:
#    RTL(a, b, opcode) == GoldenModel(a, b, opcode)
#
# Trata-se da implementação de um modelo comportamental de referência, utilizado como oráculo de 
# verificação funcional.
# 
# Os resultados produzidos pelo RTL em VHDL devem ser bit-a-bit idênticos
# aos produzidos por este modelo para as mesmas entradas.

def model_alu(opcode, a, b):
    """Implementação do GOLDEN MODEL em Python da ALU
    
    Parâmetros:
        opcode: qual operação fazer (ALU_ADD, ALU_SUB, etc)
        a, b: dois números de entrada de 32 bits
    
    Retorna:
        (resultado_32bits, zero_flag)
        zero_flag = 1 se resultado é zero, 0 caso contrário
    """
    # Preparar versões assinadas e não-assinadas dos operandos
    a_s, b_s = to_signed(a), to_signed(b)      # Com sinal (podem ser negativos)
    a_u, b_u = to_unsigned(a), to_unsigned(b)  # Sem sinal (sempre positivos)
    
    # shamt = shift amount (quanto deslocar)
    # & 0x1F máscara para pegar apenas 5 bits (valores 0-31)
    shamt = b_u & 0x1F

    # Fazer a operação correspondente ao opcode
    res = 0
    if opcode == ALU_ADD:   
        res = a_u + b_u                        # Adição simples
    elif opcode == ALU_SUB: 
        res = a_u - b_u                        # Subtração
    elif opcode == ALU_AND: 
        res = a_u & b_u                        # E bit a bit (&)
    elif opcode == ALU_OR:  
        res = a_u | b_u                        # OU bit a bit (|)
    elif opcode == ALU_XOR: 
        res = a_u ^ b_u                        # OU Exclusivo bit a bit (^)
    elif opcode == ALU_SLL: 
        res = a_u << shamt                     # Shift Left: move bits para esquerda
    elif opcode == ALU_SRL: 
        res = a_u >> shamt                     # Shift Right Lógico: preenche com zeros
    elif opcode == ALU_SRA: 
        res = a_s >> shamt                     # Shift Right Aritmético: preserva sinal
    elif opcode == ALU_SLT: 
        res = 1 if a_s < b_s else 0            # Retorna 1 se a < b (com sinal)
    elif opcode == ALU_SLTU:
        res = 1 if a_u < b_u else 0            # Retorna 1 se a < b (sem sinal)
    
    # Converter resultado para 32 bits não-assinado
    res_masked = to_unsigned(res)
    
    # Calcular flag de zero (será 1 se resultado é zero)
    is_zero = 1 if res_masked == 0 else 0
    
    return res_masked, is_zero

# =====================================================================================================================
# TESTES AUTOMATIZADOS COM COCOTB (TESTBENCH)
# =====================================================================================================================

# Cada função abaixo é um TESTE executado automaticamente
# @cocotb.test() = "registra" essa função como teste para cocotb rodar
# async = essas funções são assíncronas (usam 'await' para esperar)
# dut = Device Under Test (o circuito VHDL que está sendo testado)

@cocotb.test()  # Registra como teste para cocotb
async def test_basic_ops(dut):

    # Testa operações básicas da ALU: ADD e SUB

    log_header("Iniciando Teste Básico (ADD/SUB)")
    
    # ========== TESTE 1: ADIÇÃO ====================================================================
    # Valores dos sinais:
    # - dut.ALUControl_i = entrada de controle (qual operação fazer)
    # - dut.A_i, dut.B_i = duas entradas de dados
    # - dut.Result_o = saída do resultado
    # - dut.Zero_o = saída do flag de zero (1 se resultado é zero, 0 caso contrário)
    # - .value = permite ler/escrever valores desses sinais
    
    dut.ALUControl_i.value = ALU_ADD                    # Configura para fazer adição
    dut.A_i.value, dut.B_i.value = 10, 32               # Entrada: 10 + 32
    await settle()                                      # Espera a lógica VHDL calcular
    
    # assert = verificação. Se falso, o teste falha
    assert int(dut.Result_o.value) == 42, "ADD Falhou"  # Deveria ser 42
    assert dut.Zero_o.value == 0                        # Resultado não é zero, então flag = 0
    
    # Escreve mensagem de sucesso do teste
    log_success("ADD OK")  

    # ========== TESTE 2: SUBTRAÇÃO =================================================================

    dut.ALUControl_i.value = ALU_SUB                    # Configura para subtração
    dut.A_i.value, dut.B_i.value = 10, 10               # 10 - 10 = 0
    await settle()                                      # Espera cálculo
    
    assert int(dut.Result_o.value) == 0, "SUB Falhou"   # Deveria ser 0
    assert dut.Zero_o.value == 1                        # Resultado é zero, então flag = 1

    # Escreve mensagem de sucesso do teste
    log_success("SUB & Zero Flag OK")

@cocotb.test()
async def test_shifts(dut):

    # Testa operações de SHIFT (deslocamento de bits)
    
    log_header("Iniciando Teste de Shifts (SLL, SRL, SRA)")
    
    val_neg = 0xFFFFFFF0  # Um número negativo em hex (representa -16 com sinal)
    shift = 4             # Deslocar 4 posições

    # Loop testando as 3 operações de shift
    # Cada iteração testa uma operação diferente

    for op, name in [(ALU_SRA, "SRA"), (ALU_SRL, "SRL"), (ALU_SLL, "SLL")]:
        
        dut.ALUControl_i.value = op  # Define qual shift fazer
        dut.A_i.value, dut.B_i.value = val_neg, shift
        await settle()  # Aguarda resultado
        
        # Calcular resultado esperado usando o Golden Model
        expected, _ = model_alu(op, val_neg, shift)  # _ = ignora o zero_flag
        got = int(dut.Result_o.value)  # Ler resultado da ALU no VHDL
        
        # Verificar se VHDL bateu com Python
        assert got == expected, f"{name} Falhou. Esp: {hex(expected)} Obt: {hex(got)}"

        # Escreve mensagem de sucesso do teste
        log_success(f"{name} OK")

@cocotb.test()
async def test_slt_logic(dut):

    # Testa operações de comparação (Set Less Than)

    # SLT = Set Less Than: retorna 1 se A < B, 0 caso contrário
    # Existe a versão sinalizada (SLT) e não sinalizada (SLTU)
    
    log_header("Iniciando Teste de Comparações (SLT/SLTU)")
    
    # ========== TESTE DE COMPARAÇÃO COM SINAL (SLT) ==========
    # - SLT = Set Less Than (retorna 1 se A < B, com sinal)
    # - 0xFFFFFFFF COM SINAL = -1 em decimal
    # - Então: -1 < 1 ? SIM! Então resultado = 1
    
    dut.ALUControl_i.value = ALU_SLT
    dut.A_i.value, dut.B_i.value = 0xFFFFFFFF, 1  # -1 < 1
    await settle()
    assert int(dut.Result_o.value) == 1  # Deveria ser 1 (verdadeiro)
    log_success("SLT (Signed) OK")

    # ========== TESTE DE COMPARAÇÃO SEM SINAL (SLTU) ==========
    # SLTU = Set Less Than Unsigned (retorna 1 se A < B, sem sinal)
    # 0xFFFFFFFF SEM SINAL = 4294967295 em decimal (máximo 32-bit)
    # Então: 4294967295 < 1 ? NÃO! Então resultado = 0
    
    dut.ALUControl_i.value = ALU_SLTU
    dut.A_i.value, dut.B_i.value = 0xFFFFFFFF, 1  # MAX > 1
    await settle()
    assert int(dut.Result_o.value) == 0  # Deveria ser 0 (falso)
    log_success("SLTU (Unsigned) OK")

@cocotb.test()
async def test_randomized(dut):
    
    # TESTE DE ESTRESSE: gera 1000 operações aleatórias e verifica todas
    
    # O "fuzz testing" (teste com dados aleatórios) é uma técnica poderosa porque:
    # - Cobre casos que nós humanos nunca pensaríamos
    # - Encontra bugs em situações raras e inesperadas
    # - Testa a robustez real do circuito
    
    log_header("Iniciando Teste de Estresse Randômico (1000 iterações)")
    
    # Lista de todas as operações que queremos testar
    ops = [ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU]
    
    for i in range(1000):  # 1000 iterações
        # Gerar valores aleatórios
        op = random.choice(ops)  # Escolhe uma operação aleatória da lista
        a = random.getrandbits(32)  # Número aleatório de 32 bits
        b = random.getrandbits(32)  # Outro número aleatório de 32 bits

        # Enviar para a ALU no VHDL
        dut.ALUControl_i.value = op
        dut.A_i.value, dut.B_i.value = a, b
        await settle()  # Aguardar resultado

        # Calcular resultado esperado usando Golden Model em Python
        expected_res, expected_zero = model_alu(op, a, b)
        
        # Comparar VHDL com Python
        if int(dut.Result_o.value) != expected_res or int(dut.Zero_o.value) != expected_zero:
             msg = f"\n{Colors.FAIL}FALHA na iteração {i}{Colors.ENDC}\nOp: {bin(op)}\nA: {hex(a)}\nB: {hex(b)}"
             assert int(dut.Result_o.value) == expected_res, f"{msg} -> Res Errado"
             assert int(dut.Zero_o.value) == expected_zero, f"{msg} -> Zero Errado"

    log_success(f"1000 Vetores Aleatórios Verificados com Sucesso")

# =====================================================================================================================