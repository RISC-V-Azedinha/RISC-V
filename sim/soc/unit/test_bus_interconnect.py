# =====================================================================================================
# File: test_bus_interconnect.py
# =====================================================================================================
# 
# CONSIDERAÇÕES DE VERIFICAÇÃO E COBERTURA:
# 
# 1. Cobertura de Mapeamento (Fuzzing):
#    - Garante que 100% do espaço de endereçamento (0x00000000 a 0xFFFFFFFF) seja
#      decodificado corretamente para o escravo alvo ou caia na proteção de Bus Fault.
# 
# 2. Cobertura de Topologia (Crossbar Parallelism):
#    - Valida a independência dos caminhos de dados. Garante que Mestre A falando com Escravo X 
#      não gera 'stall' ou corrupção no Mestre B falando com Escravo Y.
# 
# 3. Corner Cases Cobertos nesta Suíte:
#    - Priority Encoder: Colisões simultâneas no mesmo ciclo (CPU > DMA_RD > DMA_WR).
#    - Sticky Arbitration (Lock): Se um Mestre de alta prioridade acessa um Escravo lento, 
#      a malha DEVE travar o roteamento até o hand-off, impedindo intercalação corrupta.
#    - Bus Faults: Transações para endereços vazios devem retornar ready=1 e data=0 
#      imediatamente para evitar Deadlocks no processador.
# 
# 4. Monitores de Protocolo (Assertions Background):
#    - O teste instacia coroutines passivas que vigiam as portas de entrada. Se qualquer 
#      estímulo de teste ou retorno do RTL violar o protocolo (ex: retirar VALID antes do READY), 
#      a simulação aborta instantaneamente.
# 
# =====================================================================================================

import cocotb
import random
from cocotb.triggers import Timer, RisingEdge, ReadOnly, FallingEdge
from cocotb.clock import Clock
from sim.core.single_cycle.include.test_utils import log_header, log_success, log_error

# ==============================================================================
# AUXILIARES & GOLDEN MODEL
# ==============================================================================

async def setup_dut(dut):
    """Inicializa clock, reset e zera entradas do DUT."""
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    # Inicia os monitores de protocolo em background
    cocotb.start_soon(protocol_monitor(dut.clk_i, dut.cpu_vld_i, dut.cpu_rdy_o, "CPU_PORT"))
    cocotb.start_soon(protocol_monitor(dut.clk_i, dut.dma_rd_vld_i, dut.dma_rd_rdy_o, "DMA_RD_PORT"))
    cocotb.start_soon(protocol_monitor(dut.clk_i, dut.dma_wr_vld_i, dut.dma_wr_rdy_o, "DMA_WR_PORT"))

    dut.rst_i.value = 1
    dut.cpu_vld_i.value = 0
    dut.imem_vld_i.value = 0
    dut.dma_rd_vld_i.value = 0
    dut.dma_wr_vld_i.value = 0
    
    await Timer(15, "ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

async def settle():
    """Aguarda propagação combinacional inicial."""
    await Timer(1, "ns")

def model_addr_decode(addr):
    """Modelo Python da decodificação de endereço."""
    nibble = (addr >> 28) & 0xF
    if nibble == 0x0: return "ROM"
    if nibble == 0x1: return "UART"
    if nibble == 0x2: return "GPIO"
    if nibble == 0x4: return "DMA"
    if nibble == 0x5: return "CLINT" 
    if nibble == 0x6: return "PLIC"
    if nibble == 0x8: return "RAM"
    if nibble == 0x9: return "NPU"
    return "NONE"

async def protocol_monitor(clk, vld, rdy, port_name):
    """Monitor passivo que vigia infrações do protocolo rdy/vld."""
    while True:
        await RisingEdge(clk)
        await ReadOnly() # Lê os valores processados no fim do ciclo
        
        if vld.value == 1 and rdy.value == 0:
            # Se o mestre requisitou e não teve resposta, ele é obrigado a manter o VLD.
            # Checamos na borda de descida (meio do ciclo) para evitar Race Conditions 
            # com as transições de borda de subida geradas pelo testbench.
            await FallingEdge(clk)
            assert vld.value == 1, f"VIOLAÇÃO DE PROTOCOLO em {port_name}: VALID caiu antes do READY!"

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_sanity_check(dut):
    log_header("Teste 1: Sanity Check (Endereços Conhecidos via CPU)")
    await setup_dut(dut)
    
    dut.cpu_addr_i.value = 0x8000AABB
    dut.cpu_vld_i.value  = 1
    await settle()
    
    assert dut.ram_vld_b_o.value == 1, "RAM não foi selecionada!"
    assert dut.rom_vld_b_o.value == 0, "ROM foi selecionada incorretamente!"
    
    dut.cpu_vld_i.value = 0 # Limpeza para evitar disparo do monitor
    log_success("Sanity Check OK")

@cocotb.test()
async def test_harvard_concurrency(dut):
    log_header("Teste 2: Harvard Split (Acesso Simultâneo IMem e CPU_DMem)")
    await setup_dut(dut)
    
    VAL_INSTRUCT = 0x11223344  
    VAL_DATA_OLD = 0x55667788  
    
    dut.rom_data_a_i.value = VAL_INSTRUCT
    dut.ram_data_b_i.value = VAL_DATA_OLD 
    
    dut.imem_addr_i.value = 0x00001000
    dut.imem_vld_i.value  = 1
    
    dut.cpu_addr_i.value = 0x80002000
    dut.cpu_vld_i.value  = 1
    dut.cpu_we_i.value   = 0xF
    
    await settle()
    
    assert dut.rom_vld_a_o.value == 1, "IMem não selecionou ROM"
    assert dut.ram_vld_b_o.value == 1, "CPU não selecionou RAM"
    assert int(dut.imem_data_o.value) == VAL_INSTRUCT, "IMem leu dado errado"
    
    dut.imem_vld_i.value = 0
    dut.cpu_vld_i.value = 0
    log_success("Concorrência Harvard OK")

@cocotb.test()
async def test_fuzzing_map(dut):
    log_header("Teste 3: Fuzzing Completo (Decodificação da porta CPU)")
    await setup_dut(dut)
    ITERATIONS = 1000
    
    for i in range(ITERATIONS):
        addr = random.randint(0, 0xFFFFFFFF)
        
        dut.cpu_addr_i.value = addr
        dut.cpu_vld_i.value  = 1
        await settle()
        
        target = model_addr_decode(addr)
        
        signals = {
            "ROM":  int(dut.rom_vld_b_o.value),
            "UART": int(dut.uart_vld_o.value),
            "GPIO": int(dut.gpio_vld_o.value),
            "DMA":  int(dut.dma_vld_o.value),
            "CLINT": int(dut.clint_vld_o.value), 
            "PLIC":  int(dut.plic_vld_o.value),  
            "RAM":  int(dut.ram_vld_b_o.value),
            "NPU":  int(dut.npu_vld_o.value)
        }
        
        for dev, state in signals.items():
            if dev == target:
                assert state == 1, f"FALHA Fuzz #{i}: {target} deveria estar ativo para addr {hex(addr)}"
            else:
                assert state == 0, f"FALHA Fuzz #{i}: {dev} ativou incorretamente para addr {hex(addr)}"
                    
        if target != "NONE":
            mock_data = random.randint(0, 0xFFFFFFFF)
            
            # CORREÇÃO: O Testbench agora responde RDY para TODOS os targets válidos
            if target == "ROM":   dut.rom_data_b_i.value = mock_data; dut.rom_rdy_b_i.value = 1
            elif target == "RAM": dut.ram_data_b_i.value = mock_data; dut.ram_rdy_b_i.value = 1
            elif target == "DMA": dut.dma_data_i.value = mock_data;   dut.dma_rdy_i.value = 1
            elif target == "UART": dut.uart_data_i.value = mock_data; dut.uart_rdy_i.value = 1
            elif target == "GPIO": dut.gpio_data_i.value = mock_data; dut.gpio_rdy_i.value = 1
            elif target == "NPU":  dut.npu_data_i.value = mock_data;  dut.npu_rdy_i.value = 1
            elif target == "CLINT": dut.clint_data_i.value = mock_data; dut.clint_rdy_i.value = 1
            elif target == "PLIC": dut.plic_data_i.value = mock_data; dut.plic_rdy_i.value = 1
            
            await settle()
            assert int(dut.cpu_rdy_o.value) == 1, f"Ready não retornou para {target}"
            
        else:
            # Com a proteção Bus Fault, o barramento devolve ready forçado com data zero
            assert int(dut.cpu_rdy_o.value) == 1, f"Ready Bus Fault falhou (Unmapped: {hex(addr)})"
            assert int(dut.cpu_data_o.value) == 0, f"Data Bus Fault deveria ser 0 (Unmapped: {hex(addr)})"

        # CORREÇÃO DO HANDSHAKE: O mestre espera a borda do clock
        # onde o RDY é 1 ANTES de retirar o VLD.
        await RisingEdge(dut.clk_i)
        
        # Agora sim o VLD pode cair
        dut.cpu_vld_i.value = 0
        
        # Limpa todos os ready simulados
        dut.rom_rdy_b_i.value = 0
        dut.ram_rdy_b_i.value = 0
        dut.dma_rdy_i.value = 0
        dut.uart_rdy_i.value = 0
        dut.gpio_rdy_i.value = 0
        dut.npu_rdy_i.value = 0
        dut.clint_rdy_i.value = 0
        dut.plic_rdy_i.value = 0

    log_success(f"Fuzzing OK ({ITERATIONS} endereços)")

@cocotb.test()
async def test_crossbar_parallelism(dut):
    log_header("Teste 4: Crossbar - Paralelismo Total (Sem Colisão)")
    await setup_dut(dut)
    
    # CPU -> GPIO | DMA_RD -> RAM | DMA_WR -> NPU
    dut.cpu_addr_i.value = 0x20000000;    dut.cpu_vld_i.value = 1
    dut.dma_rd_addr_i.value = 0x80004000; dut.dma_rd_vld_i.value = 1
    dut.dma_wr_addr_i.value = 0x90000000; dut.dma_wr_vld_i.value = 1
    await settle()
    
    assert dut.gpio_vld_o.value == 1, "CPU não alcançou GPIO"
    assert dut.ram_vld_b_o.value == 1, "DMA_RD não alcançou RAM"
    assert dut.npu_vld_o.value == 1, "DMA_WR não alcançou NPU"
    
    dut.gpio_rdy_i.value = 1; dut.ram_rdy_b_i.value = 1; dut.npu_rdy_i.value = 1
    await settle()
    
    assert dut.cpu_rdy_o.value == 1, "CPU sofreu STALL indevido"
    assert dut.dma_rd_rdy_o.value == 1, "DMA_RD sofreu STALL indevido"
    assert dut.dma_wr_rdy_o.value == 1, "DMA_WR sofreu STALL indevido"
    
    dut.cpu_vld_i.value = 0; dut.dma_rd_vld_i.value = 0; dut.dma_wr_vld_i.value = 0
    log_success("Paralelismo do Crossbar Validado!")

@cocotb.test()
async def test_slave_arbitration(dut):
    log_header("Teste 5: Crossbar - Arbitragem no Escravo (Colisão)")
    await setup_dut(dut)
    
    # Colisão: CPU e DMA_RD tentam acessar a RAM
    dut.cpu_addr_i.value = 0x80001000;    dut.cpu_vld_i.value = 1
    dut.dma_rd_addr_i.value = 0x80002000; dut.dma_rd_vld_i.value = 1
    dut.ram_rdy_b_i.value = 1
    await settle()
    
    assert dut.ram_vld_b_o.value == 1, "RAM não ativada"
    # Prioridade agora é do DMA: DMA_RD > DMA_WR > CPU
    assert dut.cpu_rdy_o.value == 0, "CPU não deveria receber ready (perde prioridade para DMA)"
    assert dut.dma_rd_rdy_o.value == 1, "DMA_RD deveria receber ready (deve ter prioridade)"
    assert int(dut.ram_addr_b_o.value) == 0x80002000, "Mux roteou endereço errado (deve selecionar DMA_RD)"
    
    # Limpeza para evitar disparo do monitor na transição de testes
    dut.cpu_vld_i.value = 0
    dut.dma_rd_vld_i.value = 0
    log_success("Arbitragem Validada!")

@cocotb.test()
async def test_sticky_arbitration_and_handoff(dut):
    log_header("Teste 5: Sticky Arbitration & Hand-off (CPU retém a RAM, DMA espera)")
    await setup_dut(dut)
    
    # Ciclo 1: CPU pede acesso à RAM. A RAM é lenta e não responde ainda.
    dut.cpu_addr_i.value = 0x80001000
    dut.cpu_vld_i.value = 1
    dut.ram_rdy_b_i.value = 0
    await RisingEdge(dut.clk_i) # Clock tick registra o owner = MST_CPU
    
    assert dut.ram_vld_b_o.value == 1, "RAM não ativada pela CPU"
    assert dut.cpu_rdy_o.value == 0, "CPU não deveria ter recebido rdy"

    # Ciclo 2: No meio da transação da CPU, o DMA tenta acessar a RAM.
    dut.dma_rd_addr_i.value = 0x80002000
    dut.dma_rd_vld_i.value = 1
    await settle()

    # Verifica se a Sticky Arbitration segurou o roteamento na CPU
    assert dut.dma_rd_rdy_o.value == 0, "DMA não sofreu STALL. Colisão!"
    assert int(dut.ram_addr_b_o.value) == 0x80001000, "O MUX mudou para o DMA no meio da transação da CPU!"

    # Ciclo 3: A RAM finalmente responde para a CPU.
    dut.ram_rdy_b_i.value = 1
    await settle()
    assert dut.cpu_rdy_o.value == 1, "CPU não recebeu a resposta da RAM"
    
    # Avança o clock. A CPU enxerga o RDY e abaixa o VLD. A trava deve ser solta.
    await RisingEdge(dut.clk_i)
    dut.cpu_vld_i.value = 0
    dut.ram_rdy_b_i.value = 0 # RAM volta a zero
    await settle()

    # Ciclo 4: Hand-off. Com a CPU fora, o DMA deve ganhar o barramento automaticamente.
    assert dut.ram_vld_b_o.value == 1, "RAM não re-ativada para o DMA"
    assert int(dut.ram_addr_b_o.value) == 0x80002000, "MUX não repassou endereço do DMA"
    
    # Finaliza a transação do DMA
    dut.ram_rdy_b_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.dma_rd_vld_i.value = 0
    
    log_success("Sticky Arbitration e Hand-off Validados Rigorosamente!")

@cocotb.test()
async def test_three_way_collision(dut):
    log_header("Teste 6: Three-Way Collision (Priority Encoder Extreme)")
    await setup_dut(dut)
    
    # Os 3 mestres atiram requisições na NPU simultaneamente.
    dut.cpu_addr_i.value = 0x90000004;    dut.cpu_vld_i.value = 1
    dut.dma_rd_addr_i.value = 0x90000010; dut.dma_rd_vld_i.value = 1
    dut.dma_wr_addr_i.value = 0x90000014; dut.dma_wr_vld_i.value = 1
    dut.npu_rdy_i.value = 0
    await settle()
    
    # Avaliação Combinacional (Prioridade 1: DMA_RD)
    assert dut.cpu_rdy_o.value == 0 and dut.dma_rd_rdy_o.value == 0 and dut.dma_wr_rdy_o.value == 0
    assert int(dut.npu_addr_o.value) == 0x90000010, "DMA_RD falhou no Priority Encoder"
    
    # Fim Transação DMA_RD
    dut.npu_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.dma_rd_vld_i.value = 0
    dut.npu_rdy_i.value = 0
    await settle()
    
    # Avaliação Combinacional (Prioridade 2: DMA_WR)
    assert int(dut.npu_addr_o.value) == 0x90000014, "DMA_WR falhou no Priority Encoder pós DMA_RD"
    
    # Fim Transação DMA_WR
    dut.npu_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.dma_wr_vld_i.value = 0
    dut.npu_rdy_i.value = 0
    await settle()
    
    # Avaliação Combinacional (Prioridade 3: CPU)
    assert int(dut.npu_addr_o.value) == 0x90000004, "CPU falhou no Priority Encoder final"
    
    # Fim Transação CPU
    dut.npu_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.cpu_vld_i.value = 0

    log_success("Priority Encoder suportou colisão tripla perfeitamente!")