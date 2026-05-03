# ==============================================================================
# File: test_dual_port_ram.py
# ==============================================================================
#
# >>> Descrição: Este arquivo contém testes em cocotb para uma memória RAM dual-port (BRAM)
#       que utiliza a política READ-FIRST: quando há escrita, a saída mostra o valor
#       antigo (anterior à escrita), não o novo valor.
#
# ==============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import random

# Constantes de configuração da memória
ADDR_WIDTH = 12
DATA_WIDTH = 32
MAX_ADDR   = (2 ** ADDR_WIDTH) - 1  # Endereço máximo: 0xFFF
MAX_DATA   = (2 ** DATA_WIDTH) - 1  # Dado máximo: 0xFFFFFFFF

from sim.core.single_cycle.include.test_utils import (
    settle, log_header, log_success, log_info
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

@cocotb.test()
async def test_basic_rw_port_a(dut):
    log_header("Teste sequencial: escreve, depois lê")

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    addr = 0x100
    data = 0xDEADBEEF
    
    # PASSO 1: ESCRITA
    dut.vld_a_i.value = 1
    dut.we_a.value = 0xF          
    dut.addr_a.value = addr       
    dut.data_a_i.value = data    
    await RisingEdge(dut.clk)     
    
    # PASSO 2: LEITURA
    dut.we_a.value = 0            
    await RisingEdge(dut.clk)     
    
    await settle()
    val, _ = safe_int(dut.data_a_o.value)
    
    dut.vld_a_i.value = 0
    
    assert val == data, f"Erro: Leu {hex(val or 0)}, esperava {hex(data)}"
    log_success("Basic RW OK")


@cocotb.test()
async def test_random_stress(dut):
    log_header("Teste Randômico Usando a Política READ-FIRST.")

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    
    golden_mem = {}
    NUM_TRANSACTIONS = 1000
    
    log_info(f"Iniciando {NUM_TRANSACTIONS} iterações...")

    for i in range(NUM_TRANSACTIONS):
        addr = random.randint(0, MAX_ADDR)
        data = random.randint(0, MAX_DATA)
        is_write = random.choice([True, False])
        use_port_a = random.choice([True, False])
        
        we_mask = 0xF if is_write else 0

        if use_port_a:
            # Operação na PORTA A
            dut.vld_a_i.value = 1
            dut.addr_a.value = addr
            dut.we_a.value = we_mask                      
            dut.data_a_i.value = data if is_write else 0 
            
            dut.vld_b_i.value = 0
            dut.we_b.value = 0  
        else:
            # Operação na PORTA B
            dut.vld_b_i.value = 1
            dut.addr_b.value = addr
            dut.we_b.value = we_mask                      
            dut.data_b_i.value = data if is_write else 0 
            
            dut.vld_a_i.value = 0
            dut.we_a.value = 0  

        if is_write:
            golden_mem[addr] = data

        await RisingEdge(dut.clk)
        
        # ======== VERIFICAÇÃO DE INTEGRIDADE ========
        if not is_write:
            await settle()
            
            if addr in golden_mem:
                expected = golden_mem[addr]
                signal = dut.data_a_o if use_port_a else dut.data_b_o
                port = "A" if use_port_a else "B"
                
                got, binstr = safe_int(signal.value)
                
                if got is None: 
                    assert False, f"Iter {i}: Porta {port} indefinida: {binstr}"
                
                assert got == expected, \
                    f"FALHA Iter {i} ({port}): Endereço {hex(addr)}. Esp: {hex(expected)}, Obt: {hex(got)}"
            
        dut.we_a.value = 0
        dut.we_b.value = 0

    log_success("Stress Test OK")