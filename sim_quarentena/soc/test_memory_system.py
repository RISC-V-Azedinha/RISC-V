# =====================================================================================================
# File: test_memory_system.py
# =====================================================================================================
#
# >>> Descrição: Testbench de Sistema (System Level).
#       Verifica a interação completa: CPU + DMA + Arbiter + Interconnect + Memórias.
#
# =====================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from test_utils import log_header, log_success, log_error

# ==============================================================================
# CONSTANTES
# ==============================================================================

# Endereços base do sistema de memória
RAM_BASE     = 0x80000000
DMA_CFG_BASE = 0x40000000

# Tamanho da RAM (Random Access Memory)
RAM_SIZE     = 4096 * 4 # 16KB bytes

# ==============================================================================
# AUXILIARES
# ==============================================================================

async def setup_dut(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_i.value = 1

    dut.cpu_dmem_addr_i.value = 0
    dut.cpu_dmem_wdata_i.value = 0
    dut.cpu_dmem_we_i.value = 0
    dut.cpu_dmem_vld_i.value = 0
    dut.cpu_imem_addr_i.value = 0
    dut.cpu_imem_vld_i.value = 0

    dut.dma_m_addr_i.value = 0
    dut.dma_m_wdata_i.value = 0
    dut.dma_m_we_i.value = 0
    dut.dma_m_vld_i.value = 0

    dut.dma_s_rdata_i.value = 0
    dut.dma_s_rdy_i.value = 0

    await Timer(20, unit="ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

async def cpu_access(dut, addr, wdata=None, we_vec=0):
    dut.cpu_dmem_addr_i.value = addr
    dut.cpu_dmem_vld_i.value = 1

    if wdata is not None:
        dut.cpu_dmem_wdata_i.value = wdata
        dut.cpu_dmem_we_i.value = we_vec
    else:
        dut.cpu_dmem_we_i.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")
        if dut.cpu_dmem_rdy_o.value == 1:
            val = int(dut.cpu_dmem_data_o.value)
            dut.cpu_dmem_vld_i.value = 0
            dut.cpu_dmem_we_i.value = 0
            return val

    raise TimeoutError("CPU Timeout esperando Ready")

async def dma_access(dut, addr, wdata=None):
    dut.dma_m_addr_i.value = addr
    dut.dma_m_vld_i.value = 1

    if wdata is not None:
        dut.dma_m_wdata_i.value = wdata
        dut.dma_m_we_i.value = 1
    else:
        dut.dma_m_we_i.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")
        if dut.dma_m_rdy_o.value == 1:
            val = int(dut.dma_m_data_o.value)
            dut.dma_m_vld_i.value = 0
            dut.dma_m_we_i.value = 0
            return val

    raise TimeoutError("DMA Timeout esperando Ready")

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_01_basic_rw(dut):
    log_header("Teste 1: Acessos Básicos RAM")
    await setup_dut(dut)

    addr1 = RAM_BASE + 0x100
    val1  = 0x11223344
    await cpu_access(dut, addr1, val1, 0xF)
    assert await cpu_access(dut, addr1) == val1
    assert await dma_access(dut, addr1) == val1

    addr2 = RAM_BASE + 0x200
    val2  = 0xAABBCCDD
    await dma_access(dut, addr2, val2)
    assert await cpu_access(dut, addr2) == val2

    log_success("Acessos Básicos OK")

@cocotb.test()
async def test_02_dma_config_path(dut):
    log_header("Teste 2: Acesso CPU -> DMA Config")
    await setup_dut(dut)

    dut.dma_s_rdy_i.value = 1

    dut.cpu_dmem_addr_i.value = DMA_CFG_BASE
    dut.cpu_dmem_wdata_i.value = 0xDEADBEEF
    dut.cpu_dmem_we_i.value = 0xF
    dut.cpu_dmem_vld_i.value = 1

    seen = False
    for _ in range(5):
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")
        if dut.dma_s_vld_o.value == 1:
            seen = True
            assert int(dut.dma_s_wdata_o.value) == 0xDEADBEEF
            break

    assert seen, "Sinal Valid não chegou no DMA Slave"

    dut.cpu_dmem_vld_i.value = 0
    log_success("Rota de Configuração DMA OK")

@cocotb.test()
async def test_03_arbitration_collision(dut):
    log_header("Teste 3: Colisão CPU vs DMA")
    await setup_dut(dut)

    dut.cpu_dmem_addr_i.value = RAM_BASE + 0x300
    dut.cpu_dmem_vld_i.value = 1

    dut.dma_m_addr_i.value = RAM_BASE + 0x400
    dut.dma_m_vld_i.value = 1

    dma_granted = False
    for _ in range(5):
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")
        if dut.dma_m_rdy_o.value == 1:
            dma_granted = True
            break

    assert dma_granted, "DMA não recebeu Ready a tempo"
    assert dut.cpu_dmem_rdy_o.value == 0, "CPU ganhou antes do DMA!"

    dut.dma_m_vld_i.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")
        if dut.cpu_dmem_rdy_o.value == 1:
            log_success("CPU retomou acesso corretamente.")
            return

    assert False, "CPU não ganhou acesso após DMA liberar"

@cocotb.test()
async def test_04_stress_fuzzing(dut):
    log_header("Teste 4: Stress Fuzzing (CPU + DMA)")
    await setup_dut(dut)

    ram_model = {}

    for i in range(1000):
        scenario = random.randint(1, 3)

        addr_cpu = RAM_BASE + (random.randint(0, 200) * 4)
        addr_dma = RAM_BASE + (random.randint(201, 400) * 4)

        data_cpu = random.randint(0, 0xFFFFFFFF)
        data_dma = random.randint(0, 0xFFFFFFFF)

        cpu_active = 1 if (scenario & 1) else 0
        dma_active = 1 if (scenario & 2) else 0

        dut.cpu_dmem_vld_i.value = cpu_active
        dut.cpu_dmem_addr_i.value = addr_cpu
        dut.cpu_dmem_wdata_i.value = data_cpu
        dut.cpu_dmem_we_i.value = 0xF if cpu_active else 0

        dut.dma_m_vld_i.value = dma_active
        dut.dma_m_addr_i.value = addr_dma
        dut.dma_m_wdata_i.value = data_dma
        dut.dma_m_we_i.value = 1 if dma_active else 0

        await RisingEdge(dut.clk_i)
        await RisingEdge(dut.clk_i)
        await Timer(1, "ns")

        if dma_active and dut.dma_m_rdy_o.value == 1:
            ram_model[addr_dma] = data_dma
        elif cpu_active and dut.cpu_dmem_rdy_o.value == 1:
            ram_model[addr_cpu] = data_cpu

        if i % 50 == 0 and ram_model:
            dut.dma_m_vld_i.value = 0
            dut.cpu_dmem_vld_i.value = 0
            await Timer(1, "ns")

            chk_addr, chk_data = random.choice(list(ram_model.items()))
            assert await cpu_access(dut, chk_addr) == chk_data

    log_success("Fuzzing Completo sem erros de integridade.")
