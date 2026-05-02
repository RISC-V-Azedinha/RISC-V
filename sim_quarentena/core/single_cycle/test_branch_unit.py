# ============================================================================================================================================================
# File: test_branch_unit.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para a Unidade de Desvio (Branch Unit).
#     Verifica a decisão de tomada de branch baseada na flag Zero da ALU e Funct3.
#     Assume que a ALU realiza operações SLT/SLTU para branches relacionais.
#
# ============================================================================================================================================================

import cocotb   # Biblioteca principal do cocotb
import random   # Para gerar valores aleatórios nos testes

# Importa utilitários compartilhados entre testbenches
from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# CONSTANTES (RISC-V BRANCH FUNCT3)
# =====================================================================================================================

F3_BEQ  = 0b000
F3_BNE  = 0b001
F3_BLT  = 0b100
F3_BGE  = 0b101
F3_BLTU = 0b110
F3_BGEU = 0b111

NAMES = {
    F3_BEQ: "BEQ", F3_BNE: "BNE", 
    F3_BLT: "BLT", F3_BGE: "BGE", 
    F3_BLTU: "BLTU", F3_BGEU: "BGEU"
}

# =====================================================================================================================
# GOLDEN MODEL - Modelo de referência em Python
# =====================================================================================================================
#
# Def. Formal: Para todo (a, b, opcode) ∈ Domínio_Especificado:
#    RTL(a, b, opcode) == GoldenModel(a, b, opcode)
#
# Trata-se da implementação de um modelo comportamental de referência, utilizado como oráculo de 
# verificação funcional.

def model_branch_unit(branch_en, funct3, alu_zero):
    """
    Simula o hardware Branch Unit.
    
    Args:
        branch_en (int): Sinal Branch_i (1 se é instrução de branch).
        funct3 (int): Campo funct3 da instrução.
        alu_zero (int): Flag Zero vinda da ALU (1 se resultado == 0).
        
    Returns:
        int: Sinal BranchTaken_o (1 se deve desviar, 0 caso contrário).
    """
    
    # Se não é instrução de branch, nunca toma o desvio
    if not branch_en:
        return 0

    # BEQ: Taken se Zero=1 (A == B, A-B=0)
    if funct3 == F3_BEQ:
        return 1 if alu_zero else 0
    
    # BNE: Taken se Zero=0 (A != B, A-B!=0)
    elif funct3 == F3_BNE:
        return 0 if alu_zero else 1
    
    # BLT / BLTU: A < B. 
    # A ALU executa SLT/SLTU.
    # Se A < B, Resultado = 1 (Non-Zero) -> Zero_Flag = 0
    # Se A >= B, Resultado = 0 (Zero)    -> Zero_Flag = 1
    # Portanto, Taken se Zero_Flag = 0.
    elif funct3 in [F3_BLT, F3_BLTU]:
        return 0 if alu_zero else 1

    # BGE / BGEU: A >= B.
    # A ALU executa SLT/SLTU.
    # Se A >= B, Resultado = 0 (Zero)    -> Zero_Flag = 1
    # Portanto, Taken se Zero_Flag = 1.
    elif funct3 in [F3_BGE, F3_BGEU]:
        return 1 if alu_zero else 0
    
    return 0 # Padrão (Indefinido)

# =====================================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================================

async def verify_branch(dut, branch_en, funct3, alu_zero, expected, case_desc):
    """
    Aplica estímulos e verifica a saída.
    """

    # Aplica estímulos
    dut.Branch_i.value   = branch_en
    dut.Funct3_i.value   = funct3
    dut.ALU_Zero_i.value = alu_zero
    
    # Aguarda estabilização dos sinais
    await settle()
    
    # Leitura da saída
    current = int(dut.BranchTaken_o.value)
    
    # Comparação
    if current != expected:
        f3_name = NAMES.get(funct3, f"UNK({bin(funct3)})")
        log_error(f"FALHA: {case_desc}")
        log_error(f"In : Branch={branch_en}, F3={f3_name}, Zero={alu_zero}")
        log_error(f"Out: Exp={expected} | Got={current}")
        assert False, f"Falha no caso: {case_desc}"

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):
    
    # Reproduz os testes manuais do branch_unit_tb.vhd
    
    log_header("Testes Dirigidos - Branch Unit")
    
    # 1. Não é Branch (Branch_i = 0)
    # Deve ser 0 independente dos outros sinais
    await verify_branch(dut, 0, F3_BEQ, 1, 0, "No Branch (Branch=0)")
    log_success("Disable Logic OK")

    # 2. BEQ (Branch if Equal) - Usa SUB
    # Taken se Zero=1
    await verify_branch(dut, 1, F3_BEQ, 1, 1, "BEQ Taken (Z=1)")
    await verify_branch(dut, 1, F3_BEQ, 0, 0, "BEQ Not Taken (Z=0)")
    log_success("BEQ OK")

    # 3. BNE (Branch if Not Equal) - Usa SUB
    # Taken se Zero=0
    await verify_branch(dut, 1, F3_BNE, 0, 1, "BNE Taken (Z=0)")
    await verify_branch(dut, 1, F3_BNE, 1, 0, "BNE Not Taken (Z=1)")
    log_success("BNE OK")

    # 4. BLT (Branch Less Than) - Usa SLT
    # Taken se A < B (Res=1 => Z=0)
    await verify_branch(dut, 1, F3_BLT, 0, 1, "BLT Taken (Z=0)")
    await verify_branch(dut, 1, F3_BLT, 1, 0, "BLT Not Taken (Z=1)")
    log_success("BLT OK")

    # 5. BGE (Branch Greater Equal) - Usa SLT
    # Taken se A >= B (Res=0 => Z=1)
    await verify_branch(dut, 1, F3_BGE, 1, 1, "BGE Taken (Z=1)")
    await verify_branch(dut, 1, F3_BGE, 0, 0, "BGE Not Taken (Z=0)")
    log_success("BGE OK")

    # 6. BLTU (Less Than Unsigned) - Usa SLTU
    # Lógica idêntica ao BLT para a Branch Unit (depende só do Zero)
    await verify_branch(dut, 1, F3_BLTU, 0, 1, "BLTU Taken (Z=0)")
    await verify_branch(dut, 1, F3_BLTU, 1, 0, "BLTU Not Taken (Z=1)")
    log_success("BLTU OK")

    # 7. BGEU (Greater Equal Unsigned) - Usa SLTU
    # Lógica idêntica ao BGE
    await verify_branch(dut, 1, F3_BGEU, 1, 1, "BGEU Taken (Z=1)")
    await verify_branch(dut, 1, F3_BGEU, 0, 0, "BGEU Not Taken (Z=0)")
    log_success("BGEU OK")

@cocotb.test()
async def stress_test_randomized(dut):
    
    # Gera casos aleatórios para cobrir todas combinações de Funct3 e Zero.
    
    # Número de iterações aleatórias
    NUM_ITERATIONS = 5000

    # Contador de hits por tipo de instrução
    hits = {}
    
    # Escreve cabeçalho do teste
    log_header(f"Stress Test Randomized ({NUM_ITERATIONS} iterações)")
    
    # Lista de Funct3 válidos para branches
    valid_funct3 = [F3_BEQ, F3_BNE, F3_BLT, F3_BGE, F3_BLTU, F3_BGEU]
    
    # Loop de iterações aleatórias 
    for i in range(NUM_ITERATIONS):

        # Gera entradas aleatórias
        branch_en = random.choice([0, 1, 1, 1])
        funct3    = random.choice(valid_funct3)
        alu_zero  = random.choice([0, 1])
        
        # Calcula esperado pelo modelo
        expected = model_branch_unit(branch_en, funct3, alu_zero)
        
        # Verifica DUT
        await verify_branch(dut, branch_en, funct3, alu_zero, expected, f"Iter {i}")
        
        # Estatísticas (apenas se branch_en=1)
        if branch_en:
            op_name = NAMES[funct3]
            hits[op_name] = hits.get(op_name, 0) + 1

    # Relatório de cobertura de operações
    for op, count in sorted(hits.items()):
        log_info(f"{op:<5}: {count} vezes")
        
    # Escreve mensagem de sucesso do teste
    log_success(f"{NUM_ITERATIONS} Iterações verificadas com sucesso!")