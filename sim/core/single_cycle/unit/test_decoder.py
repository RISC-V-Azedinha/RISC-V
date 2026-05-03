# ====================================================================================================
# File: test_decoder.py
# ====================================================================================================
#
# >>> Descrição: Testbench para o Decoder.
#     Verifica a geração correta dos sinais de controle para diferentes tipos de instruções.
#
# ====================================================================================================

# Importando as bibliotecas necessárias para o teste
import cocotb
import random

# Importando as funções de logging e utilitários de teste customizados
from sim.core.single_cycle.include.test_utils import log_header, log_info, log_success, log_error, settle

# Códigos de Operação (opcodes) para as instruções RISC-V
OP_R_TYPE   = 0x33 
OP_I_TYPE   = 0x13 
OP_LOAD     = 0x03 
OP_STORE    = 0x23 
OP_BRANCH   = 0x63 
OP_JAL      = 0x6F 
OP_JALR     = 0x67 
OP_LUI      = 0x37 
OP_AUIPC    = 0x17 
OP_FENCE    = 0x0F 
OP_SYSTEM   = 0x73 

# Mapeamento de opcodes para nomes legíveis (para melhor logging)
OP_NAMES = {
    OP_R_TYPE: "R-Type", OP_I_TYPE: "I-Type", OP_LOAD: "LOAD", OP_STORE: "STORE",
    OP_BRANCH: "BRANCH", OP_JAL: "JAL", OP_JALR: "JALR", OP_LUI: "LUI",
    OP_AUIPC: "AUIPC", OP_FENCE: "FENCE", OP_SYSTEM: "SYSTEM"
}

# Classe para representar os sinais de controle esperados para cada opcode
class ControlSignals:
    """Estrutura para armazenar os sinais de controle gerados pelo decoder"""
    
    def __init__(self, rw=0, alu_a=0, alu_b=0, wb_src=0, mw=0, br=0, jmp=0, alu_op=0):
        """Inicializa os sinais de controle com valores padrão (NOP) ou específicos"""
        
        self.reg_write = rw
        self.alu_src_a = alu_a
        self.alu_src_b = alu_b
        self.wb_src = wb_src
        self.mem_write = mw
        self.branch = br
        self.jump = jmp
        self.alu_op = alu_op

    def __eq__(self, other):
        """Compara dois objetos ControlSignals para verificar se são iguais (todos os sinais correspondem)"""
        
        return self.__dict__ == other.__dict__

    def __str__(self):
        """Retorna uma representação legível dos sinais de controle para facilitar o logging e a depuração"""
        
        return (f"RW={self.reg_write} SrcA={self.alu_src_a} SrcB={self.alu_src_b} "
                f"WBSrc={self.wb_src} MW={self.mem_write} "
                f"Br={self.branch} Jmp={self.jump} AOp={self.alu_op}")

def model_decoder(opcode):
    """Modelo de referência para os sinais de controle gerados pelo decoder com base no opcode"""
    
    # Golden Model: Define os sinais de controle esperados para cada tipo de instrução com base no opcode, seguindo a especificação do RISC-V. Instruções desconhecidas ou ilegais resultam em sinais de controle que correspondem a um NOP (sem operação).
    
    if opcode == OP_R_TYPE:   return ControlSignals(rw=1, alu_a=0, alu_b=0, wb_src=0, mw=0, br=0, jmp=0, alu_op=0b10)
    elif opcode == OP_I_TYPE: return ControlSignals(rw=1, alu_a=0, alu_b=1, wb_src=0, mw=0, br=0, jmp=0, alu_op=0b11)
    elif opcode == OP_LOAD:   return ControlSignals(rw=1, alu_a=0, alu_b=1, wb_src=1, mw=0, br=0, jmp=0, alu_op=0b00)
    elif opcode == OP_STORE:  return ControlSignals(rw=0, alu_a=0, alu_b=1, wb_src=0, mw=1, br=0, jmp=0, alu_op=0b00)
    elif opcode == OP_BRANCH: return ControlSignals(rw=0, alu_a=0, alu_b=0, wb_src=0, mw=0, br=1, jmp=0, alu_op=0b01)
    elif opcode == OP_JAL:    return ControlSignals(rw=1, alu_a=0, alu_b=0, wb_src=2, mw=0, br=0, jmp=1, alu_op=0b00)
    elif opcode == OP_JALR:   return ControlSignals(rw=1, alu_a=0, alu_b=1, wb_src=2, mw=0, br=0, jmp=1, alu_op=0b00)
    elif opcode == OP_LUI:    return ControlSignals(rw=1, alu_a=2, alu_b=1, wb_src=0, mw=0, br=0, jmp=0, alu_op=0b00)
    elif opcode == OP_AUIPC:  return ControlSignals(rw=1, alu_a=1, alu_b=1, wb_src=0, mw=0, br=0, jmp=0, alu_op=0b00)
    else:                     return ControlSignals() # NOP

async def verify_decoder(dut, opcode, expected, case_desc):
    """Configura o opcode de entrada, aguarda a estabilização dos sinais e verifica se os sinais de controle gerados correspondem ao esperado"""
    
    dut.Opcode_i.value = opcode
    await settle()
    
    current = ControlSignals(
        rw      = int(dut.reg_write_o.value),
        alu_a   = int(dut.alu_src_a_o.value),
        alu_b   = int(dut.alu_src_b_o.value),
        wb_src  = int(dut.wb_src_o.value), # Lendo o sinal corrigido
        mw      = int(dut.mem_write_o.value),
        br      = int(dut.branch_o.value),
        jmp     = int(dut.jump_o.value),
        alu_op  = int(dut.alu_op_o.value)
    )
    
    if current != expected:
        op_name = OP_NAMES.get(opcode, f"UNK({hex(opcode)})")
        log_error(f"FALHA: {case_desc}")
        log_error(f"Opcode: {op_name}")
        log_error(f"Esperado: {expected}")
        log_error(f"Recebido: {current}")
        assert False, f"Falha no caso: {case_desc}"

@cocotb.test()
async def run_directed_tests(dut):
    """Executa testes dirigidos para cada opcode conhecido, verificando se os sinais de controle gerados pelo decoder correspondem ao modelo de referência para cada tipo de instrução"""
    
    log_header("Testes Dirigidos - Decoder")
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
        (0x7F,      "Illegal Opcode (NOP)") 
    ]
    
    for opcode, desc in test_cases:
        expected = model_decoder(opcode)
        await verify_decoder(dut, opcode, expected, desc)
        
    log_success("Todos os Testes Dirigidos Passaram!")

@cocotb.test()
async def stress_test_randomized(dut):
    """Realiza um teste de estresse com opcodes aleatórios, verificando se o decoder responde corretamente a uma ampla variedade de entradas, incluindo opcodes válidos e inválidos, para garantir a robustez do design"""
    
    NUM_ITERATIONS = 5000
    hits = {}
    log_header(f"Stress Test Randomized ({NUM_ITERATIONS} iterações)")
    valid_opcodes = list(OP_NAMES.keys())
    
    for i in range(NUM_ITERATIONS):
        opcode = random.choice(valid_opcodes) if random.random() < 0.8 else random.randint(0, 127)
        expected = model_decoder(opcode)
        op_desc = OP_NAMES.get(opcode, "INVALID")
        await verify_decoder(dut, opcode, expected, f"Iter {i} [{op_desc}]")
        hits[op_desc] = hits.get(op_desc, 0) + 1

    for op, count in sorted(hits.items()):
        log_info(f"{op:<10}: {count} vezes")
        
    log_success(f"{NUM_ITERATIONS} Vetores Aleatórios Verificados com Sucesso")