# ============================================================================================================================================================
# File: test_control.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench de Integração para a Unidade de Controle Top-Level (Multi-Cycle).
#     Verifica a interligação correta entre a Main FSM, ALU Control e Branch Unit.
#     O foco principal é validar a lógica de `pc_write` combinada (Salto Condicional/Incondicional)
#     e a tradução correta das operações para a ALU.
#
# ============================================================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
from test_utils import log_header, log_success, log_info, log_error, settle

# =====================================================================================================================
# CONSTANTES OPCODES & FUNCTS
# =====================================================================================================================

OPCODE_R_TYPE = 0x33 # 0110011 (ADD, SUB, AND, OR...)
OPCODE_BRANCH = 0x63 # 1100011 (BEQ, BNE...)

FUNCT3_BEQ    = 0x0
FUNCT3_ADD    = 0x0
FUNCT7_ADD    = 0x00
FUNCT7_SUB    = 0x20

# =====================================================================================================================
# FUNÇÕES AUXILIARES
# =====================================================================================================================

def init_signals(dut):
    """Inicializa as entradas do DUT."""
    dut.Reset_i.value           = 0
    dut.soc_en_i.value          = 1
    dut.imem_rdy_i.value        = 0
    dut.dmem_rdy_i.value        = 0
    dut.Instruction_i.value     = 0
    dut.ALU_Zero_i.value        = 0
    dut.CSR_Mstatus_MIE_i.value = 0
    dut.CSR_Mie_i.value         = 0
    dut.CSR_Mip_i.value         = 0
    dut.Csr_Valid_i.value       = 1

async def reset_dut(dut):
    """Aplica o Reset Síncrono."""
    init_signals(dut)
    dut.Reset_i.value = 1
    await RisingEdge(dut.Clk_i)
    await RisingEdge(dut.Clk_i)
    dut.Reset_i.value = 0
    await settle()

def build_instruction(opcode, funct3, funct7):
    """Constrói uma instrução dummy (sem rs1, rs2 ou rd) só para estimular a FSM."""
    instr = (funct7 << 25) | (funct3 << 12) | opcode
    return instr

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_alu_control_integration(dut):
    """Verifica se o Control traduz corretamente R-Type para a ALU no estágio EXECUTE."""
    log_header("Integration: Control -> ALU Control (R-Type ADD/SUB)")
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    await reset_dut(dut)
    
    # ---------------------------------------------------------------------------------
    # 1. Testa instrução ADD (R-Type)
    # ---------------------------------------------------------------------------------
    dut.imem_rdy_i.value    = 1
    dut.Instruction_i.value = build_instruction(OPCODE_R_TYPE, FUNCT3_ADD, FUNCT7_ADD)
    
    await RisingEdge(dut.Clk_i) # Vai para S_IF (Ready) -> S_ID
    dut.imem_rdy_i.value = 0
    
    await RisingEdge(dut.Clk_i) # Vai para S_ID -> S_EX_ALU
    
    # No estágio S_EX_ALU, a FSM manda ALUOp="10". A ALUControl vê Funct3=0 e Funct7=0 e manda ADD="0000"
    await settle()
    
    alu_ctrl = dut.Ctrl_alu_control_o.value.to_unsigned()
    assert alu_ctrl == 0, f"Erro: ALU Control deveria ser 0 (ADD), mas é {alu_ctrl}"
    
    log_success("Traducao para ADD [OK]")

@cocotb.test()
async def test_branch_unit_integration(dut):
    """Verifica se a Branch Unit aciona o PCWrite corretamente."""
    log_header("Integration: Control -> Branch Unit -> PCWrite")
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    await reset_dut(dut)
    
    # ---------------------------------------------------------------------------------
    # Setup BEQ (Branch if Equal)
    # ---------------------------------------------------------------------------------
    dut.imem_rdy_i.value    = 1
    dut.Instruction_i.value = build_instruction(OPCODE_BRANCH, FUNCT3_BEQ, 0)
    
    await RisingEdge(dut.Clk_i) # Borda 1: S_IF -> S_ID
    dut.imem_rdy_i.value = 0
    
    await RisingEdge(dut.Clk_i) # Borda 2: S_ID -> S_EX_BR (Wait=0)
    
    # No ciclo S_EX_BR (Wait=0), a FSM manda "pc_write_cond = 0" 
    await settle()
    assert dut.Ctrl_pc_write_o.value == 0, "PCWrite ativou cedo demais!"
    
    # =================================================================================
    # CASO 1: ALU NÃO deu Zero (Branch NOT taken)
    # =================================================================================
    dut.ALU_Zero_i.value = 0
    
    # A próxima borda avança a FSM para Wait=1 e grava a flag Zero ao mesmo tempo
    await RisingEdge(dut.Clk_i) 
    await settle()
    
    # PC_Write deve ser 0 (Não toma o branch)
    assert dut.Ctrl_pc_write_o.value == 0, "PCWrite ativou mas a ALU não deu ZERO!"
    log_info("Branch NOT taken verificado [OK]")
    
    # =================================================================================
    # CASO 2: ALU DEU Zero (Branch TAKEN)
    # =================================================================================
    await reset_dut(dut)
    dut.imem_rdy_i.value    = 1
    dut.Instruction_i.value = build_instruction(OPCODE_BRANCH, FUNCT3_BEQ, 0)
    
    await RisingEdge(dut.Clk_i) # Borda 1: S_IF -> S_ID
    dut.imem_rdy_i.value = 0
    
    await RisingEdge(dut.Clk_i) # Borda 2: S_ID -> S_EX_BR (Wait=0)
    
    # Prepara a flag Zero AGORA, enquanto a FSM ainda espera o clock
    dut.ALU_Zero_i.value = 1
    
    # A próxima borda avança a FSM para Wait=1 e grava a flag Zero ao mesmo tempo
    await RisingEdge(dut.Clk_i) 
    await settle()
    
    # AGORA o PC_Write deve ser 1 (Toma o branch)
    assert dut.Ctrl_pc_write_o.value == 1, "PCWrite NAO ativou com ALU=Zero e BEQ!"
    log_info("Branch TAKEN verificado [OK]")
    
    log_success("Integração de Branch validada com sucesso.")