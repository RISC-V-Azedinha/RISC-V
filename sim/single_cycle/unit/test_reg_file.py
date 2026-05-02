# ============================================================================================================================================================
# File: test_reg_file.py
# ============================================================================================================================================================
#
# >>> Descrição: Testbench para o Banco de Registradores (Register File).
#     Verifica escrita síncrona, leitura assíncrona (combinacional) e a imutabilidade do registrador x0.
#     Inclui modelo de referência (Golden Model) com estado persistente.
#
# ============================================================================================================================================================

import cocotb                            # Biblioteca principal do cocotb
from cocotb.clock import Clock           # Utilitário para geração de clock
from cocotb.triggers import RisingEdge   # Triggers para eventos de simulação
import random                            # Para gerar valores aleatórios nos testes

# Importa utilitários compartilhados entre testbenches
from test_utils import log_header, log_info, log_success, log_error, settle

# =====================================================================================================================
# GOLDEN MODEL - Modelo de referência em Python
# =====================================================================================================================
#
# Def. Formal: 
#    Leitura(addr) == regs[addr] (Combinacional)
#    Próximo(regs[addr]) == data SE (we=1 E addr!=0) SENÃO regs[addr] (Sequencial)
#
# Trata-se da implementação de um modelo comportamental de referência, mantendo o estado 
# interno dos 32 registradores para validação sequencial.

class RegFileModel:
    def __init__(self):
        # 32 registradores de 32 bits, inicializados com 0
        self.regs = [0] * 32

    def read(self, addr):
        """
        Lê o valor do registrador (x0 é sempre 0).
        """
        if addr == 0:
            return 0
        return self.regs[addr]

    def write(self, addr, data, we):
        """
        Atualiza o estado interno se a escrita estiver habilitada e addr != 0.
        """
        if we and addr != 0:
            # Garante que armazenamos como unsigned 32-bit para consistência
            self.regs[addr] = data & 0xFFFFFFFF

# =====================================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================================

async def verify_read(dut, port_num, addr, expected_val, case_desc):
    """
    Verifica se a porta de leitura especificada (1 ou 2) está com o valor correto.
    Como a leitura é assíncrona/combinacional, não esperamos clock aqui.
    """

    # Seleciona os sinais baseados na porta
    if port_num == 1:
        dut.ReadAddr1_i.value = addr
        signal_out = dut.ReadData1_o
    else:
        dut.ReadAddr2_i.value = addr
        signal_out = dut.ReadData2_o
        
    # Aguarda propagação combinacional
    await settle()
    
    # Leitura do valor atual
    current_val = signal_out.value.to_unsigned()
    
    # Normaliza esperado para comparação (trata negativos se houver)
    expected_norm = expected_val & 0xFFFFFFFF
    
    # Comparação
    if current_val != expected_norm:
        log_error(f"FALHA: {case_desc}")
        log_error(f"Porta: {port_num}, Addr: x{addr}")
        log_error(f"Esperado: {hex(expected_norm)} ({expected_norm})")
        log_error(f"Recebido: {hex(current_val)} ({current_val})")
        assert False, f"Falha no caso: {case_desc}"

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def run_directed_tests(dut):
    
    # Reproduz os testes manuais dirigidos do reg_file_tb.vhd.
    
    log_header("Testes Dirigidos - Register File")
    
    # 1. Inicializa Clock (10ns period -> 100MHz)
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    
    # Reset inicial dos sinais
    dut.RegWrite_i.value  = 0
    dut.ReadAddr1_i.value = 0
    dut.ReadAddr2_i.value = 0
    dut.WriteAddr_i.value = 0
    dut.WriteData_i.value = 0
    
    # Espera alguns clocks para estabilizar
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)

    # -------------------------------------------------------------------------
    # Teste 1: Escrever 42 em x5
    # -------------------------------------------------------------------------
    
    dut.RegWrite_i.value  = 1
    dut.WriteAddr_i.value = 5
    dut.WriteData_i.value = 42
    
    # Aguarda a borda de subida onde a escrita acontece
    await RisingEdge(dut.clk_i)
    
    # Ciclo seguinte: Desabilita escrita e Verifica leitura
    dut.RegWrite_i.value = 0
    await verify_read(dut, 1, 5, 42, "Leitura de x5 apos escrita")
    log_success("Teste 1: Escrever 42 em x5 [OK]")

    # -------------------------------------------------------------------------
    # Teste 2: Tentar escrever 99 em x0 (Deve falhar/ser ignorado)
    # -------------------------------------------------------------------------
    
    dut.RegWrite_i.value  = 1
    dut.WriteAddr_i.value = 0
    dut.WriteData_i.value = 99
    
    # Aguarda a borda de subida onde a escrita acontece
    await RisingEdge(dut.clk_i)
    
    # Ciclo seguinte: Desabilita escrita e Verifica leitura
    dut.RegWrite_i.value = 0
    await verify_read(dut, 1, 0, 0, "Leitura de x0 (deve ser 0)")
    log_success("Teste 2: Tentar escrever 99 em x0 [OK]")

    # -------------------------------------------------------------------------
    # Teste 3: Leitura Simultânea (x5=42, escrever x10=-1)
    # -------------------------------------------------------------------------
    
    dut.RegWrite_i.value  = 1
    dut.WriteAddr_i.value = 10
    dut.WriteData_i.value = 0xFFFFFFFF # -1 em 32 bits
    
    # Aguarda a borda de subida onde a escrita acontece
    await RisingEdge(dut.clk_i)
    
    # Ciclo seguinte: Desabilita escrita
    dut.RegWrite_i.value = 0
    # Verifica porta 1 lendo x5 e porta 2 lendo x10 simultaneamente
    await verify_read(dut, 1, 5, 42, "Porta 1 lendo x5")
    await verify_read(dut, 2, 10, 0xFFFFFFFF, "Porta 2 lendo x10")
    log_success("Teste 3: Escrever -1 (0xFFFFFFFF) em x10 e ler x5 e x10 [OK]")

    # -------------------------------------------------------------------------
    # Teste 4: Read-Before-Write (Transparência/Timing)
    # -------------------------------------------------------------------------
    
    # Ciclo N: x7 tem 0. Vamos configurar para escrever 99.
    # Mas TAMBÉM vamos ler x7 combinacionalmente ANTES do clock.
    
    dut.RegWrite_i.value  = 1
    dut.WriteAddr_i.value = 7
    dut.WriteData_i.value = 99
    
    # Configura leitura para o MESMO endereço
    dut.ReadAddr1_i.value = 7
    
    await settle()
    # Verificação A: Antes do clock, a saída deve ser o valor ANTIGO (0)
    if dut.ReadData1_o.value.to_unsigned() != 0:
        log_error("ERRO [Teste 4a]: Leitura assincrona mudou antes do clock!")
        assert False
        
    # Aguarda a borda de subida onde a escrita acontece
    await RisingEdge(dut.clk_i)
    
    # Aguarda estabilização dos sinais
    await settle()
    
    # Verificação B: Imediatamente após o clock, a leitura deve refletir o novo valor
    if dut.ReadData1_o.value.to_unsigned() != 99:
        log_error("ERRO [Teste 4b]: Leitura assincrona nao atualizou apos clock!")
        log_error(f"Got: {dut.ReadData1_o.value.to_unsigned()}")
        assert False

    log_success("Teste 4: Read-Before-Write em x7 [OK]")

    # -------------------------------------------------------------------------
    # Teste 5: Write Enable '0'
    # -------------------------------------------------------------------------
    
    dut.RegWrite_i.value  = 0
    dut.WriteAddr_i.value = 8
    dut.WriteData_i.value = 123
    
    await RisingEdge(dut.clk_i)
    
    await verify_read(dut, 1, 8, 0, "x8 deve manter 0")
    log_success("Teste 5: Tentar escrever 123 em x8 com WE=0 [OK]")

    # -------------------------------------------------------------------------
    # Teste 6: Leitura Assíncrona (Mudança de endereço)
    # -------------------------------------------------------------------------
    
    # x5=42, x10=-1. Clock parado (ou irrelevante entre bordas)
    await verify_read(dut, 1, 5, 42, "Leitura Async x5")
    await verify_read(dut, 1, 10, 0xFFFFFFFF, "Leitura Async x10")
    log_success("Teste 6: Leitura Assincrona sem clock [OK]")

@cocotb.test()
async def stress_test_randomized(dut):

    # Stress Test: Realiza 2000 operações aleatórias mantendo um Shadow Model.
    
    # Número de iterações aleatórias
    NUM_ITERATIONS = 2000
    
    # Escreve cabeçalho do teste
    log_header(f"Stress Test Randomized ({NUM_ITERATIONS} ciclos)")
    
    # Inicia o clock da simulação com período de 10 ns
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    # Instancia o modelo de referência
    model = RegFileModel()
    
    # Inicialização / Limpeza dos registradores
    log_info("Inicializando/Limpando registradores...")
    for i in range(1, 32):
        dut.RegWrite_i.value  = 1
        dut.WriteAddr_i.value = i
        dut.WriteData_i.value = 0
        model.write(i, 0, 1)
        await RisingEdge(dut.clk_i)
        
    log_info("Estado limpo. Iniciando Loops Aleatorios...")

    for i in range(NUM_ITERATIONS):
        # 1. Gera estímulos aleatórios para o Ciclo N
        # Escrita
        we_rand = random.choice([0, 1, 1]) # 66% chance de escrita
        w_addr  = random.randint(0, 31)
        w_data  = random.randint(0, 0xFFFFFFFF)
        
        # Leitura (Endereços aleatórios para as duas portas)
        r_addr1 = random.randint(0, 31)
        r_addr2 = random.randint(0, 31)
        
        # 2. Aplica ao DUT
        dut.RegWrite_i.value  = we_rand
        dut.WriteAddr_i.value = w_addr
        dut.WriteData_i.value = w_data
        
        dut.ReadAddr1_i.value = r_addr1
        dut.ReadAddr2_i.value = r_addr2
        
        # 3. Validação Pré-Clock (Leitura Assíncrona do estado ATUAL)
        await settle()
        
        exp_d1 = model.read(r_addr1)
        exp_d2 = model.read(r_addr2)
        
        if dut.ReadData1_o.value.to_unsigned() != exp_d1:
            log_error(f"Iter {i}: Erro Leitura Porta 1 (Pre-Clock)")
            log_error(f"Addr: x{r_addr1} | Exp: {hex(exp_d1)} | Got: {hex(dut.ReadData1_o.value.to_unsigned())}")
            assert False
            
        if dut.ReadData2_o.value.to_unsigned() != exp_d2:
            log_error(f"Iter {i}: Erro Leitura Porta 2 (Pre-Clock)")
            log_error(f"Addr: x{r_addr2} | Exp: {hex(exp_d2)} | Got: {hex(dut.ReadData2_o.value.to_unsigned())}")
            assert False
            
        # 4. Avança Clock (Escrita acontece aqui)
        await RisingEdge(dut.clk_i)
        
        # 5. Atualiza o estado do modelo PÓS-CLOCK
        model.write(w_addr, w_data, we_rand)

     # Escreve mensagem de sucesso do teste
    log_success(f"{NUM_ITERATIONS} Vetores Aleatórios Verificados com Sucesso")