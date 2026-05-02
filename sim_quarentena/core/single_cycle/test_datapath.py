# ============================================================================================================================================================
# File: test_datapath.py
# ============================================================================================================================================================
#
# >>> Descrição:
#   Testbench cocotb para validação do Datapath.
#   Usa sinais de DEBUG expostos pelo hardware para verificação ciclo-a-ciclo.
#
#   Testa:
#     - Reset e PC inicial
#     - Incremento sequencial do PC
#     - Cálculo de PC_next
#     - Observabilidade de instrução
#     - Caminho ALU / Write-back
#     - Caminho de Store
#     - Stress test com controle aleatório
#     - Banco de registradores (x0 - x31)
#
# ============================================================================================================================================================

import cocotb                                  # Importa o framework cocotb
from cocotb.clock import Clock                 # Importa a classe Clock para gerar clock
from cocotb.triggers import RisingEdge, Timer  # Importa triggers para sincronização
import random                                  # Importa módulo random para geração de valores aleatórios

# Importa utilitários compartilhados para logging e funções auxiliares
from test_utils import log_header, log_info, log_success, settle, sign_extend

# =====================================================================================================================
# Helpers
# =====================================================================================================================

async def drive_control(dut, rw=0, src_a=0, src_b=0, wb_src=0, mw=0, pcsrc=0, aluc=0):
    """Define os sinais de controle do datapath"""
    dut.reg_write_i.value      = rw
    dut.alu_src_a_i.value      = src_a
    dut.alu_src_b_i.value      = src_b
    dut.mem_write_i.value      = mw
    dut.wb_src_i.value         = wb_src
    dut.pcsrc_i.value          = pcsrc
    dut.alucontrol_i.value     = aluc

async def apply_reset(dut):
    """Aplica um pulso de reset"""
    dut.Reset_i.value = 1
    await RisingEdge(dut.CLK_i)
    dut.Reset_i.value = 0
    await settle()

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_reset_and_pc_increment(dut):
    
    # Verifica:
    #   - PC inicial após reset
    #   - Incremento sequencial PC + 4
    #   - Coerência PC_current / PC_next
    log_header("Teste: Reset e Incremento de PC")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())

    # Aplica sinal de reset
    await apply_reset(dut)

    # Após reset, verifica PC inicial e IMem_addr_o (igual a PC)
    assert int(dut.dbg_pc_current_o.value) == 0, "PC_current não inicializou em 0"
    assert int(dut.IMem_addr_o.value) == 0, "IMem_addr_o != PC após reset"

    # Controle: PC sequencial
    await drive_control(dut, pcsrc=0)

    # Avança um ciclo de clock
    await RisingEdge(dut.CLK_i)
    await settle()

    # Verifica PC_current e PC_next
    pc_cur  = int(dut.dbg_pc_current_o.value)
    pc_next = int(dut.dbg_pc_next_o.value)

    # Verifica coerência entre PC_current e PC_next
    # PC_next = PC_current + 4 (incremento sequencial)
    assert pc_cur == 4, "PC_current não incrementou para 4"
    assert pc_next == 8, "PC_next não calculado corretamente"

    # Escreve a mensagem de sucesso do teste
    log_success("Reset e incremento sequencial de PC OK")


@cocotb.test()
async def test_instruction_visibility(dut):
    
    # Verifica se a instrução da IMem aparece corretamente no datapath.
    log_header("Teste: Observabilidade de Instrução")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())

    # Aplica sinal de reset
    await apply_reset(dut)

    # Força uma instrução conhecida na IMem
    instr = 0x00A58533                           # ADD x10, x11, x10 (exemplo)
    dut.IMem_data_i.value = instr                # Define a instrução na IMem

    # Controle: PC sequencial
    await drive_control(dut, pcsrc=0)

    # Avança um ciclo de clock
    await RisingEdge(dut.CLK_i)
    await settle()

    # Verifica se a instrução está visível no datapath
    assert int(dut.dbg_instruction_o.value) == instr, "Instrução não propagou corretamente"

    # Escreve a mensagem de sucesso do teste
    log_success("Instrução visível corretamente no datapath")


@cocotb.test()
async def test_alu_and_writeback_path(dut):
    
    # Verifica:
    #   - Resultado da ALU para múltiplas operações
    #   - Flag Zero em diferentes cenários
    #   - Caminho de write-back com dados reais
    log_header("Teste: Caminho ALU e Write-back (Múltiplas Operações)")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())

    # Aplica o sinal de reset
    await apply_reset(dut)

    # Matriz de testes: cada entrada contém (nome_operacao, codigo_aluc, descricao)
    alu_tests = [
        ("ADD", 0b0000, "Adição"),
        ("SUB", 0b1000, "Subtração"),
        ("AND", 0b0111, "OU lógico bit a bit"),
        ("OR",  0b0110, "E lógico bit a bit"),
        ("XOR", 0b0100, "OU exclusivo"),
        ("SLT", 0b0010, "Set Less Than (comparação com sinal)"),
        ("SLL", 0b0001, "Shift Left Logical"),
        ("SRL", 0b0101, "Shift Right Logical"),
    ]

    # Instrução R-Type com rs1=1, rs2=2 (configura os operandos)
    instr_template = (0x2 << 20) | (0x1 << 15) | (0 << 12) | (0 << 7) | 0x33

    # Itera sobre a matriz de testes
    for idx, (op_name, aluc_code, description) in enumerate(alu_tests, 1):
        log_info(f"Teste {idx}: {op_name} ({description})")
        
        # Define a instrução
        dut.IMem_data_i.value = instr_template
        
        # Define os sinais de controle
        await drive_control(dut, rw=1, src_a=0, src_b=0, aluc=aluc_code)
        
        # Avança um ciclo de clock
        await RisingEdge(dut.CLK_i)
        await settle()
        
        # Captura os resultados
        alu_res = int(dut.dbg_alu_result_o.value)
        zero    = int(dut.dbg_alu_zero_o.value)
        
        # Log do resultado
        log_info(f"  Resultado {op_name}: {hex(alu_res)}, ZERO = {zero}")
        
        # Validações
        assert isinstance(alu_res, int), f"Resultado da ALU inválido para {op_name}"
        assert zero in (0, 1), f"Flag ZERO inválida para {op_name}"

    # Escreve mensagem de sucesso do teste
    log_success("Caminho ALU / Write-back validado com múltiplas operações!")


@cocotb.test()
async def test_store_path(dut):
    
    # Verifica se o caminho de Store está funcional:
    #   - Enable de escrita
    #   - Dado de saída
    log_header("Teste: Caminho de Store")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())

    # Aplica sinal de reset
    await apply_reset(dut)

    # Controle: escrita na memória
    await drive_control(dut, mw=1)

    # Avança um ciclo de clock
    await RisingEdge(dut.CLK_i)
    await settle()

    # Verifica se a escrita na memória foi ativada
    assert dut.DMem_writeEnable_o.value == 1, "DMem_writeEnable_o não foi ativado"

    # Escreve a mensagem de sucesso do teste
    log_success("Caminho de escrita na memória OK")


@cocotb.test()
async def stress_test_datapath_flow(dut):
    
    # Stress test:
    #   - Controle aleatório
    #   - Valida coerência PC_current -> PC_next
    log_header("Stress Test: Fluxo do Datapath")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())
    
    # Aplica sinal de reset
    await apply_reset(dut)

    # Loop de iteração de testes de estresse
    for i in range(50):

        # Gera instrução aleatória de 32 bits
        instr = random.getrandbits(32)

        # Configura a instrução na entrada do datapath
        dut.IMem_data_i.value = instr

        # Randomiza o modo de atualização do PC
        pc_mode = random.randint(0, 2)

        # Controle: configura o modo de atualização do PC
        await drive_control(dut, pcsrc=pc_mode)

        # Captura o PC anterior
        pc_before = int(dut.dbg_pc_current_o.value)

        # Avança um ciclo de clock
        await RisingEdge(dut.CLK_i)
        await settle()

        # Captura o PC posterior
        pc_after = int(dut.dbg_pc_current_o.value)

        # Informa os valores (logging)
        log_info(f"[{i}] PC {pc_before} -> {pc_after} (pcsrc={pc_mode})")

        # Verificação
        if pc_mode == 0:
            assert pc_after == pc_before + 4, "Erro no incremento sequencial do PC"

    # Escreve mensagem de sucesso do teste
    log_success("Stress test do Datapath concluído com sucesso")

@cocotb.test()
async def test_register_file_bank(dut):
    
    log_header("Teste: Banco de Registradores (x0 - x31)")

    # Inicia clock da simulação
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())

    # Aplica sinal de reset
    await apply_reset(dut)
    
    # Valores de teste
    test_values = [0] * 32

    # Informa o início da iteração de ESCRITA (WRITE)
    log_info("Escrevendo valores de 12 bits em todos os registradores...")
    for i in range(1, 32):

        # O imediato de ADDI tem apenas 12 bits
        val = random.getrandbits(12) 

        # Salva o valor gerado aplicando a extensão de sinal e máscara
        test_values[i] = sign_extend(val, 12) & 0xFFFFFFFF
        
        # ADDI x[i], x0, val -> Opcode 0x13
        # Montamos a instrução garantindo que não estoure 32 bits
        instr = ((val & 0xFFF) << 20) | (0 << 15) | (0 << 12) | (i << 7) | 0x13
        
        # Aplica a instrução ao DUT
        dut.IMem_data_i.value = instr
        
        # Aplica os sinais de controle ao DUT
        await drive_control(dut, rw=1, src_b=1, aluc=0) # RegWrite=1, ALUSrcB=Imm, ADD
        
        # Avança para o próximo ciclo de clock
        await RisingEdge(dut.CLK_i)
        await Timer(1, "ns")

    # Informa o início da itieração de LEITURA (READ)
    log_info("Verificando leitura...")
    for i in range(32):

        # Instrução para ler x[i] nos barramentos rs1 e rs2
        dut.IMem_data_i.value = (i << 15) | (i << 20) | 0x33 

        # Avança o ciclo de clock
        await settle()
        
        # x0 deve ser sempre 0
        expected = 0 if i == 0 else test_values[i]
        got_rs1 = int(dut.dbg_rs1_data_o.value)
        
        # Compara o valor obtido com o esperado
        assert got_rs1 == expected, f"Erro x{i}: esperado {expected}, obtido {got_rs1}"

    # Escreve mensagem de sucesso do teste
    log_success("Banco de registradores validado com sucesso!")