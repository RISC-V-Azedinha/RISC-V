# ==============================================================================
# File: test_dual_port_ram.py
# ==============================================================================
#
# >>> Descrição: Este arquivo contém testes em cocotb para uma memória RAM dual-port (BRAM)
#       que utiliza a política READ-FIRST: quando há escrita, a saída mostra o valor
#       antigo (anterior à escrita), não o novo valor.
#       [ATUALIZADO: Testes refatorados para respeitar o Handshake Atômico (rdy/vld)]
#
# ==============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge
import random

# Constantes de configuração da memória
ADDR_WIDTH = 12
DATA_WIDTH = 32
MAX_ADDR   = (2 ** ADDR_WIDTH) - 1  # Endereço máximo: 0xFFF
MAX_DATA   = (2 ** DATA_WIDTH) - 1  # Dado máximo: 0xFFFFFFFF

from sim.core.single_cycle.include.test_utils import (
    settle, log_header, log_success, log_info, log_error
)

def safe_int(signal_value):
    try:
        return int(signal_value), None
    except ValueError:
        return None, str(signal_value)

async def reset_dut(dut):
    # Desativa porta A
    dut.we_a.value = 0
    dut.addr_a.value = 0
    dut.data_a_i.value = 0
    dut.vld_a_i.value = 0
    
    # Desativa porta B
    dut.we_b.value = 0
    dut.addr_b.value = 0
    dut.data_b_i.value = 0
    dut.vld_b_i.value = 0
    
    for _ in range(5): await RisingEdge(dut.clk)

# ==============================================================================
# Função Universal de Handshake para a RAM
# ==============================================================================
async def ram_transaction(dut, port, addr, we_mask, data=0):
    """Executa uma transação atômica respeitando estritamente o rdy/vld"""
    if port == 'A':
        dut.addr_a.value = addr
        dut.data_a_i.value = data
        dut.we_a.value = we_mask
        dut.vld_a_i.value = 1
        
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(dut.rdy_a_o.value) == 1:
                val = dut.data_a_o.value
                break
                
        # Simula o Mestre consumindo o ACK e abaixando o pedido na mesma borda
        await RisingEdge(dut.clk)
        dut.vld_a_i.value = 0
        dut.we_a.value = 0
        
        # Insere 1 ciclo de "descanso" no barramento para separar transações back-to-back
        await RisingEdge(dut.clk) 
        return val
        
    else:
        dut.addr_b.value = addr
        dut.data_b_i.value = data
        dut.we_b.value = we_mask
        dut.vld_b_i.value = 1
        
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(dut.rdy_b_o.value) == 1:
                val = dut.data_b_o.value
                break
                
        await RisingEdge(dut.clk)
        dut.vld_b_i.value = 0
        dut.we_b.value = 0
        
        await RisingEdge(dut.clk)
        return val

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_basic_rw_port_a(dut):
    log_header("Teste sequencial: escreve, depois lê (Porta A)")

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    addr = 0x100
    data = 0xDEADBEEF
    
    # PASSO 1: ESCRITA
    await ram_transaction(dut, 'A', addr=addr, we_mask=0xF, data=data)
    
    # PASSO 2: LEITURA
    raw_val = await ram_transaction(dut, 'A', addr=addr, we_mask=0x0, data=0x0)
    val, _ = safe_int(raw_val)
    
    if val != data:
        log_error(f"Erro: Leu {hex(val or 0)}, esperava {hex(data)}")
        assert False
        
    log_success("Basic RW OK")

@cocotb.test()
async def test_random_stress(dut):
    log_header("Teste Randômico com Política READ-FIRST e Handshake.")

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    golden_mem = {}
    NUM_TRANSACTIONS = 1000
    
    log_info(f"Iniciando {NUM_TRANSACTIONS} iterações atômicas...")

    for i in range(NUM_TRANSACTIONS):
        addr = random.randint(0, MAX_ADDR)
        data = random.randint(0, MAX_DATA)
        is_write = random.choice([True, False])
        use_port_a = random.choice([True, False])
        
        we_mask = 0xF if is_write else 0
        port_id = 'A' if use_port_a else 'B'

        # Executa a transação completa pelo barramento
        raw_val = await ram_transaction(dut, port=port_id, addr=addr, we_mask=we_mask, data=(data if is_write else 0))
        
        # ======== VERIFICAÇÃO DE INTEGRIDADE ========
        if not is_write:
            # Em uma leitura, esperamos o valor que foi previamente gravado na memória Python
            expected = golden_mem.get(addr, 0) # Retorna 0 se o endereço nunca foi escrito
            got, binstr = safe_int(raw_val)
            
            if got is None: 
                assert False, f"Iter {i}: Porta {port_id} indefinida: {binstr}"
            
            if got != expected:
                assert False, f"FALHA Iter {i} ({port_id}): Endereço {hex(addr)}. Esp: {hex(expected)}, Obt: {hex(got)}"
                
        else:
            # Em uma escrita, atualizamos o nosso Golden Model Python
            golden_mem[addr] = data

    log_success("Stress Test OK")

@cocotb.test()
async def test_ram_double_write_bug(dut):
    """
    TDD: Verifica se a RAM mantém o rdy_a_o por 2 ciclos seguidos
    devido à falta do Edge Guard na Porta A.
    """
    log_header("Teste de Integração: Double Write na RAM (Porta A)")
    
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    # 1. Mestre inicia a transação de escrita na Porta A
    dut.addr_a.value = 0x00000004
    dut.data_a_i.value = 0xCAFEBABE
    dut.we_a.value   = 0xF # Habilita os 4 bytes
    dut.vld_a_i.value  = 1
    
    # 2. Aguarda a resposta
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_a_o.value) == 1:
            break
            
    # 3. CICLO CEGO DO MESTRE
    # O mestre abaixa os sinais exatamente na borda de clock que consome o ACK
    await RisingEdge(dut.clk)
    
    # Modificamos antes de checar os sinais (simulando mestre síncrono real)
    dut.vld_a_i.value = 0
    dut.we_a.value  = 0
    
    # Fase ReadOnly para verificar o comportamento do periférico
    await ReadOnly()
    rdy_no_ciclo_cego = int(dut.rdy_a_o.value)
    
    # 4. VERIFICAÇÃO DO BUG
    if rdy_no_ciclo_cego == 1:
        log_error("BUG DETECTADO: O rdy_a_o durou 2 ciclos seguidos!")
        assert False, "Violação de Handshake na RAM: O Mestre está perdendo 1 ciclo à toa."
        
    log_success("Edge Guard validado na RAM! Pulso atômico de 1 ciclo.")