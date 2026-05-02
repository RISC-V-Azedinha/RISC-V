# =====================================================================================================
# File: test_boot_rom.py
# =====================================================================================================
#
# >>> Descrição: Testbench para a Boot ROM.
#       Compara palavra a palavra o conteúdo da ROM com o arquivo HEX original.
#
# =====================================================================================================

import cocotb                               # Biblioteca principal do cocotb
from cocotb.clock import Clock              # Para gerar clock
from cocotb.triggers import RisingEdge      # Para aguardar borda de clock
import os                                   # Para manipulação de arquivos e caminhos

# Utilitários compartilhados (mesmo padrão do Load Unit)
from test_utils import log_header, log_info, log_success, log_error, log_console

# =====================================================================================================
# GOLDEN MODEL – Boot ROM
# =====================================================================================================
#
# Def. Formal: Para todo (a, b, opcode) ∈ Domínio_Especificado:
#    RTL(a, b, opcode) == GoldenModel(a, b, opcode)
#
# Trata-se da implementação de um modelo comportamental de referência, utilizado como oráculo de 
# verificação funcional.

def load_boot_rom_hex(filepath):
    """
    Carrega o arquivo HEX da Boot ROM para um dicionário indexado por palavra.
    """
    rom = {}

    try:
        with open(filepath, "r") as f:
            for idx, line in enumerate(f):
                line = line.strip()
                if line:
                    rom[idx] = int(line, 16)
    except FileNotFoundError:
        return None

    return rom

# =====================================================================================================
# FUNÇÃO DE VERIFICAÇÃO
# =====================================================================================================

async def verify_rom_dual_ports(dut, addr_a_word, expected_a, addr_b_word, expected_b):
    """
    Aplica endereços em ambas as portas da ROM e verifica os dados retornados (1 ciclo depois).
    """

    # Aplica endereços em bytes
    dut.addr_a_i.value = addr_a_word * 4
    dut.addr_b_i.value = addr_b_word * 4

    # Aguarda ciclo de leitura síncrona
    await RisingEdge(dut.clk)

    # Lê saídas
    actual_a = int(dut.data_a_o.value)
    actual_b = int(dut.data_b_o.value)

    # Logging para debug
    log_console(f"PORTA A: Exp=0x{expected_a:08X} Got=0x{actual_a:08X} | PORTA B: Exp=0x{expected_b:08X} Got=0x{actual_b:08X}")

    # Comparação Porta A
    if actual_a != expected_a:
        log_error(f"FALHA na ROM (Porta A) no endereço 0x{addr_a_word*4:08X}")
        assert False, "Divergência na Porta A da Boot ROM"

    # Comparação Porta B
    if actual_b != expected_b:
        log_error(f"FALHA na ROM (Porta B) no endereço 0x{addr_b_word*4:08X}")
        assert False, "Divergência na Porta B da Boot ROM"

# =====================================================================================================
# TESTE PRINCIPAL
# =====================================================================================================

@cocotb.test()
async def test_boot_rom(dut):
    
    # Teste da Boot ROM Dual-Port que compara o conteúdo da ROM com o arquivo HEX original.

    log_header("Teste da Boot ROM Dual-Port")

    # Inicia Clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Startup
    log_info("Aguardando inicialização da ROM...")
    for _ in range(5):
        await RisingEdge(dut.clk)

    # Localiza arquivo HEX
    hex_path = os.environ.get("HEX_PATH_FOR_TEST", "build/boot/bootloader.hex")
    if not os.path.exists(hex_path):
        hex_path = os.path.join(os.getcwd(), "../boot/bootloader.hex")

    rom_ref = load_boot_rom_hex(hex_path)
    if not rom_ref:
        log_error(f"Arquivo HEX não encontrado ou vazio: {hex_path}")
        assert False

    log_info(f"{len(rom_ref)} palavras carregadas do HEX")

    # Primeira leitura inválida (preenchimento do pipeline síncrono)
    dut.addr_a_i.value = 0
    dut.addr_b_i.value = 0
    await RisingEdge(dut.clk)

    # Verificação exaustiva: 
    # Enquanto a Porta A lê sequencialmente (0, 1, 2...), 
    # a Porta B lê de trás para frente (N, N-1, N-2...) para garantir independência.
    num_words = len(rom_ref)
    
    for i in range(num_words):
        idx_a = i
        idx_b = (num_words - 1) - i
        
        # Como a leitura é síncrona, verificamos o que pedimos no ciclo anterior
        if i > 0:
            prev_idx_a = i - 1
            prev_idx_b = (num_words - 1) - (i - 1)
            await verify_rom_dual_ports(
                dut, 
                idx_a, rom_ref[prev_idx_a], 
                idx_b, rom_ref[prev_idx_b]
            )
        else:
            # Primeiro ciclo apenas preenche o endereço
            dut.addr_a_i.value = idx_a * 4
            dut.addr_b_i.value = idx_b * 4
            await RisingEdge(dut.clk)

    log_success("Boot ROM Dual-Port validada com sucesso em ambas as portas!")
