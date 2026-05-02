import cocotb
import random
from test_utils import (
    OP_R_TYPE, OP_I_TYPE, OP_LOAD, OP_STORE, OP_BRANCH,
    OP_JAL, OP_JALR, OP_LUI, OP_AUIPC, log_header, 
    log_info, log_success, log_error, settle
)

BRANCH_NAMES = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE", 6: "BLTU", 7: "BGEU"}

class ControlExpected:
    def __init__(self, rw=0, src_a=0, src_b=0, wb_src=0, mw=0, pcsrc=0, aluc=0):
        self.reg_write = rw
        self.alu_src_a = src_a
        self.alu_src_b = src_b
        self.wb_src = wb_src
        self.mem_write = mw
        self.pcsrc = pcsrc
        self.alucontrol = aluc

    def __eq__(self, other):
        return self.__dict__ == other.__dict__

    def __str__(self):
        return (f"RW={self.reg_write} SrcA={self.alu_src_a} SrcB={self.alu_src_b} "
                f"WBSrc={self.wb_src} MW={self.mem_write} "
                f"PCSrc={self.pcsrc} ALUC={self.alucontrol}")

def model_control(instruction, alu_zero):
    opcode = instruction & 0x7F
    f3 = (instruction >> 12) & 0x07
    f7_5 = (instruction >> 30) & 0x01

    res = ControlExpected()
    alu_op = 0

    if opcode == OP_R_TYPE:   res.reg_write, res.alu_src_b, alu_op = 1, 0, 2
    elif opcode == OP_I_TYPE: res.reg_write, res.alu_src_b, alu_op = 1, 1, 3
    elif opcode == OP_LOAD:   res.reg_write, res.alu_src_b, res.wb_src, alu_op = 1, 1, 1, 0
    elif opcode == OP_STORE:  res.alu_src_b, res.mem_write, alu_op = 1, 1, 0
    elif opcode == OP_BRANCH: alu_op = 1
    elif opcode == OP_JAL:    res.reg_write, res.wb_src, res.pcsrc = 1, 2, 1
    elif opcode == OP_JALR:   res.reg_write, res.alu_src_b, res.wb_src, alu_op, res.pcsrc = 1, 1, 2, 0, 2
    elif opcode == OP_LUI:    res.reg_write, res.alu_src_a, res.alu_src_b, alu_op = 1, 2, 1, 0
    elif opcode == OP_AUIPC:  res.reg_write, res.alu_src_a, res.alu_src_b, alu_op = 1, 1, 1, 0

    if alu_op == 0: res.alucontrol = 0
    elif alu_op == 1:
        if f3 in [0, 1]: res.alucontrol = 8
        elif f3 in [4, 5]: res.alucontrol = 2
        elif f3 in [6, 7]: res.alucontrol = 3
    elif alu_op == 2:
        map_r = {0: 8 if f7_5 else 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 13 if f7_5 else 5, 6: 6, 7: 7}
        res.alucontrol = map_r.get(f3, 0)
    elif alu_op == 3:
        map_i = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 13 if f7_5 else 5, 6: 6, 7: 7}
        res.alucontrol = map_i.get(f3, 0)

    branch_met = False
    if opcode == OP_BRANCH:
        if f3 == 0:   branch_met = (alu_zero == 1)
        elif f3 == 1: branch_met = (alu_zero == 0)
        elif f3 == 4: branch_met = (alu_zero == 0)
        elif f3 == 5: branch_met = (alu_zero == 1)
        elif f3 == 6: branch_met = (alu_zero == 0)
        elif f3 == 7: branch_met = (alu_zero == 1)
        if branch_met: res.pcsrc = 1
        
    return res

async def verify(dut, inst, zero, msg=""):
    dut.Instruction_i.value = inst
    dut.ALU_Zero_i.value = zero
    await settle()
    
    expected = model_control(inst, zero)
    current = ControlExpected(
        int(dut.reg_write_o.value), int(dut.alu_src_a_o.value), int(dut.alu_src_b_o.value),
        int(dut.wb_src_o.value), int(dut.mem_write_o.value),
        int(dut.pcsrc_o.value), int(dut.alucontrol_o.value)
    )
    
    if current != expected:
        log_error(f"FALHA: {msg} | Inst={hex(inst)} Zero={zero}")
        log_error(f"Esperado: {expected}")
        log_error(f"Recebido: {current}")
        assert False

@cocotb.test()
async def test_boundary_cases(dut):
    log_header("Boundary Tests")
    log_info("Verificando instrução nula (0x00000000)...")
    await verify(dut, 0x00000000, 0, "All Zeros")
    log_info("Verificando instrução cheia (0xFFFFFFFF)...")
    await verify(dut, 0xFFFFFFFF, 1, "All Ones")
    log_success("Testes de limite aprovados")

@cocotb.test()
async def test_illegal_opcodes(dut):
    log_header("Illegal Opcodes Test")
    valid_opcodes = [OP_R_TYPE, OP_I_TYPE, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC]
    count = 0
    for op in range(128):
        if op not in valid_opcodes:
            await verify(dut, op, random.choice([0,1]), f"Opcode={hex(op)}")
            count += 1
    log_info(f"{count} opcodes ilegais verificados.")
    log_success("Todos opcodes ilegais geraram NOP")

@cocotb.test()
async def test_branch_matrix(dut):
    log_header("Branch Matrix Test")
    f3_codes = [0, 1, 4, 5, 6, 7]
    for f3 in f3_codes:
        name = BRANCH_NAMES.get(f3, "UNK")
        for zero in [0, 1]:
            log_info(f"Testando {name:<4} com ALU_Zero={zero}")
            inst = OP_BRANCH | (f3 << 12)
            await verify(dut, inst, zero, f"Branch={name}")
    log_success("Matriz de Branch validada")

@cocotb.test()
async def stress_test_control(dut):
    log_header("Stress Test (10000 iterações)")
    opcodes = [OP_R_TYPE, OP_I_TYPE, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC]
    for i in range(10000):
        if i % 2000 == 0:
            log_info(f"Progresso: {i}/10000 iterações concluídas...")
        inst = random.choice(opcodes) | (random.randint(0, 0xFFFFFF) << 7)
        await verify(dut, inst, random.choice([0, 1]), "Stress")
    log_success("Stress test concluído com sucesso")