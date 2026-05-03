# =====================================================================================================================
# File: test_datapath.py
# =====================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from sim.core.single_cycle.include.test_utils import log_header, log_success, log_info, log_error, settle

# =====================================================================================================================
# CONSTANTES (Instruções pré-compiladas)
# =====================================================================================================================

# ADD x3, x1, x2  (Opcode: 0110011, rd: x3, funct3: 000, rs1: x1, rs2: x2, funct7: 0000000)
INSTR_ADD = 0x002081B3

# LW x4, 4(x1)    (Opcode: 0000011, rd: x4, funct3: 010, rs1: x1, imm: 4)
INSTR_LW  = 0x0040A203

# =====================================================================================================================
# FUNÇÕES DE CONTROLE
# =====================================================================================================================

def init_datapath(dut):
    """Zera os sinais de controle (Muxes e Enables)."""
    dut.PCWrite_i.value    = 0
    dut.OPCWrite_i.value   = 0
    dut.IRWrite_i.value    = 0
    dut.RS1Write_i.value   = 0
    dut.RS2Write_i.value   = 0
    dut.ALUWrite_i.value   = 0
    dut.MDRWrite_i.value   = 0
    dut.reg_write_i.value  = 0
    dut.mem_write_i.value  = 0
    
    dut.pcsrc_i.value      = 0  
    dut.alu_src_a_i.value  = 0  
    dut.alu_src_b_i.value  = 0  
    dut.wb_src_i.value     = 0  
    dut.alucontrol_i.value = 0  

async def reset_dut(dut):
    init_datapath(dut)
    dut.Reset_i.value = 1
    await RisingEdge(dut.CLK_i)
    await RisingEdge(dut.CLK_i)
    dut.Reset_i.value = 0
    await settle()

async def execute_addi(dut, rd, imm):
    """Executa um ADDI rd, x0, imm manualmente."""
    imm_12 = imm & 0xFFF
    instr = (imm_12 << 20) | (0 << 15) | (0 << 12) | (rd << 7) | 0x13
    
    # 1. FETCH
    dut.IMem_data_i.value = instr
    dut.IRWrite_i.value   = 1
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # 2. DECODE
    dut.RS1Write_i.value = 1
    dut.RS2Write_i.value = 1
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # 3. EXECUTE
    dut.alu_src_a_i.value  = 0 # RS1 (x0 = 0)
    dut.alu_src_b_i.value  = 1 # IMM
    dut.alucontrol_i.value = 0 # ADD
    dut.ALUWrite_i.value   = 1
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # 4. WB
    dut.wb_src_i.value    = 0 # ALUResult
    dut.reg_write_i.value = 1
    await RisingEdge(dut.CLK_i) 
    init_datapath(dut)

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_rtype_flow(dut):
    log_header("Testando Fluxo R-Type (ADD x3, x1, x2)")
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())
    await reset_dut(dut)

    log_info("Setup: Executando ADDI para carregar x1=10 e x2=20...")
    await execute_addi(dut, 1, 10)
    await execute_addi(dut, 2, 20)
    
    # -------------------------------------------------------------------------
    # CICLO 1: FETCH
    # -------------------------------------------------------------------------
    log_info("Ciclo 1: FETCH")
    dut.IMem_data_i.value = INSTR_ADD 
    dut.IRWrite_i.value   = 1         
    dut.PCWrite_i.value   = 1         
    dut.pcsrc_i.value     = 0         
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    await settle()
    assert dut.DBG_instruction_o.value.to_unsigned() == INSTR_ADD, "IR não capturou a instrução."

    # -------------------------------------------------------------------------
    # CICLO 2: DECODE
    # -------------------------------------------------------------------------
    log_info("Ciclo 2: DECODE")
    dut.RS1Write_i.value = 1 
    dut.RS2Write_i.value = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # -------------------------------------------------------------------------
    # CICLO 3: EXECUTE
    # -------------------------------------------------------------------------
    log_info("Ciclo 3: EXECUTE")
    dut.alu_src_a_i.value  = 0 # RS1
    dut.alu_src_b_i.value  = 0 # RS2
    dut.alucontrol_i.value = 0 # ADD
    dut.ALUWrite_i.value   = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)

    # -------------------------------------------------------------------------
    # CICLO 4: WRITE-BACK
    # -------------------------------------------------------------------------
    log_info("Ciclo 4: WRITE-BACK")
    dut.wb_src_i.value    = 0 # ALUResult
    dut.reg_write_i.value = 1 # Grava em x3
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # -------------------------------------------------------------------------
    # VERIFICAÇÃO: Carrega o IR no novo ciclo para ler a saída de x3 no DBG
    # -------------------------------------------------------------------------
    dut.IMem_data_i.value = 0x00018000 # Instrução Dummy com rs1=3 (Bits 19:15 = "00011")
    dut.IRWrite_i.value   = 1
    await RisingEdge(dut.CLK_i) # Grava o Dummy no IR
    init_datapath(dut)
    
    # Agora a instrução no IR aponta rs1 para x3. 
    # Precisamos dar um clock para que o dado passe do RegFile para o r_RS1!
    dut.RS1Write_i.value = 1 
    await RisingEdge(dut.CLK_i) 
    init_datapath(dut)
    
    await settle()
    assert dut.DBG_rs1_data_o.value.to_unsigned() == 30, "Write-Back falhou. x3 não contém 30."
    log_success("Fluxo R-Type Validado com Sucesso.")


@cocotb.test()
async def test_load_flow(dut):
    log_header("Testando Fluxo LOAD (LW x4, 4(x1))")
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())
    await reset_dut(dut)
    
    log_info("Setup: Executando ADDI para carregar o endereço base x1=0x100...")
    await execute_addi(dut, 1, 0x100)

    # -------------------------------------------------------------------------
    # CICLO 1: FETCH
    # -------------------------------------------------------------------------
    dut.IMem_data_i.value = INSTR_LW 
    dut.IRWrite_i.value   = 1         
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)

    # -------------------------------------------------------------------------
    # CICLO 2: DECODE
    # -------------------------------------------------------------------------
    dut.RS1Write_i.value = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)

    # -------------------------------------------------------------------------
    # CICLO 3: EXECUTE (Cálculo de Endereço)
    # -------------------------------------------------------------------------
    dut.alu_src_a_i.value  = 0 # RS1
    dut.alu_src_b_i.value  = 1 # IMM
    dut.alucontrol_i.value = 0 # ADD
    dut.ALUWrite_i.value   = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    await settle()
    assert dut.DMem_addr_o.value.to_unsigned() == 0x104, "Cálculo de endereço da ALU falhou."

    # -------------------------------------------------------------------------
    # CICLO 4: MEMORY (Leitura de Dados)
    # -------------------------------------------------------------------------
    dut.DMem_data_i.value = 0xDEADBEEF
    dut.MDRWrite_i.value  = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)

    # -------------------------------------------------------------------------
    # CICLO 5: WRITE-BACK
    # -------------------------------------------------------------------------
    dut.wb_src_i.value    = 1 # MDR
    dut.reg_write_i.value = 1 
    await RisingEdge(dut.CLK_i)
    init_datapath(dut)
    
    # -------------------------------------------------------------------------
    # VERIFICAÇÃO: Lendo x4
    # -------------------------------------------------------------------------
    dut.IMem_data_i.value = 0x00020000 # Instrução Dummy com rs1=4
    dut.IRWrite_i.value   = 1
    await RisingEdge(dut.CLK_i) # Grava Dummy no IR
    init_datapath(dut)
    
    dut.RS1Write_i.value = 1 
    await RisingEdge(dut.CLK_i) 
    init_datapath(dut)
    
    await settle()
    assert dut.DBG_rs1_data_o.value.to_unsigned() == 0xDEADBEEF, "Write-Back do LOAD falhou."
    log_success("Fluxo LOAD Validado com Sucesso.")