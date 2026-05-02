# ============================================================================================================================================================
# File: test_csr_file.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para o Banco de Registradores de Controle e Status (CSR File).
#     Verifica:
#      1. Operações Atômicas: CSRRW (Write), CSRRS (Set), CSRRC (Clear).
#      2. Tratamento de Traps (Hardware): Salvamento automático de PC e Causa, e MRET.
#      3. Hardwired bits (Ex: MTVEC[1:0] = 00).
#      4. Mapeamento Assíncrono do registrador MIP.
#      5. Detecção de endereços inválidos.
#
# ============================================================================================================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import random

from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# CONSTANTES (Mapeamento RISC-V Privileged)
# =====================================================================================================================

ADDR_MSTATUS = 0x300
ADDR_MIE     = 0x304
ADDR_MTVEC   = 0x305
ADDR_MEPC    = 0x341
ADDR_MCAUSE  = 0x342
ADDR_MIP     = 0x344

OP_CSRRW = 1 # "01"
OP_CSRRS = 2 # "10"
OP_CSRRC = 3 # "11"

# =====================================================================================================================
# FUNÇÕES AUXILIARES
# =====================================================================================================================

def init_signals(dut):
    """Inicializa todas as entradas para evitar propagação de 'U' no tempo zero."""
    dut.Reset_i.value       = 0
    dut.Csr_Addr_i.value    = 0
    dut.Csr_Write_i.value   = 0
    dut.Csr_Op_i.value      = 0
    dut.Csr_WData_i.value   = 0
    dut.Trap_Enter_i.value  = 0
    dut.Trap_Return_i.value = 0
    dut.Trap_PC_i.value     = 0
    dut.Trap_Cause_i.value  = 0
    dut.Irq_Ext_i.value     = 0
    dut.Irq_Timer_i.value   = 0
    dut.Irq_Soft_i.value    = 0

async def verify_csr_read(dut, addr, expected_val, case_desc):
    """Lê um CSR combinacionalmente e verifica o resultado."""
    dut.Csr_Addr_i.value = addr
    dut.Csr_Write_i.value = 0
    await settle()
    
    current_val = dut.Csr_RData_o.value.to_unsigned()
    expected_norm = expected_val & 0xFFFFFFFF
    
    if current_val != expected_norm:
        log_error(f"FALHA: {case_desc}")
        log_error(f"CSR Addr: {hex(addr)} | Esperado: {hex(expected_norm)} | Recebido: {hex(current_val)}")
        assert False, f"Falha no caso: {case_desc}"

async def write_csr(dut, addr, data, op=OP_CSRRW):
    """Realiza um ciclo de escrita em um CSR."""
    dut.Csr_Addr_i.value  = addr
    dut.Csr_WData_i.value = data
    dut.Csr_Op_i.value    = op
    dut.Csr_Write_i.value = 1
    await RisingEdge(dut.Clk_i)
    dut.Csr_Write_i.value = 0
    await settle()

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_csr_operations(dut):
    
    log_header("Testes Dirigidos - CSR File (Operações Atômicas & Hardware Traps)")
    
    # Inicia o Clock (100MHz)
    cocotb.start_soon(Clock(dut.Clk_i, 10, unit="ns").start())
    init_signals(dut)
    
    # -------------------------------------------------------------------------
    # 0. Reset
    # -------------------------------------------------------------------------
    dut.Reset_i.value = 1
    await RisingEdge(dut.Clk_i)
    await RisingEdge(dut.Clk_i)
    dut.Reset_i.value = 0
    await settle()
    
    # -------------------------------------------------------------------------
    # Teste 1: Escrita Simples (CSRRW) e Hardwired Bits
    # -------------------------------------------------------------------------
    # MTVEC deve forçar os 2 bits menos significativos para "00" (Direct Mode)
    await write_csr(dut, ADDR_MTVEC, 0x80000007, OP_CSRRW) # Bits 1:0 = 11
    
    # Esperado: 0x80000004 (Os bits 1:0 devem ser limpos pelo VHDL)
    await verify_csr_read(dut, ADDR_MTVEC, 0x80000004, "CSRRW no MTVEC (Com Hardwired 00)")
    
    # Verifica porta paralela
    assert dut.Mtvec_o.value.to_unsigned() == 0x80000004, "Saída paralela Mtvec_o falhou."
    log_success("Teste 1: Escrita CSRRW & Máscara Hardwired [OK]")

    # -------------------------------------------------------------------------
    # Teste 2: Lógica CSRRS (Read/Set)
    # -------------------------------------------------------------------------
    # Escreve 0x00000011 no MEPC
    await write_csr(dut, ADDR_MEPC, 0x00000011, OP_CSRRW)
    
    # Set bit 1 (0x00000002) usando CSRRS
    await write_csr(dut, ADDR_MEPC, 0x00000002, OP_CSRRS)
    
    # Esperado: 0x11 OR 0x02 = 0x13
    await verify_csr_read(dut, ADDR_MEPC, 0x00000013, "CSRRS no MEPC")
    log_success("Teste 2: Lógica CSRRS (Set Bits) [OK]")

    # -------------------------------------------------------------------------
    # Teste 3: Lógica CSRRC (Read/Clear)
    # -------------------------------------------------------------------------
    # Limpa bit 0 e bit 4 (0x00000011) usando CSRRC no valor 0x13
    await write_csr(dut, ADDR_MEPC, 0x00000011, OP_CSRRC)
    
    # Esperado: 0x13 AND NOT(0x11) = 0x02
    await verify_csr_read(dut, ADDR_MEPC, 0x00000002, "CSRRC no MEPC")
    log_success("Teste 3: Lógica CSRRC (Clear Bits) [OK]")

    # -------------------------------------------------------------------------
    # Teste 4: Hardware Trap Entry (Entrada na Exceção)
    # -------------------------------------------------------------------------
    # Setup inicial: Liga MIE (Bit 3 do MSTATUS)
    await write_csr(dut, ADDR_MSTATUS, 0x00000008, OP_CSRRW)
    
    # Dispara o Trap por hardware
    dut.Trap_Enter_i.value = 1
    dut.Trap_PC_i.value    = 0x40001004
    dut.Trap_Cause_i.value = 0x0000000B # Exemplo: Environment Call
    
    await RisingEdge(dut.Clk_i)
    dut.Trap_Enter_i.value = 0
    await settle()
    
    # Verificações pós-trap:
    await verify_csr_read(dut, ADDR_MEPC, 0x40001004, "MEPC após Trap Entry")
    await verify_csr_read(dut, ADDR_MCAUSE, 0x0000000B, "MCAUSE após Trap Entry")
    
    # -> CORREÇÃO AQUI: Força o endereço de volta para MSTATUS antes de ler <-
    dut.Csr_Addr_i.value = ADDR_MSTATUS
    await settle()
    
    mstatus_val = dut.Csr_RData_o.value.to_unsigned()
    assert (mstatus_val & 0x8) == 0, "MIE não foi limpo após o Trap"
    assert (mstatus_val & 0x80) != 0, "MPIE não guardou o valor antigo do MIE"
    assert dut.Global_Irq_En_o.value == 0, "Saída paralela Global_Irq_En_o não desligou."
    
    log_success("Teste 4: Hardware Trap Entry (Salva contexto) [OK]")

    # -------------------------------------------------------------------------
    # Teste 5: Hardware Trap Return (MRET)
    # -------------------------------------------------------------------------
    dut.Trap_Return_i.value = 1
    await RisingEdge(dut.Clk_i)
    dut.Trap_Return_i.value = 0
    await settle()
    
    # -> CORREÇÃO AQUI: Por segurança, garanta o endereço no MSTATUS <-
    dut.Csr_Addr_i.value = ADDR_MSTATUS
    await settle()
    
    # MSTATUS: MIE (bit 3) deve receber MPIE (1). MPIE deve virar 1.
    mstatus_val = dut.Csr_RData_o.value.to_unsigned()
    assert (mstatus_val & 0x8) != 0, "MIE não foi restaurado após MRET"
    assert (mstatus_val & 0x80) != 0, "MPIE não foi setado para 1 após MRET"
    assert dut.Global_Irq_En_o.value == 1, "Saída paralela Global_Irq_En_o não ligou."
    
    log_success("Teste 5: Hardware Trap Return (Restaura contexto) [OK]")

    # -------------------------------------------------------------------------
    # Teste 6: Construção do MIP (Machine Interrupt Pending) Assíncrono
    # -------------------------------------------------------------------------
    # Levanta a interrupção de Timer (Bit 7) e Externa (Bit 11)
    dut.Irq_Timer_i.value = 1
    dut.Irq_Ext_i.value   = 1
    await settle()
    
    # MIP (0x344) deve refletir imediatamente: Bit 7 e Bit 11 = 0x880
    await verify_csr_read(dut, ADDR_MIP, 0x00000880, "Leitura Combinacional do MIP")
    
    # Verifica a porta de saída paralela
    assert dut.Mip_o.value.to_unsigned() == 0x880, "Saída paralela Mip_o falhou."
    
    dut.Irq_Timer_i.value = 0
    dut.Irq_Ext_i.value   = 0
    log_success("Teste 6: Mapeamento Assíncrono do MIP [OK]")

    # -------------------------------------------------------------------------
    # Teste 7: Endereço Inválido
    # -------------------------------------------------------------------------
    dut.Csr_Addr_i.value = 0xFFF # Endereço não mapeado
    await settle()
    
    assert dut.Csr_Valid_o.value == 0, "Csr_Valid_o deveria ser 0 para endereço inválido."
    log_success("Teste 7: Detecção de Endereço Inválido [OK]")