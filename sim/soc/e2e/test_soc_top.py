# ==============================================================================
# File: sim/soc/test_soc_top.py
# ==============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import sim.core.single_cycle.include.test_utils as tu

# ==============================================================================
# CONSTANTES DE MEMÓRIA E MMIO
# ==============================================================================

ROM_BASE      = 0x00000000
ROM_LIMIT     = 0x00001000  # Tamanho estimado da ROM
RAM_BASE      = 0x80000000
MMIO_OUT_ADDR = 0x10000004  # Endereço virtual usado pelo C para output (Snoop)

@cocotb.test()
async def test_execution_monitor(dut):
    """
    Monitora a execução do SoC com logs detalhados:
    1. Acompanha o Bootloader (ROM -> RAM).
    2. Detecta a transição de execução.
    3. Valida a saída do Fibonacci via snoop do barramento.
    """
    
    tu.log_header("INICIANDO SIMULAÇÃO COMPLETA DO SOC RISC-V")
    tu.log_info("Arquitetura: Harvard Modificada (CPU + DMA) | SW: Bootloader + Fibonacci")

    # --------------------------------------------------------------------------
    # 1. INICIALIZAÇÃO (Clock & Reset)
    # --------------------------------------------------------------------------
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())
    
    tu.log_info("Resetando o processador...")
    dut.Reset_i.value = 1
    dut.UART_RX_i.value = 1 # Idle state da UART
    
    for _ in range(10): await RisingEdge(dut.CLK_i)
    
    dut.Reset_i.value = 0
    tu.log_info("Reset liberado. Iniciando monitoramento de execução...")
    tu.log_header("RASTREAMENTO DE INSTRUÇÕES E DADOS")

    # --------------------------------------------------------------------------
    # 2. CONFIGURAÇÃO DO TESTE
    # --------------------------------------------------------------------------
    # Aumentado para 50k ciclos para garantir boot + execução completa
    CYCLES_MAX = 50000  
    
    # Lista gabarito de Fibonacci
    expected_fib = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597]
    fib_idx = 0
    
    # Variáveis de estado
    last_pc = -1
    last_we = 0
    boot_completed = False

    # --------------------------------------------------------------------------
    # 3. LOOP DE SIMULAÇÃO
    # --------------------------------------------------------------------------
    for cycle in range(CYCLES_MAX):
        await RisingEdge(dut.CLK_i)
        
        # --- Leitura Segura dos Sinais Internos (Atualizados para soc_top.vhd) ---
        try:
            # Sinais de Busca (Instruction Fetch) - Nomes atualizados (_cpu_)
            pc    = int(dut.s_cpu_imem_addr.value)
            instr = int(dut.s_cpu_imem_data.value)
            
            # Sinais de Dados (Data Memory Access) - Nomes atualizados (_cpu_)
            dmem_we   = int(dut.s_cpu_dmem_we.value)
            dmem_addr = int(dut.s_cpu_dmem_addr.value)
            dmem_data = int(dut.s_cpu_dmem_wdata.value)
            
        except ValueError:
            # Captura 'X', 'Z' ou 'U' no início da simulação
            pc, instr, dmem_we, dmem_addr, dmem_data = 0, 0, 0, 0, 0
        except AttributeError:
             # Caso grave onde o sinal não foi encontrado
             tu.log_error("Erro de acesso aos sinais internos. Verifique os nomes no test_soc_top.py")
             raise

        # --- A. DETECÇÃO DE INSTRUÇÃO (Execução) ---
        # Só imprimimos quando o PC muda
        if pc != last_pc:
            
            # Determina a região de memória para colorir/identificar o log
            if pc < ROM_LIMIT:
                region = "ROM (Boot)"
                color  = tu.Colors.WARNING # Amarelo para ROM
            elif pc >= RAM_BASE:
                region = "RAM (App) "
                color  = tu.Colors.HEADER  # Ciano para RAM
            else:
                region = "UNKNOWN   "
                color  = tu.Colors.FAIL

            # Detecta o momento exato do salto ROM -> RAM
            if last_pc < RAM_BASE and pc >= RAM_BASE:
                tu.log_header(f"🚀 SALTO PARA RAM DETECTADO NO CICLO {cycle}!")
                boot_completed = True

            # Imprime a linha de rastro da instrução
            log_msg = f"[{region}] Cycle {cycle:5d} | PC: 0x{pc:08X} | Instr: 0x{instr:08X}"
            
            # Usa o logger do cocotb diretamente para aplicar a cor
            cocotb.log.info(f"{color}{log_msg}{tu.Colors.ENDC}")

            last_pc = pc

        # --- B. DETECÇÃO DE SAÍDA (Snoop do Barramento) ---
        # Verifica se houve escrita no endereço especial 0x10000004
        if dmem_we != 0 and last_we == 0 and dmem_addr == MMIO_OUT_ADDR:
            
            tu.log_int(f"Valor escrito no barramento: {dmem_data}")
            
            # Validação
            if fib_idx < len(expected_fib):
                expected = expected_fib[fib_idx]
                
                if dmem_data == expected:
                    tu.log_success(f"Fibonacci({fib_idx}) validado: {dmem_data}")
                else:
                    tu.log_error(f"Fibonacci({fib_idx}) INCORRETO! Esperado: {expected}, Recebido: {dmem_data}")
                
                fib_idx += 1
            else:
                tu.log_info(f"Termo extra gerado (além do teste): {dmem_data}")

        last_we = dmem_we

        # --- C. CONDIÇÃO DE TÉRMINO ---
        if fib_idx >= len(expected_fib):
            tu.log_header("TESTE CONCLUÍDO COM SUCESSO")
            tu.log_success("Todos os termos da sequência de Fibonacci foram validados!")
            break

    # --------------------------------------------------------------------------
    # 4. ASSERÇÕES FINAIS
    # --------------------------------------------------------------------------
    if not boot_completed:
        tu.log_error("O Bootloader não completou a transição para a RAM dentro do limite de ciclos.")
    
    assert boot_completed, "Falha no Boot."
    assert fib_idx >= len(expected_fib), f"Faltaram termos. Processou {fib_idx}/{len(expected_fib)}"