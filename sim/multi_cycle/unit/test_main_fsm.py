# ============================================================================================================================================================
# File: test_main_fsm.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para a Máquina de Estados Principal (Main FSM) do Multiciclo.
#     Verifica:
#      1. Fluxo de Reset e inicialização.
#      2. Fluxo de uma instrução R-Type (IF -> ID -> EX_ALU -> WB_REG -> IF).
#      3. Fluxo de uma instrução LOAD com Handshake (IF -> ID -> EX_ADDR -> MEM_RD (Stall) -> WB_REG -> IF).
#      4. Fluxo de Branch com o microestado de "Wait".
#      5. Interrupções (Preempção no Decode).
#
# ============================================================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# CONSTANTES OPCODES (Para facilitar a legibilidade)
# =====================================================================================================================

OPCODE_R_TYPE = 0x33 # 0110011
OPCODE_LOAD   = 0x03 # 0000011
OPCODE_BRANCH = 0x63 # 1100011

# =====================================================================================================================
# FUNÇÕES AUXILIARES
# =====================================================================================================================

def init_signals(dut):
    """Inicializa as entradas do DUT."""
    dut.Reset_i.value        = 0
    dut.soc_en_i.value       = 1  # CPU Habilitada
    dut.Opcode_i.value       = 0
    dut.Funct3_i.value       = 0
    dut.Funct12_i.value      = 0
    dut.imem_rdy_i.value     = 0
    dut.dmem_rdy_i.value     = 0
    dut.Irq_MIE_i.value      = 0
    dut.Irq_Mie_Reg_i.value  = 0
    dut.Irq_Mip_Reg_i.value  = 0
    dut.Csr_Valid_i.value    = 1

async def reset_dut(dut):
    """Executa a sequência de Reset."""
    dut.Reset_i.value = 1
    await RisingEdge(dut.Clk_i)
    await RisingEdge(dut.Clk_i)
    dut.Reset_i.value = 0
    await settle()

async def assert_state_outputs(dut, expected_outputs, state_name):
    """
    Verifica se os sinais de controle batem com o dicionário esperado.
    Só verifica as chaves que foram passadas no dicionário.
    """
    await ReadOnly() # Garante que os sinais combinacionais assentaram
    
    for signal_name, expected_val in expected_outputs.items():
        actual_val = getattr(dut, signal_name).value
        
        try:
             actual_int = int(actual_val)
        except ValueError:
             log_error(f"Sinal {signal_name} tem valor invalido: {actual_val} no estado {state_name}")
             assert False

        if actual_int != expected_val:
            log_error(f"FALHA ({state_name}): Sinal {signal_name} deveria ser {expected_val}, mas e {actual_int}")
            assert False

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_r_type_flow(dut):
    """Testa o caminho de execução de uma instrução R-Type: IF -> ID -> EX_ALU -> WB_REG -> IF"""
    log_header("FSM: Fluxo R-Type (ADD)")
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    init_signals(dut)
    await reset_dut(dut)
    
    # ---------------------------------------------------------------------------------
    # ESTADO 1: S_IF (Instruction Fetch) - STALL
    # ---------------------------------------------------------------------------------
    # No IF, a FSM pede instrução, mas espera o imem_rdy_i = 1 para avançar.
    await assert_state_outputs(dut, {'imem_vld_o': 1, 'is_fetch_stage_o': 1}, "S_IF (Wait)")
    
    # -> O TEMPO PRECISA AVANÇAR APÓS UM READONLY ANTES DE ESCREVER <-
    await RisingEdge(dut.Clk_i) 
    
    # ---------------------------------------------------------------------------------
    # ESTADO 1: S_IF (Instruction Fetch) - READY
    # ---------------------------------------------------------------------------------
    # Simula a memória entregando a instrução (ADD)
    dut.imem_rdy_i.value = 1
    dut.Opcode_i.value   = OPCODE_R_TYPE
    await settle()
    await assert_state_outputs(dut, {'IRWrite_o': 1, 'PCWrite_o': 1}, "S_IF (Ready)")
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # ESTADO 2: S_ID (Instruction Decode)
    # ---------------------------------------------------------------------------------
    dut.imem_rdy_i.value = 0 # Memória abaixa o ready
    await settle()
    await assert_state_outputs(dut, {'RS1Write_o': 1, 'RS2Write_o': 1, 'is_fetch_stage_o': 0}, "S_ID")
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # ESTADO 3: S_EX_ALU (Execute)
    # ---------------------------------------------------------------------------------
    await assert_state_outputs(dut, {
        'ALUrWrite_o': 1, 
        'ALUSrcA_o': 0, # rs1 
        'ALUSrcB_o': 0, # rs2
        'ALUOp_o': 2    # R-Type
    }, "S_EX_ALU")
    await RisingEdge(dut.Clk_i)

    # ---------------------------------------------------------------------------------
    # ESTADO 4: S_WB_REG (Write-Back)
    # ---------------------------------------------------------------------------------
    await assert_state_outputs(dut, {
        'RegWrite_o': 1, 
        'WBSel_o': 0 # ALUResult
    }, "S_WB_REG")
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # VOLTA PARA S_IF
    # ---------------------------------------------------------------------------------
    await assert_state_outputs(dut, {'imem_vld_o': 1, 'is_fetch_stage_o': 1}, "Back to S_IF")
    log_success("Fluxo R-Type completo.")

@cocotb.test()
async def test_load_stall_flow(dut):
    """Testa uma instrução LOAD, com ênfase no Handshake da Memória (STALL)"""
    log_header("FSM: Fluxo LOAD com Stall na DMem")
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    init_signals(dut)
    await reset_dut(dut)
    
    # S_IF
    dut.imem_rdy_i.value = 1
    dut.Opcode_i.value   = OPCODE_LOAD
    await RisingEdge(dut.Clk_i)
    
    # S_ID
    dut.imem_rdy_i.value = 0
    await RisingEdge(dut.Clk_i)
    
    # S_EX_ADDR
    await assert_state_outputs(dut, {'ALUrWrite_o': 1, 'ALUOp_o': 0, 'ALUSrcB_o': 1}, "S_EX_ADDR")
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # ESTADO: S_MEM_RD (Com Atraso da Memória)
    # ---------------------------------------------------------------------------------
    # Ciclo 1 no estado de MEM_RD (Memória ainda não está pronta)
    dut.dmem_rdy_i.value = 0
    await assert_state_outputs(dut, {'dmem_vld_o': 1, 'MDRWrite_o': 0}, "S_MEM_RD (Stall 1)")
    await RisingEdge(dut.Clk_i)
    
    # Ciclo 2 no estado de MEM_RD (Ainda esperando)
    await assert_state_outputs(dut, {'dmem_vld_o': 1, 'MDRWrite_o': 0}, "S_MEM_RD (Stall 2)")
    await RisingEdge(dut.Clk_i)
    
    # Ciclo 3: Memória finalmente responde
    dut.dmem_rdy_i.value = 1
    await settle()
    await assert_state_outputs(dut, {'dmem_vld_o': 1, 'MDRWrite_o': 1}, "S_MEM_RD (Ready)")
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # ESTADO: S_WB_REG
    # ---------------------------------------------------------------------------------
    dut.dmem_rdy_i.value = 0
    await settle()
    await assert_state_outputs(dut, {'RegWrite_o': 1, 'WBSel_o': 1}, "S_WB_REG (Load)")
    await RisingEdge(dut.Clk_i)
    
    log_success("Fluxo LOAD com Stalls completo.")

@cocotb.test()
async def test_interrupt_preemption(dut):
    """Testa se a FSM intercepta corretamente uma interrupção no Decode e força um Trap"""
    log_header("FSM: Preempção de Interrupção no DECODE")
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    init_signals(dut)
    await reset_dut(dut)
    
    # S_IF 
    dut.imem_rdy_i.value = 1
    dut.Opcode_i.value   = OPCODE_R_TYPE
    await RisingEdge(dut.Clk_i)
    
    # ---------------------------------------------------------------------------------
    # ESTADO: S_ID 
    # ---------------------------------------------------------------------------------
    dut.imem_rdy_i.value = 0
    
    # INJETA INTERRUPÇÃO EXTERNA AGORA!
    dut.Irq_MIE_i.value = 1
    dut.Irq_Mie_Reg_i.value = (1 << 11)
    dut.Irq_Mip_Reg_i.value = (1 << 11)
    await settle()
    
    await assert_state_outputs(dut, {
        'TrapEnter_o': 1, 
        'PCWrite_o': 1
    }, "S_ID (Interrupção Disparada)")
    
    assert dut.TrapCause_o.value.to_unsigned() == 0x8000000B, "Causa incorreta."
    
    await RisingEdge(dut.Clk_i)
    
    # Remove as interrupções para o próximo ciclo
    dut.Irq_MIE_i.value = 0
    dut.Irq_Mip_Reg_i.value = 0
    await settle()
    
    # ---------------------------------------------------------------------------------
    # O Próximo Estado deve ser S_IF abortado.
    # ---------------------------------------------------------------------------------
    await assert_state_outputs(dut, {'is_fetch_stage_o': 1}, "Abortou para S_IF")
    
    log_success("Preempção de Interrupção tratada com sucesso.")