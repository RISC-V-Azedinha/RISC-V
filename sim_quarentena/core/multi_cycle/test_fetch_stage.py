# ================================================================================================================
# File: test_fetch_stage.py
# ================================================================================================================
#
# >>> Descrição: Conjunto de testes focado exclusivamente no Estágio de Busca (Instruction Fetch).
#       Verifica reset, stall, carga de instruções e robustez (stress test).
#
# ================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# Importa utilitários personalizados
from test_utils import log_header, log_info, log_success, log_error, settle, Colors

# =================================================================================================
# Finite State Machine (IF)
# =================================================================================================

# Simula os estados necessários para recuperação de dados em memória síncrona (como BRAM)
# - A função de transição (f) define, a partir do estado atual e da entrada, o próximo estado
# - Enquanto, a função de saída (g) define os sinais de saída gerados naquele estado
#
# OBS.: é adotado o modelo de Moore, ou seja, sinais são gerados de forma estável em um estado.

f_transicao = {
    'IF_ADDR': {'always': 'IF_DATA'},  # Ciclo 1: Endereçamento
    'IF_DATA': {'always': 'IF_ADDR'}   # Ciclo 2: Leitura de Dados            
}

# Define os sinais de controle (Moore) para cada estado

g_saidas = {
    # Estado ADDR: Apenas coloca endereço no barramento. Não escreve em registradores.
    'IF_ADDR': {'pcw': 0, 'irw': 0, 'opcw': 0, 'pcsrc': 0},  

    # Estado DATA: Dado da memória chegou. Escreve no IR, Salva OldPC e Incrementa PC.
    'IF_DATA': {'pcw': 1, 'irw': 1, 'opcw': 1, 'pcsrc': 0}
}

# A lógica para percorrer a FSM será encapsulada em FSMRunner, para limpar os testes

class FSMRunner:
    def __init__(self, estado_inicial, f_transicao, g_saidas):
        """Define o estado iinicial e as funções de transição e saída"""
        self.estado = estado_inicial
        self.f_transicao = f_transicao
        self.g_saidas = g_saidas

    def sinais(self):
        """Saídas do estado atual (Moore)"""
        return self.g_saidas[self.estado]

    def proximo_estado(self, entradas):
        """A partir das entradas, leva a FSM ao próximo estado"""
        transicoes = self.f_transicao[self.estado]

        for cond, prox in transicoes.items():
            if cond == 'always':
                return prox
            if cond in entradas and entradas[cond]:
                return prox

        raise RuntimeError(f"Sem transição válida para {self.estado}")

    async def tick(self, dut, entradas=None):
        """
        Executa exatamente UM ciclo de FSM:
        - aplica sinais do estado atual
        - espera borda de clock
        - atualiza estado
        """
        if entradas is None:
            entradas = {}

        # 1. Aplica sinais do estado atual
        await drive_control(dut, **self.sinais())

        # 2. Clock
        await RisingEdge(dut.CLK_i)
        await settle()

        # 3. Avança estado
        self.estado = self.proximo_estado(entradas)

# =================================================================================================
# Helpers de Monitoramento e Setup
# =================================================================================================

class IFMonitor: 

    @staticmethod
    def decodificar_sinais_controle(dut):
        """Traduz os sinais de controle brutos para texto descritivo"""
        pc_w  = int(dut.pcwrite_i.value)
        ir_w  = int(dut.irwrite_i.value)
        opc_w = int(dut.opcwrite_i.value)
        
        acoes = []
        if pc_w:  acoes.append("ATUALIZA_PC")
        if ir_w:  acoes.append("CARREGA_IR")
        if opc_w: acoes.append("SALVA_OLD_PC")
        
        if not acoes:
            return "CONGELADO (Stall)"
        return " + ".join(acoes)

    @staticmethod
    def log_status_ciclo(dut, nome_passo):
        """Imprime uma tabela formatada do estado atual do datapath"""
        
        # 1. Captura dados de estado do datapath 
        r_pc     = int(dut.DBG_r_pc_o.value)      # PC Atual
        r_oldpc  = int(dut.DBG_r_opc_o.value)     # Old PC
        r_ir     = int(dut.DBG_r_ir_o.value)      # Instruction Register
        pc_next  = int(dut.DBG_pc_next_o.value)   # Lógica Combinacional do Próximo PC
        
        # 2. Captura os dados da interface de memória (IMem)
        mem_addr = int(dut.IMem_addr_o.value)
        mem_data = int(dut.IMem_data_i.value)

        # 3. Captura sinais de controle no instante (snapshot) 
        c_pcw   = int(dut.pcwrite_i.value)
        c_irw   = int(dut.irwrite_i.value)
        c_opcw  = int(dut.opcwrite_i.value)
        c_pcsrc = int(dut.pcsrc_i.value)

        # Informa os sinais e a execução no momento
        raw_ctrl_str = f"PCWrite:{c_pcw} | IRWrite:{c_irw} | OPCWrite:{c_opcw} | PCSrc:{c_pcsrc:02b}"
        micro_ops = IFMonitor.decodificar_sinais_controle(dut)

        # Cores para o log do estado de IF do datapath
        C_LBL = Colors.HEADER
        C_VAL = Colors.SUCCESS
        C_WRN = Colors.WARNING
        C_INF = Colors.INFO
        C_RST = Colors.ENDC

        # Tabela que reune todas as informações anteriores para o usuário
        cocotb.log.info(f"\n{Colors.INFO}{'='*80}{C_RST}")
        cocotb.log.info(f" ⏱️  PASSO: {Colors.BOLD}{nome_passo}{C_RST}")
        cocotb.log.info(f" 🎮 CTRL : {C_WRN}[ {micro_ops} ]{C_RST}")
        cocotb.log.info(f" 🎛️  RAW  : {C_INF}{raw_ctrl_str}{C_RST}")
        cocotb.log.info(f"{Colors.INFO}{'-'*80}{C_RST}")
        cocotb.log.info(f"  {C_LBL}REGISTRADORES{C_RST} | PC      : {C_VAL}0x{r_pc:08X}{C_RST}  (Próx: {C_WRN}0x{pc_next:08X}{C_RST})")
        cocotb.log.info(f"                | OldPC   : {C_VAL}0x{r_oldpc:08X}{C_RST}")
        cocotb.log.info(f"                | IR      : {C_VAL}0x{r_ir:08X}{C_RST}")
        cocotb.log.info(f"  {C_LBL}MEMORIA BUS  {C_RST} | Endereço: {C_WRN}0x{mem_addr:08X}{C_RST}  ->  DadoLido: {C_VAL}0x{mem_data:08X}{C_RST}")
        cocotb.log.info(f"{Colors.INFO}{'='*80}{C_RST}\n")

# =================================================================================================
# Drivers e Modelos
# =================================================================================================

async def drive_control(dut, pcw=0, irw=0, opcw=0, pcsrc=0):
    """Função auxiliar que configura os sinais de controle do Fetch e zera os demais."""

    # Variáveis de interesse para o teste
    dut.pcwrite_i.value    = pcw
    dut.irwrite_i.value    = irw
    dut.opcwrite_i.value   = opcw
    dut.pcsrc_i.value      = pcsrc
    
    # Zera sinais irrelevantes (não são de interesse para o teste)
    dut.reg_write_i.value  = 0
    dut.alu_src_a_i.value  = 0
    dut.alu_src_b_i.value  = 0
    dut.mem_write_i.value  = 0
    dut.wb_src_i.value     = 0
    dut.alucontrol_i.value = 0
    dut.rs1write_i.value   = 0
    dut.rs2write_i.value   = 0
    dut.aluwrite_i.value   = 0
    dut.mdrwrite_i.value   = 0

class ModeloMemoria:
    def __init__(self, dut):
        """Inicializa a memória vazia para o DUT"""
        self.dut = dut
        self.mem = {}

    def carregar_programa(self, program_dict):
        """Carrega dados de programa (instruções) na memória para o DUT"""
        self.mem.update(program_dict)
        log_info(f"Modelo de Memória: Carregado com {len(program_dict)} instruções.")

    def ler(self, addr):
        """Simula a leitura do dado da memória (instrução)"""
        val = int(addr) & 0xFFFFFFFC 
        return self.mem.get(val, 0)

    async def rodar_loop_imem(self):
        """
        [MODO BRAM SÍNCRONA]
        Simula uma Block RAM de FPGA:
        1. Espera a borda de subida do clock
        2. Amostra o endereço presente no barramento
        3. Espera o tempo de acesso
        4. Coloca o dado no barramento
        """
        
        # Loop Síncrono
        while True:

            # 1. A BRAM só reage ao Clock, não à mudança combinacional do endereço
            await RisingEdge(self.dut.CLK_i)
            
            # 2. Amostragem do endereço
            # Na borda do clock, a memória registra o endereço
            # A BRAM registrou o valor antigo para endereçamento
            addr_amostrado = self.dut.IMem_addr_o.value
            
            # 3. Latência (Clock-to-Output) de um ciclo de clock
            await settle()
            
            # 4, Atualização da Saída
            data = self.ler(addr_amostrado)
            self.dut.IMem_data_i.value = data

async def setup_test(dut, instructions=None):
    """Configuração padrão para cada teste"""

    # Reinicia o clock
    cocotb.start_soon(Clock(dut.CLK_i, 10, unit="ns").start())
    
    # Carrega a memória e inicializa processo
    mem_model = ModeloMemoria(dut)
    cocotb.start_soon(mem_model.rodar_loop_imem())
    if instructions:
        mem_model.carregar_programa(instructions)
    
    # Reseta sinais de controle do DUT
    await drive_control(dut)

    # Aplica sinal de reset ao DUT
    dut.Reset_i.value = 1

    # Aguarda para liberar o sinal
    await settle()

    # Libera o datapath para execução
    dut.Reset_i.value = 0

    # Aguarda a estabilização dos sinais
    await settle()

# =================================================================================================
# BATERIA DE TESTES
# =================================================================================================

@cocotb.test()
async def test_reset_validation(dut):
    
    # [IF] Validação do Reset: PC deve iniciar em 0
    log_header("TESTE 01: Validação do Reset")

    # Configura os sinais de controle e inicializa a memória
    await setup_test(dut)
    
    # Exibe estado inicial do estágio de IF do datapath
    IFMonitor.log_status_ciclo(dut, "PÓS-RESET")
    
    # Verifica se as variáveis de interesse estão corretas
    assert dut.DBG_r_pc_o.value        == 0 , "Falha: PC não é 0 após reset"
    assert dut.IMem_addr_o.value       == 0 , "Falha: Endereço de Memória deve seguir o PC"
    assert dut.DBG_r_IR_o.value        == 0 , "Falha: IR não é 0 após reset"
    assert dut.DBG_r_opc_o.value       == 0 , "Falha: OldPC não é 0 após reset"
    assert dut.pcsrc_i.value           == 0 , "Falha: PCSrc não é 0 após reset"
    assert dut.DBG_instruction_o.value == 0 , "Falha: Instrução não é 0 após reset"

    # Escreve mensagem de sucesso do teste
    log_success("Reset OK: PC inicializado em 0x00000000.")


@cocotb.test()
async def test_stall_validation(dut):
    
    # [IF] Validação de Stall: PC e IR não devem mudar se Enables=0
    log_header("TESTE 02: Validação de Stall (Congelamento)")
    
    # Configura os sinais de controle e inicializa a memória
    # Também carrega dado no endereço 0x00000000
    prog = { 0x0: 0xDEADBEEF }
    await setup_test(dut, prog)
    
    # Configura os sinais de controle para zero (inicialmentes)
    log_info("Aplicando clock sem habilitar escrita (PCWrite=0, IRWrite=0 etc.)")
    await drive_control(dut)
    
    # Passa três ciclos de clock
    for i in range(3):
        await RisingEdge(dut.CLK_i)
    await settle()
    
    # Exibe estado do estágio de IF do datapath
    IFMonitor.log_status_ciclo(dut, "APÓS 3 CICLOS DE STALL")
    
    # Verifica se houve mudança no estado (mesmo com os sinais de escrita desabilitados)
    assert dut.DBG_r_pc_o.value        == 0 , "Falha: PC mudou durante Stall"
    assert dut.IMem_addr_o.value       == 0 , "Falha: Endereço de Memória mudou durante Stall"
    assert dut.DBG_r_IR_o.value        == 0 , "Falha: IR mudou durante Stall"
    assert dut.DBG_r_opc_o.value       == 0 , "Falha: OldPC mudou durante Stall"
    assert dut.pcsrc_i.value           == 0 , "Falha: PCSrc mudou durante Stall"
    assert dut.DBG_instruction_o.value == 0 , "Falha: Instrução mudou durante Stall"

    # Escreve mensagem de sucesso do teste
    log_success("Stall OK: Registradores mantiveram o estado.")

@cocotb.test()
async def test_full_fetch_cycle(dut):

    # [IF] Fetch Real: Atualiza PC, IR e OldPC 
    log_header("TESTE 03: Ciclo de Fetch (FSM) PC=0 -> PC=4")

    # Inicializa a memória com dados pré-definidos
    prog = { 0x00: 0xAAAA_1111, 0x04: 0xBBBB_2222 }
    await setup_test(dut, prog)

    # Inicializa a Máquina de Estados Finitos (FSM)
    fsm = FSMRunner(
        estado_inicial='IF_ADDR',
        f_transicao=f_transicao,
        g_saidas=g_saidas
    )

    # =====================================================================
    # Ciclo 1 — IF_ADDR
    # =====================================================================
    await fsm.tick(dut)

    # Exibe o estado do estágio IF
    IFMonitor.log_status_ciclo(dut, "APÓS IF_ADDR")

    # Nada deve ter mudado ainda
    assert int(dut.DBG_r_pc_o.value)  == 0
    assert int(dut.DBG_r_ir_o.value)  == 0
    assert int(dut.DBG_r_opc_o.value) == 0

    # =========================
    # Ciclo 2 — IF_DATA
    # =========================
    await fsm.tick(dut)

    # Exibe o estado do estágio IF
    IFMonitor.log_status_ciclo(dut, "APÓS IF_DATA")

    # Captura dos registradores
    ir_atual   = int(dut.DBG_r_ir_o.value)
    pc_atual   = int(dut.DBG_r_pc_o.value)
    opc_atual  = int(dut.DBG_r_opc_o.value)
    inst_atual = int(dut.DBG_instruction_o.value)

    # =====================================================================
    # Verificações
    # =====================================================================
    assert ir_atual   == 0xAAAA1111, f"IR incorreto: 0x{ir_atual:08X}"
    assert pc_atual   == 4,          f"PC incorreto: {pc_atual}"
    assert opc_atual  == 0,          f"OldPC incorreto: {opc_atual}"
    assert inst_atual == ir_atual,   "IR e Instruction divergem"

    # Escreve mensagem de sucesso do teste
    log_success("Fetch FSM OK: IR carregado e PC incrementado corretamente.")

@cocotb.test()
async def test_stress_fetch(dut):
    
    # [IF] Stress Test: Simula 20 ciclos de Fetch consecutivos
    log_header("TESTE 04: Stress Test (Fetch Contínuo)")
    
    # Gera dados aleatórios para a memória
    N_INSTRUCOES = 20
    prog_random = {}
    for i in range(N_INSTRUCOES):
        prog_random[i * 4] = random.randint(1, 0xFFFFFFFF)
    prog_random[N_INSTRUCOES * 4] = 0x00000013 # NOP Final

    # Inicializa a memória carregando dados aleatórios
    await setup_test(dut, prog_random)
    
    # Configura a Máquina de Estados Finitos (FSM)
    fsm = FSMRunner(
        estado_inicial='IF_ADDR',
        f_transicao=f_transicao,
        g_saidas=g_saidas
    )

    # Iteração para verificação do fetch de todas as instruções aleatórias
    log_info(f"Iniciando loop de {N_INSTRUCOES} instruções...")
    pc_esperado = 0

    for i in range(N_INSTRUCOES):

        # Estado IF_ADDR inicial do ciclo IF
        await fsm.tick(dut)

        # Estado IF_DATA do ciclo IF (carrega dados)
        await fsm.tick(dut)

        # Verifica a instrução esperada de acordo com o incremento do pc_esperado
        instr_esperada = prog_random[pc_esperado]
        
        # Captura os sinais de estado do estágio IF do datapath
        pc_obtido   = int(dut.DBG_r_pc_o.value)
        ir_obtido   = int(dut.DBG_r_ir_o.value)
        opc_obtido  = int(dut.DBG_r_opc_o.value)
        inst_obtido = int(dut.DBG_instruction_o.value)
        
        if ir_obtido != instr_esperada:
            log_error(f"[Ciclo {i}] Falha de IR! PC Esperado na captura: 0x{pc_esperado:08X}")
            log_error(f"   Esperado: 0x{instr_esperada:08X}")
            log_error(f"   Obtido  : 0x{ir_obtido:08X}")
            IFMonitor.log_status_ciclo(dut, "FALHA NO STRESS TEST")
            assert False, "Dados do IR inconsistentes (Race Condition?)"

        if pc_obtido != (pc_esperado + 4):
            log_error(f"[Ciclo {i}] Falha de PC! PC perdeu sincronismo.")
            assert False

        if opc_obtido != (pc_obtido - 4):
            log_error(f"[Ciclo {i}] OldPC incorreto. Esperado: 0, Recebido: {opc_obtido}")
            assert False
            
        if inst_obtido != ir_obtido:
            log_error(f"[Ciclo {i}] Instrução incorreta. Esperado: 0x{ir_obtido:08X}, Recebido: 0x{inst_obtido:08X}")
            assert False
        
        # Incrementa PC + 4 para a próxima instrução
        pc_esperado += 4

    # Escreve mensagem de sucesso do teste
    log_success(f"Stress Test OK: {N_INSTRUCOES} instruções processadas com sucesso.")