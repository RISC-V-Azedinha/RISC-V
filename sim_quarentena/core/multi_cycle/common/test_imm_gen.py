# ============================================================================================================================================================
# File: test_imm_gen.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para o Gerador de Imediatos (Imm Gen).
#     Verifica a geração correta de imediatos para formatos I, S, B, U e J.
#     Inclui verificação de extensão de sinal e testes aleatórios (CRV).
#
# ============================================================================================================================================================

import cocotb   # Biblioteca principal do cocotb
import random   # Para gerar valores aleatórios nos testes

# Importa utilitários compartilhados entre testbenches
from test_utils import log_header, log_info, log_success, log_error, settle, sign_extend

# =====================================================================================================================
# CONSTANTES E FUNÇÕES AUXILIARES (RISC-V SPEC)
# =====================================================================================================================

OPCODE_I_TYPE   = 0x13  # 0010011 (ADDI, etc)
OPCODE_STORE    = 0x23  # 0100011 (SW, SB, SH)
OPCODE_BRANCH   = 0x63  # 1100011 (BEQ, BNE, etc)
OPCODE_LUI      = 0x37  # 0110111 (LUI)
OPCODE_JAL      = 0x6F  # 1101111 (JAL)

# =====================================================================================================================
# GOLDEN MODEL - Modelo de referência em Python
# =====================================================================================================================
#
# Def. Formal: Para todo (instruction) ∈ Domínio_Especificado:
#    RTL(instruction) == GoldenModel(instruction)
#
# Trata-se da implementação de um modelo comportamental de referência, utilizado como oráculo de 
# verificação funcional.

def model_imm_gen(instruction):
    """
    Simula o hardware ImmGen.
    Recebe um inteiro de 32 bits (instrução) e retorna o imediato de 32 bits.
    """

    # Extrai o opcode (bits 6:0)
    opcode = instruction & 0x7F
    
    # I-Type: imm[11:0] (Bits 31:20)
    if opcode == OPCODE_I_TYPE:
        imm_11_0 = (instruction >> 20) & 0xFFF
        return sign_extend(imm_11_0, 12)

    # S-Type: imm[11:5] (31:25) | imm[4:0] (11:7)
    elif opcode == OPCODE_STORE:
        imm_11_5 = (instruction >> 25) & 0x7F
        imm_4_0  = (instruction >> 7)  & 0x1F
        imm_val  = (imm_11_5 << 5) | imm_4_0
        return sign_extend(imm_val, 12)

    # B-Type: imm[12]|imm[10:5]|imm[4:1]|imm[11] -> (31, 30:25, 11:8, 7)
    elif opcode == OPCODE_BRANCH:
        bit_12    = (instruction >> 31) & 1
        bit_10_5  = (instruction >> 25) & 0x3F
        bit_4_1   = (instruction >> 8)  & 0xF
        bit_11    = (instruction >> 7)  & 1
        
        imm_val = (bit_12 << 12) | (bit_11 << 11) | (bit_10_5 << 5) | (bit_4_1 << 1)
        return sign_extend(imm_val, 13)

    # U-Type: imm[31:12] (31:12) << 12
    elif opcode == OPCODE_LUI:
        imm_31_12 = (instruction >> 12) & 0xFFFFF
        val = imm_31_12 << 12
        return sign_extend(val, 32)

    # J-Type: imm[20]|imm[10:1]|imm[11]|imm[19:12] -> (31, 30:21, 20, 19:12)
    elif opcode == OPCODE_JAL:
        bit_20    = (instruction >> 31) & 1
        bit_10_1  = (instruction >> 21) & 0x3FF
        bit_11    = (instruction >> 20) & 1
        bit_19_12 = (instruction >> 12) & 0xFF
        imm_val = (bit_20 << 20) | (bit_19_12 << 12) | (bit_11 << 11) | (bit_10_1 << 1)
        return sign_extend(imm_val, 21)

    return 0 # Indefinido

# =====================================================================================================================
# BUILDER HELPERS (Para construir instruções de teste)
# =====================================================================================================================

def make_instr(opcode, rd=0, funct3=0, rs1=0, rs2=0, imm=0):
    """Constrói uma instrução RISC-V baseada no formato e no opcode"""
    
    # Garante máscaras
    rd  &= 0x1F; rs1 &= 0x1F; rs2 &= 0x1F; funct3 &= 0x7

    if opcode == OPCODE_I_TYPE:
        # I-Type: imm[11:0] | rs1 | funct3 | rd | opcode
        imm &= 0xFFF
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    elif opcode == OPCODE_STORE:
        # S-Type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
        imm &= 0xFFF
        imm_11_5 = (imm >> 5) & 0x7F
        imm_4_0  = imm & 0x1F
        return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode

    elif opcode == OPCODE_BRANCH:
        # B-Type: imm[12] | imm[10:5] | rs2 | rs1 | funct3 | imm[4:1] | imm[11] | opcode
        imm &= 0x1FFF # 13 bits
        b12 = (imm >> 12) & 1
        b11 = (imm >> 11) & 1
        b10_5 = (imm >> 5) & 0x3F
        b4_1  = (imm >> 1) & 0xF
        return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode

    elif opcode == OPCODE_LUI:
        imm_upper = (imm >> 12) & 0xFFFFF
        return (imm_upper << 12) | (rd << 7) | opcode

    elif opcode == OPCODE_JAL:
        # J-Type: imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd | opcode
        imm &= 0x1FFFFF # 21 bits
        b20 = (imm >> 20) & 1
        b19_12 = (imm >> 12) & 0xFF
        b11 = (imm >> 11) & 1
        b10_1 = (imm >> 1) & 0x3FF
        return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode
    
    return 0

# =====================================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================================

async def verify_imm(dut, instruction, expected_imm, case_desc):
    """
    Aplica a instrução, aguarda e verifica o imediato.
    """

    # Aplica a instrução
    dut.Instruction_i.value = instruction

    # Aguarda estabilização
    await settle()
    
    # Obtém o valor assinado da saída
    current_imm = dut.Immediate_o.value.to_signed()

    # Compara com o valor esperado
    if current_imm != expected_imm:
        log_error(f"FALHA: {case_desc}")
        log_error(f"Instr Hex : {hex(instruction)}")
        log_error(f"Esperado  : {expected_imm} ({hex(expected_imm & 0xFFFFFFFF)})")
        log_error(f"Recebido  : {current_imm} ({hex(current_imm & 0xFFFFFFFF)})")
        assert False, f"Falha no caso: {case_desc}"

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):
    
    # Realiza testes dirigidos para cada formato de instrução
    
    log_header("Testes Dirigidos - Imm Gen")

    # Constantes do VHDL convertidas
    RD_X5  = 5
    RS1_X6 = 6
    RS2_X7 = 7
    F3_ADDI = 0; F3_SW = 2; F3_BEQ = 0

    # 1. I-Type: ADDI x5, x6, -100
    instr = make_instr(OPCODE_I_TYPE, rd=RD_X5, rs1=RS1_X6, funct3=F3_ADDI, imm=-100)
    await verify_imm(dut, instr, -100, "I-Type (imm=-100)")
    log_success("I-Type OK")
    
    # 2. S-Type: SW x7, -4(x6)
    instr = make_instr(OPCODE_STORE, rs1=RS1_X6, rs2=RS2_X7, funct3=F3_SW, imm=-4)
    await verify_imm(dut, instr, -4, "S-Type (imm=-4)")
    log_success("S-Type OK")

    # 3. B-Type: BEQ x6, x7, -32
    instr = make_instr(OPCODE_BRANCH, rs1=RS1_X6, rs2=RS2_X7, funct3=F3_BEQ, imm=-32)
    await verify_imm(dut, instr, -32, "B-Type (imm=-32)")
    log_success("B-Type OK")

    # 4. U-Type: LUI x5, 0xABCDE
    instr = make_instr(OPCODE_LUI, rd=RD_X5, imm=0xABCDE000)
    await verify_imm(dut, instr, 0xABCDE000 - 0x100000000, "U-Type (imm=0xABCDE000 signed)") 
    log_success("U-Type OK")

    # 5. J-Type: JAL x5, -512
    instr = make_instr(OPCODE_JAL, rd=RD_X5, imm=-512)
    await verify_imm(dut, instr, -512, "J-Type (imm=-512)")
    log_success("J-Type OK")

    # 6. Limites I-Type
    # Max Positivo (+2047)
    instr = make_instr(OPCODE_I_TYPE, imm=2047)
    await verify_imm(dut, instr, 2047, "I-Type Max Pos (+2047)")
    log_success("I-Type Max Positivo OK")
    
    # Min Negativo (-2048)
    instr = make_instr(OPCODE_I_TYPE, imm=-2048)
    await verify_imm(dut, instr, -2048, "I-Type Min Neg (-2048)")
    log_success("I-Type Min Negativo OK")

    # 7. Limites B-Type (+4094) -> B-type pula em múltiplos de 2, max 12 bits signed = +4094
    instr = make_instr(OPCODE_BRANCH, imm=4094)
    await verify_imm(dut, instr, 4094, "B-Type Max Pos (+4094)")
    log_success("Limites B-Type OK")

@cocotb.test()
async def stress_test_randomized(dut):
    
    # Gera instruções aleatórias e compara com o modelo Python
    
    # Número de iterações aleatórias
    NUM_ITERATIONS = 5000

    # Contador de hits por tipo de instrução
    hits = {}
    
    # Escreve cabeçalho do teste
    log_header(f"Stress Test Randomized ({NUM_ITERATIONS} iterações)")

    # Lista de opcodes para escolher aleatoriamente
    opcodes = [OPCODE_I_TYPE, OPCODE_STORE, OPCODE_BRANCH, OPCODE_LUI, OPCODE_JAL]
    op_names = {OPCODE_I_TYPE: "I-Type", OPCODE_STORE: "S-Type", OPCODE_BRANCH: "B-Type", OPCODE_LUI: "U-Type", OPCODE_JAL: "J-Type"}

    # Loop de iterações aleatórias 
    for i in range(NUM_ITERATIONS):

        # Escolhe um opcode aleatório
        opcode = random.choice(opcodes)
        
        # Gera campos aleatórios
        rd  = random.randint(0, 31)
        rs1 = random.randint(0, 31)
        rs2 = random.randint(0, 31)
        funct3 = random.randint(0, 7)
        
        # Gera imediato aleatório válido para o formato
        imm_val = 0
        instr_word = 0

        if opcode == OPCODE_I_TYPE:
            imm_val = random.randint(-2048, 2047) # 12 bits signed
            instr_word = make_instr(opcode, rd=rd, rs1=rs1, funct3=funct3, imm=imm_val)
            
        elif opcode == OPCODE_STORE:
            imm_val = random.randint(-2048, 2047) # 12 bits signed
            instr_word = make_instr(opcode, rs1=rs1, rs2=rs2, funct3=funct3, imm=imm_val)
            
        elif opcode == OPCODE_BRANCH:
            imm_val = random.randint(-4096, 4094) & ~1 
            instr_word = make_instr(opcode, rs1=rs1, rs2=rs2, funct3=funct3, imm=imm_val)
            
        elif opcode == OPCODE_LUI:
            raw_val = random.randint(0, 0xFFFFFFFF)
            expected_imm_val = raw_val & 0xFFFFF000 
            expected_imm_val = sign_extend(expected_imm_val, 32)
            instr_word = make_instr(opcode, rd=rd, imm=raw_val)
            imm_val = expected_imm_val 
            
        elif opcode == OPCODE_JAL:
            imm_val = random.randint(-1048576, 1048574) & ~1
            instr_word = make_instr(opcode, rd=rd, imm=imm_val)

        # Verifica com o modelo Python o imediato esperado
        model_val = model_imm_gen(instr_word)
        if model_val != imm_val:
            log_error(f"ERRO DE LOGICA NO TESTBENCH (Iter {i})")
            log_error(f"Gerado: {imm_val}, Modelo Python Calculou: {model_val}")
            assert False, "Testbench Logic Error"

        await verify_imm(dut, instr_word, imm_val, f"Random {op_names[opcode]} Iter {i}")

        # Conta hits por tipo de instrução        
        name = op_names[opcode]
        hits[name] = hits.get(name, 0) + 1

    # Relatório de cobertura de operações
    for op, count in sorted(hits.items()):
        log_info(f"{op:<10}: {count} vezes")
    
    # Escreve mensagem de sucesso do teste
    log_success(f"{NUM_ITERATIONS} Vetores Aleatórios Verificados com Sucesso")