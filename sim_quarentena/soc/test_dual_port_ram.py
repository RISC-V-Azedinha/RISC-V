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
# ADDR_WIDTH: número de bits para endereçamento (2^12 = 4096 endereços)
# DATA_WIDTH: número de bits por palavra de dados (32 bits)

ADDR_WIDTH = 12
DATA_WIDTH = 32
MAX_ADDR   = (2 ** ADDR_WIDTH) - 1  # Endereço máximo: 0xFFF
MAX_DATA   = (2 ** DATA_WIDTH) - 1  # Dado máximo: 0xFFFFFFFF

# Importações auxiliares para logging e utilitários de simulação
from test_utils import (
    settle, log_header, log_success, log_info
)

# Função auxiliar para converter sinais cocotb em inteiros com segurança
# Retorna uma tupla (valor_inteiro, erro) onde:
#   - Se bem-sucedido: (valor_int, None)
#   - Se falhar (valor inválido como 'X' ou 'U'): (None, string_do_valor)

def safe_int(signal_value):
    try:
        return int(signal_value), None
    except ValueError:
        # Captura sinais com estado indeterminado ou indefinido
        return None, str(signal_value)

# Função para resetar a unidade sob teste (DUT) para estado inicial
# Desativa escrita em ambas as portas (A e B) e zera endereços e dados
# Aguarda 5 ciclos de clock para permitir que o DUT se estabilize

async def reset_dut(dut):
    # Desativa porta A
    dut.we_a.value = 0; dut.addr_a.value = 0; dut.data_in_a.value = 0
    # Desativa porta B
    dut.we_b.value = 0; dut.addr_b.value = 0; dut.data_in_b.value = 0
    # Aguarda 5 ciclos de clock para estabilização
    for _ in range(5): await RisingEdge(dut.clk)

@cocotb.test()
async def test_basic_rw_port_a(dut):

    # Teste básico de escrita seguida de leitura na porta A.
    
    # Procedimento:
    # 1. Escreve um valor em um endereço específico
    # 2. No ciclo seguinte, lê o mesmo endereço
    # 3. Verifica se o valor lido corresponde ao valor escrito
    
    log_header("Teste sequencial: escreve, depois lê")

    # Inicia o clock da simulação (período de 10 ns)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    
    # Reseta todos os sinais de controle e dados
    await reset_dut(dut)
    
    # Define endereço e dados de teste
    addr = 0x100
    data = 0xDEADBEEF
    
    # PASSO 1: ESCRITA - Escreve o dado no endereço especificado
    dut.we_a.value = 0xF          # Ativa escrita na porta A
    dut.addr_a.value = addr       # Define endereço de escrita
    dut.data_in_a.value = data    # Define dado a escrever
    await RisingEdge(dut.clk)     # Aguarda rising edge do clock (ciclo 1)
    
    # PASSO 2: LEITURA - Lê o valor armazenado no mesmo endereço
    dut.we_a.value = 0            # Desativa escrita para modo leitura
    # Mantém-se o endereço para ler a mesma posição de memória
    # Conforme comportamento READ-FIRST, a saída agora contém o novo dado
    await RisingEdge(dut.clk)     # Aguarda rising edge (ciclo 2)
    
    # Aguarda propagação de sinais antes de verificar resultado
    await settle()
    # Lê o dado da saída e converte para inteiro
    val, _ = safe_int(dut.data_out_a.value)
    
    # Verifica se o valor lido corresponde ao escrito
    assert val == data, f"Erro: Leu {hex(val or 0)}, esperava {hex(data)}"
    log_success("Basic RW OK")

@cocotb.test()
async def test_random_stress(dut):
    # Teste de estresse com 1000 operações aleatórias de leitura/escrita.
    
    # Características do teste:
    # - Endereços aleatórios entre 0 e MAX_ADDR
    # - Dados aleatórios entre 0 e MAX_DATA
    # - Operações aleatórias de leitura e escrita
    # - Uso aleatório de porta A ou B
    #- Usa "Golden Model" (golden_mem) para verificação de integridade
    
    # Nota sobre READ-FIRST:
    # Durante uma escrita, a saída reflete o valor ANTIGO (antes da escrita).
    # Por isso, só são verifiicadas as leituras (is_write = False).
    
    log_header("Teste Randômico Usando a Política READ-FIRST.")

    # Inicia o clock da simulação com período de 10 ns
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    # Reseta os sinais de controle e dados
    await reset_dut(dut)
    
    # Golden Model: dicionário que mantém cópia do conteúdo da memória
    # Usado para verificar se a BRAM retorna os valores corretos
    golden_mem = {}
    NUM_TRANSACTIONS = 1000  # Número de operações a realizar
    
    log_info(f"Iniciando {NUM_TRANSACTIONS} iterações...")

    # Executa 1000 transações aleatórias
    for i in range(NUM_TRANSACTIONS):
        # Gera valores aleatórios para cada transação
        addr = random.randint(0, MAX_ADDR)        # Endereço aleatório
        data = random.randint(0, MAX_DATA)        # Dado aleatório
        is_write = random.choice([True, False])   # Tipo aleatório (W/R)
        use_port_a = random.choice([True, False]) # Porta aleatória (A/B)
        
        # Máscara de escrita completa (Word Write) = 0xF (15)
        # Se is_write for False, máscara é 0
        we_mask = 0xF if is_write else 0

        # Configura os sinais de entrada conforme a transação gerada
        if use_port_a:
            # Operação na PORTA A
            dut.addr_a.value = addr
            dut.we_a.value = we_mask                      # Write Enable
            dut.data_in_a.value = data if is_write else 0 # Dado (se escrita)
            dut.we_b.value = 0  # Desativa porta B
        else:
            # Operação na PORTA B
            dut.addr_b.value = addr
            dut.we_b.value = we_mask                      # Write Enable
            dut.data_in_b.value = data if is_write else 0 # Dado (se escrita)
            dut.we_a.value = 0  # Desativa porta A

        # Isso mantém um registro do que "deveria" estar na memória
        if is_write:
            golden_mem[addr] = data

        # Aguarda um ciclo de clock para a transação ser processada
        await RisingEdge(dut.clk)
        
        # ======== VERIFICAÇÃO DE INTEGRIDADE ========
        # Importante: verifica APENAS leituras (is_write = False)
        # Motivo: Em operações READ-FIRST, durante escrita a saída mostra
        #         o dado ANTIGO, não o novo. Verificar escrita causaria
        #         falsos negativos, pois golden_mem já contém o novo dado.

        if not is_write:
            # Aguarda propagação de sinais antes de ler
            await settle()
            
            # Verifica apenas se o endereço já foi escrito anteriormente
            if addr in golden_mem:
                # Valor esperado (do Golden Model)
                expected = golden_mem[addr]
                # Sinal a verificar (porta A ou B, conforme transação)
                signal = dut.data_out_a if use_port_a else dut.data_out_b
                port = "A" if use_port_a else "B"
                
                # Converte sinal cocotb para inteiro (com tratamento de erro)
                got, binstr = safe_int(signal.value)
                
                # Detecta estado indeterminado (X ou U) - erro grave
                if got is None: 
                    assert False, f"Iter {i}: Porta {port} indefinida: {binstr}"
                
                # Verifica se o valor lido corresponde ao esperado
                assert got == expected, \
                    f"FALHA Iter {i} ({port}): Endereço {hex(addr)}. Esp: {hex(expected)}, Obt: {hex(got)}"
            
        # Limpa os sinais de escrita após cada transação
        dut.we_a.value = 0
        dut.we_b.value = 0

    log_success("Stress Test OK")