# ============================================================================================================================================================
# File: test_alu_control.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench unitário avançado para o controlador da ALU (ALU Control).
#       Verifica decodificação completa (R-Type, I-Type, Branch, Load/Store).
#
# ============================================================================================================================================================

import cocotb   # Biblioteca principal do cocotb
import random   # Para gerar valores aleatórios nos testes

# Importa todas as utilidades compartilhadas entre testbenches 
# Isso inclui: constantes, funções de log e utilitárias, etc.

from test_utils import (
    log_header, log_info, log_success, log_error, settle, alu_name,
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU, 
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND
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

def model_alu_control(alu_op, funct3, funct7):
    """Implementação do GOLDEN MODEL em Python da ALU Control
    
    Parâmetros:
        alu_op: operação de ALU (00, 01, 10, 11)
        funct3: campo funct3 do instrução
        funct7: campo funct7 do instrução

    Retorna:
        (opcode da ALU) conforme o modelo
    """

    # Bit 30 é o bit 5 do campo funct7 (0x20)
    bit30 = (funct7 >> 5) & 1

    # 1. Load / Store (ALUOp = 00) -> Sempre ADD
    if alu_op == 0b00:
        return ALU_ADD
    
    # 2. Branch (ALUOp = 01)
    elif alu_op == 0b01:
        # BEQ, BNE -> SUB
        if funct3 in [0b000, 0b001]: return ALU_SUB
        # BLT, BGE -> SLT
        if funct3 in [0b100, 0b101]: return ALU_SLT
        # BLTU, BGEU -> SLTU
        if funct3 in [0b110, 0b111]: return ALU_SLTU
        # Indefinido
        return ALU_ADD 

    # 3. R-Type (ALUOp = 10)
    elif alu_op == 0b10:
        if funct3 == 0b000: return ALU_SUB if bit30 else ALU_ADD # ADD/SUB
        if funct3 == 0b001: return ALU_SLL
        if funct3 == 0b010: return ALU_SLT
        if funct3 == 0b011: return ALU_SLTU
        if funct3 == 0b100: return ALU_XOR
        if funct3 == 0b101: return ALU_SRA if bit30 else ALU_SRL # SRL/SRA
        if funct3 == 0b110: return ALU_OR
        if funct3 == 0b111: return ALU_AND
        
    # 4. I-Type Arithmetic (ALUOp = 11)
    elif alu_op == 0b11:
        if funct3 == 0b000: return ALU_ADD # ADDI (Não existe SUBI)
        if funct3 == 0b001: return ALU_SLL # SLLI
        if funct3 == 0b010: return ALU_SLT # SLTI
        if funct3 == 0b011: return ALU_SLTU # SLTIU
        if funct3 == 0b100: return ALU_XOR # XORI
        if funct3 == 0b101: return ALU_SRA if bit30 else ALU_SRL # SRLI/SRAI
        if funct3 == 0b110: return ALU_OR  # ORI
        if funct3 == 0b111: return ALU_AND # ANDI

    return 0 # Indefinido

# =====================================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================================

async def verify_op(dut, alu_op, funct3, funct7, expected_cmd, case_desc):
    """Verifica uma operação específica da ALU Control
    
    Parâmetros:
        dut: dispositivo sob teste (Device Under Test)
        alu_op: operação de ALU (00, 01, 10, 11)
        funct3: campo funct3 do instrução
        funct7: campo funct7 do instrução
        expected_cmd: opcode esperado da ALU
        case_desc: descrição do caso de teste (string)
    
    Lança AssertionError em caso de falha.
    """

    dut.ALUOp_i.value  = alu_op
    dut.Funct3_i.value = funct3
    dut.Funct7_i.value = funct7
    await settle()
    
    try:
        current_cmd = int(dut.ALUControl_o.value)
    except ValueError:
        assert False, f"[{case_desc}] Saída Indefinida (X/Z)"

    if current_cmd != expected_cmd:
        exp_n = alu_name(expected_cmd)
        cur_n = alu_name(current_cmd)
        log_error(f"FALHA: {case_desc}")
        log_error(f"In: Op={bin(alu_op)} F3={bin(funct3)} F7={bin(funct7)}")
        log_error(f"Exp: {exp_n} | Got: {cur_n}")
        assert False, f"Falha no caso: {case_desc}"

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):

    log_header("Testes Dirigidos Completos - ALU Control")

    # ------------------------------------------------------------------
    # Load / Store
    # ------------------------------------------------------------------
    
    await verify_op(dut, 0b00, 0b000, 0b0000000, ALU_ADD, "Load/Store -> ADD")
    log_success("Load/Store OK")

    # ------------------------------------------------------------------
    # Branches
    # ------------------------------------------------------------------
    
    await verify_op(dut, 0b01, 0b000, 0, ALU_SUB,  "BEQ  -> SUB")
    await verify_op(dut, 0b01, 0b001, 0, ALU_SUB,  "BNE  -> SUB")
    await verify_op(dut, 0b01, 0b100, 0, ALU_SLT,  "BLT  -> SLT")
    await verify_op(dut, 0b01, 0b101, 0, ALU_SLT,  "BGE  -> SLT")
    await verify_op(dut, 0b01, 0b110, 0, ALU_SLTU, "BLTU -> SLTU")
    await verify_op(dut, 0b01, 0b111, 0, ALU_SLTU, "BGEU -> SLTU")
    log_success("Branches OK")

    # ------------------------------------------------------------------
    # R-Type Arithmetic / Logical
    # ------------------------------------------------------------------
    
    await verify_op(dut, 0b10, 0b000, 0b0000000, ALU_ADD, "R-Type ADD")
    await verify_op(dut, 0b10, 0b000, 0b0100000, ALU_SUB, "R-Type SUB")
    await verify_op(dut, 0b10, 0b001, 0, ALU_SLL,  "R-Type SLL")
    await verify_op(dut, 0b10, 0b010, 0, ALU_SLT,  "R-Type SLT")
    await verify_op(dut, 0b10, 0b011, 0, ALU_SLTU, "R-Type SLTU")
    await verify_op(dut, 0b10, 0b100, 0, ALU_XOR,  "R-Type XOR")
    await verify_op(dut, 0b10, 0b101, 0b0000000, ALU_SRL, "R-Type SRL")
    await verify_op(dut, 0b10, 0b101, 0b0100000, ALU_SRA, "R-Type SRA")
    await verify_op(dut, 0b10, 0b110, 0, ALU_OR,   "R-Type OR")
    await verify_op(dut, 0b10, 0b111, 0, ALU_AND,  "R-Type AND")
    log_success("R-Type OK")

    # ------------------------------------------------------------------
    # I-Type Arithmetic / Logical
    # ------------------------------------------------------------------
    
    await verify_op(dut, 0b11, 0b000, 0, ALU_ADD,  "ADDI")
    await verify_op(dut, 0b11, 0b001, 0, ALU_SLL,  "SLLI")
    await verify_op(dut, 0b11, 0b010, 0, ALU_SLT,  "SLTI")
    await verify_op(dut, 0b11, 0b011, 0, ALU_SLTU, "SLTIU")
    await verify_op(dut, 0b11, 0b100, 0, ALU_XOR,  "XORI")
    await verify_op(dut, 0b11, 0b110, 0, ALU_OR,   "ORI")
    await verify_op(dut, 0b11, 0b111, 0, ALU_AND,  "ANDI")
    await verify_op(dut, 0b11, 0b101, 0b0000000, ALU_SRL, "SRLI")
    await verify_op(dut, 0b11, 0b101, 0b0100000, ALU_SRA, "SRAI")
    log_success("I-Type OK")

    # ------------------------------------------------------------------
    # Final
    # ------------------------------------------------------------------
    
    log_success("Testes Dirigidos Completos OK")

@cocotb.test()
async def stress_test_randomized(dut):

    # Compara VHDL vs Python Model para 5000 vetores aleatórios.
    NUM_ITERATIONS = 5000

    # Contador de iterações por operação
    hits = {} 

    # Escreve cabeçalho do teste
    log_header(f"Stress Test ({NUM_ITERATIONS} Iterações)")
    
    for i in range(NUM_ITERATIONS):

        # Gera opcodes válidos: 00, 01, 10, 11
        op_choice = random.choice([0b00, 0b01, 0b10, 0b11])
        f3 = random.randint(0, 7)
        f7 = random.randint(0, 127)
        
        # Obtém resultado esperado do modelo
        expected = model_alu_control(op_choice, f3, f7)
        
        # Filtra casos inválidos (ex: opcode indefinido no modelo)
        if expected == 0: continue

        # Verifica a operação gerada
        await verify_op(dut, op_choice, f3, f7, expected, f"Iter {i}")
        
        # Conta ocorrências por operação
        op_name = alu_name(expected)
        hits[op_name] = hits.get(op_name, 0) + 1

    # Loga resumo das ocorrências
    for op, count in sorted(hits.items()):
        log_info(f"{op:<5}: {count} vezes")

    # Escreve mensagem de sucesso do teste
    log_success(f"{NUM_ITERATIONS} Vetores Aleatórios Verificados com Sucesso")