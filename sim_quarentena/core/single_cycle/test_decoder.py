# ============================================================================================================================================================
# File: test_decoder.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para a Unidade Decodificadora (Decoder).
#     Verifica se os sinais de controle (ALUOp, RegWrite, MemWrite, etc.) são gerados corretamente
#     para cada Opcode do RISC-V RV32I. Testa o wrapper do componente.
#
# >>> Nota: Este testbench utiliza um wrapper VHDL (decoder_wrapper.vhd) para expor os campos do record
#
# ============================================================================================================================================================

import cocotb   # Biblioteca principal do cocotb
import random   # Para gerar valores aleatórios nos testes

# Importa utilitários compartilhados entre testbenches
from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# CONSTANTES (RISC-V OPCODES)
# =====================================================================================================================

OP_R_TYPE   = 0x33 # 0110011
OP_I_TYPE   = 0x13 # 0010011
OP_LOAD     = 0x03 # 0000011
OP_STORE    = 0x23 # 0100011
OP_BRANCH   = 0x63 # 1100011
OP_JAL      = 0x6F # 1101111
OP_JALR     = 0x67 # 1100111
OP_LUI      = 0x37 # 0110111
OP_AUIPC    = 0x17 # 0010111
OP_FENCE    = 0x0F # 0001111
OP_SYSTEM   = 0x73 # 1110011

OP_NAMES = {
    OP_R_TYPE: "R-Type", OP_I_TYPE: "I-Type", OP_LOAD: "LOAD", OP_STORE: "STORE",
    OP_BRANCH: "BRANCH", OP_JAL: "JAL", OP_JALR: "JALR", OP_LUI: "LUI",
    OP_AUIPC: "AUIPC", OP_FENCE: "FENCE", OP_SYSTEM: "SYSTEM"
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

class ControlSignals:
    """Classe auxiliar para agrupar os sinais de controle esperados"""

    def __init__(self, rw=0, alu_a=0, alu_b=0, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0):
        self.reg_write = rw
        self.alu_src_a = alu_a
        self.alu_src_b = alu_b
        self.mem_to_reg = m2r
        self.mem_write = mw
        self.write_data_src = wds
        self.branch = br
        self.jump = jmp
        self.alu_op = alu_op

    def __eq__(self, other):
        return self.__dict__ == other.__dict__

    def __str__(self):
        return (f"RW={self.reg_write} SrcA={self.alu_src_a} SrcB={self.alu_src_b} "
                f"M2R={self.mem_to_reg} MW={self.mem_write} WDS={self.write_data_src} "
                f"Br={self.branch} Jmp={self.jump} AOp={self.alu_op}")

def model_decoder(opcode):
    """
    Simula o hardware Decoder.
    Retorna um objeto ControlSignals com os valores esperados.
    """
    
    # R-Type (ADD, SUB, XOR, etc)
    if opcode == OP_R_TYPE:
        return ControlSignals(rw=1, alu_a=0b00, alu_b=0, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0b10)

    # I-Type Arithmetic (ADDI, XORI, etc)
    elif opcode == OP_I_TYPE:
        return ControlSignals(rw=1, alu_a=0b00, alu_b=1, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0b11)

    # LOAD (LB, LW, etc)
    elif opcode == OP_LOAD:
        return ControlSignals(rw=1, alu_a=0b00, alu_b=1, m2r=1, mw=0, wds=0, br=0, jmp=0, alu_op=0b00)

    # STORE (SB, SW, etc)
    elif opcode == OP_STORE:
        return ControlSignals(rw=0, alu_a=0b00, alu_b=1, m2r=0, mw=1, wds=0, br=0, jmp=0, alu_op=0b00)

    # BRANCH (BEQ, BNE, etc)
    elif opcode == OP_BRANCH:
        return ControlSignals(rw=0, alu_a=0b00, alu_b=0, m2r=0, mw=0, wds=0, br=1, jmp=0, alu_op=0b01)

    # JAL
    elif opcode == OP_JAL:
        return ControlSignals(rw=1, alu_a=0b00, alu_b=0, m2r=0, mw=0, wds=1, br=0, jmp=1, alu_op=0b00)

    # JALR
    elif opcode == OP_JALR:
        return ControlSignals(rw=1, alu_a=0b00, alu_b=1, m2r=0, mw=0, wds=1, br=0, jmp=1, alu_op=0b00)

    # LUI
    elif opcode == OP_LUI:
        return ControlSignals(rw=1, alu_a=0b10, alu_b=1, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0b00)

    # AUIPC
    elif opcode == OP_AUIPC:
        return ControlSignals(rw=1, alu_a=0b01, alu_b=1, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0b00)

    # FENCE / SYSTEM / Unknown -> NOP (Tudo zero)
    else:
        return ControlSignals(rw=0, alu_a=0, alu_b=0, m2r=0, mw=0, wds=0, br=0, jmp=0, alu_op=0)

# =====================================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================================

async def verify_decoder(dut, opcode, expected, case_desc):
    """
    Aplica estímulos e verifica todas as saídas do decoder.
    """
    
    # Aplica estímulos
    dut.Opcode_i.value = opcode
    
    # Aguarda propagação combinacional
    await settle()
    
    # Leitura dos sinais atuais
    current = ControlSignals(
        rw      = int(dut.reg_write_o.value),
        alu_a   = int(dut.alu_src_a_o.value),
        alu_b   = int(dut.alu_src_b_o.value),
        m2r     = int(dut.mem_to_reg_o.value),
        mw      = int(dut.mem_write_o.value),
        wds     = int(dut.write_data_src_o.value),
        br      = int(dut.branch_o.value),
        jmp     = int(dut.jump_o.value),
        alu_op  = int(dut.alu_op_o.value)
    )
    
    # Comparação
    if current != expected:
        op_name = OP_NAMES.get(opcode, f"UNK({hex(opcode)})")
        log_error(f"FALHA: {case_desc}")
        log_error(f"Opcode: {op_name}")
        log_error(f"Esperado: {expected}")
        log_error(f"Recebido: {current}")
        assert False, f"Falha no caso: {case_desc}"

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):
    
    # Reproduz os testes manuais dirigidos do decoder_tb.vhd.
    
    log_header("Testes Dirigidos - Decoder")
    
    # Lista de opcodes para teste sequencial
    test_cases = [
        (OP_R_TYPE, "R-Type (ADD, SUB...)"),
        (OP_I_TYPE, "I-Type (ADDI, ORI...)"),
        (OP_LOAD,   "LOAD (LW, LB...)"),
        (OP_STORE,  "STORE (SW, SB...)"),
        (OP_BRANCH, "BRANCH (BEQ, BNE...)"),
        (OP_JAL,    "JAL"),
        (OP_JALR,   "JALR"),
        (OP_LUI,    "LUI"),
        (OP_AUIPC,  "AUIPC"),
        (OP_FENCE,  "FENCE (NOP)"),
        (OP_SYSTEM, "SYSTEM (ECALL - NOP)"),
        (0x7F,      "Illegal Opcode (NOP)") # Opcode inexistente (INVALID)
    ]
    
    # Executa os testes dirigidos
    for opcode, desc in test_cases:
        expected = model_decoder(opcode)
        await verify_decoder(dut, opcode, expected, desc)
    
    # Escreve mensagem de sucesso
    log_success("Todos os Testes Dirigidos Passaram!")


@cocotb.test()
async def stress_test_randomized(dut):
    
    # Gera opcodes aleatórios e verifica robustez (garante que opcodes inválidos geram NOPs).
    
    # Número de iterações aleatórias
    NUM_ITERATIONS = 5000

    # Contador de hits por tipo de instrução
    hits = {}
    
    # Escreve cabeçalho do teste
    log_header(f"Stress Test Randomized ({NUM_ITERATIONS} iterações)")
    
    # Lista de opcodes válidos conhecidos
    valid_opcodes = list(OP_NAMES.keys())
    
    # Loop de iterações aleatórias 
    for i in range(NUM_ITERATIONS):
        
        # Gera entradas aleatórias
        # 80% de chance de gerar um opcode válido, 20% de lixo aleatório
        if random.random() < 0.8:
            opcode = random.choice(valid_opcodes)
        else:
            opcode = random.randint(0, 127) # 7 bits
        
        # Calcula esperado pelo modelo
        expected = model_decoder(opcode)
        
        # Verifica DUT
        op_desc = OP_NAMES.get(opcode, "INVALID")
        await verify_decoder(dut, opcode, expected, f"Iter {i} [{op_desc}]")
        
        # Estatísticas
        hits[op_desc] = hits.get(op_desc, 0) + 1

    # Relatório de cobertura de operações
    for op, count in sorted(hits.items()):
        log_info(f"{op:<10}: {count} vezes")
        
    # Escreve mensagem de sucesso do teste
    log_success(f"{NUM_ITERATIONS} Vetores Aleatórios Verificados com Sucesso")