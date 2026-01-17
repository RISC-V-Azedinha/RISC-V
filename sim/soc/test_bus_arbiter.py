# =====================================================================================================================
# File: test_bus_arbiter.py
# =====================================================================================================================
# Descrição: Testbench corrigido para o Bus Arbiter.
# =====================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from test_utils import log_header, log_success

# ==============================================================================
# AUXILIARES
# ==============================================================================

async def setup_dut(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_i.value = 1

    dut.m0_addr_i.value  = 0; dut.m0_wdata_i.value = 0; dut.m0_vld_i.value = 0; dut.m0_we_i.value = 0
    dut.m1_addr_i.value  = 0; dut.m1_wdata_i.value = 0; dut.m1_vld_i.value = 0; dut.m1_we_i.value = 0
    dut.s_rdy_i.value    = 0; dut.s_rdata_i.value  = 0

    await Timer(20, unit="ns")
    dut.rst_i.value = 0
    await RisingEdge(dut.clk_i)

# ==============================================================================
# TESTES
# ==============================================================================

@cocotb.test()
async def test_basic_arbitration(dut):
    log_header("Teste Básico (Sanity Check)")
    await setup_dut(dut)

    # --- Caso A: CPU (M0) ----------------

    dut.m0_addr_i.value = 0x100
    dut.m0_vld_i.value  = 1

    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")

    assert dut.s_vld_o.value == 1, "M0 Valid não passou para Slave"
    assert int(dut.s_addr_o.value) == 0x100, "M0 Addr não passou para Slave"

    # Slave responde
    dut.s_rdy_i.value = 1
    dut.s_rdata_i.value = 0xAAAA

    # Ready/Rdata são registrados
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")

    assert dut.m0_rdy_o.value == 1, "Arbiter não repassou Ready para M0"
    assert int(dut.m0_rdata_o.value) == 0xAAAA, "Dado corrompido M0"

    dut.s_rdy_i.value = 0
    dut.m0_vld_i.value = 0
    await RisingEdge(dut.clk_i)

    # --- Caso B: DMA (M1) ----------------

    dut.m1_addr_i.value = 0x200
    dut.m1_vld_i.value  = 1

    # Mesma latência registrada
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")

    assert dut.s_vld_o.value == 1
    assert int(dut.s_addr_o.value) == 0x200

    # Wait state do slave
    await RisingEdge(dut.clk_i)

    dut.s_rdy_i.value = 1
    dut.s_rdata_i.value = 0xBBBB

    # Resposta registrada
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")

    assert dut.m1_rdy_o.value == 1, "Arbiter não repassou Ready para M1"
    assert int(dut.m1_rdata_o.value) == 0xBBBB

    dut.s_rdy_i.value = 0
    dut.m1_vld_i.value = 0

    log_success("Acessos Individuais OK")

# -----------------------------------------------------------------------------

@cocotb.test()
async def test_priority_switchover(dut):
    log_header("Teste de Troca de Prioridade (Switchover)")
    await setup_dut(dut)

    dut.m0_addr_i.value = 0xCAFE
    dut.m0_vld_i.value  = 1

    await RisingEdge(dut.clk_i)  # CPU registrado

    dut.m1_addr_i.value = 0xFACE
    dut.m1_vld_i.value  = 1

    await RisingEdge(dut.clk_i)  # CPU ainda esperando

    dut.s_rdy_i.value = 1
    await RisingEdge(dut.clk_i)  # CPU termina
    dut.s_rdy_i.value = 0

    # FSM síncrona > IDLE > GRANT_M1 > saída válida
    await RisingEdge(dut.clk_i)  # IDLE
    await RisingEdge(dut.clk_i)  # GRANT_M1
    await RisingEdge(dut.clk_i)  # saída registrada
    await Timer(1, unit="ns")

    assert dut.s_vld_o.value == 1
    assert int(dut.s_addr_o.value) == 0xFACE, "Arbiter não trocou para DMA"

    dut.s_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.s_rdy_i.value = 0

    dut.m1_vld_i.value = 0

    # FIX: retorno síncrono ao CPU
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")

    assert int(dut.s_addr_o.value) == 0xCAFE, "Arbiter não devolveu para CPU"

    log_success("Switchover DMA/CPU OK")

# -----------------------------------------------------------------------------

@cocotb.test()
async def test_fuzzing_stress(dut):
    log_header("Iniciando Fuzzing (Estresse Randômico)")
    await setup_dut(dut)

    M0_ADDR_BASE = 0x1000
    M1_ADDR_BASE = 0x2000

    m0_grants = 0
    m1_grants = 0

    m0_active = False
    m1_active = False
    slave_busy_counter = 0

    for i in range(1000):

        if not m0_active and random.random() < 0.4:
            dut.m0_vld_i.value = 1
            dut.m0_addr_i.value = M0_ADDR_BASE + i
            m0_active = True

        if not m1_active and random.random() < 0.4:
            dut.m1_vld_i.value = 1
            dut.m1_addr_i.value = M1_ADDR_BASE + i
            m1_active = True

        if slave_busy_counter > 0:
            dut.s_rdy_i.value = 0
            slave_busy_counter -= 1
        else:
            if random.random() < 0.3:
                dut.s_rdy_i.value = 1
                slave_busy_counter = random.randint(0, 3)
            else:
                dut.s_rdy_i.value = 0

        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")

        if dut.s_vld_o.value == 1 and dut.s_rdy_i.value == 1:
            if int(dut.s_addr_o.value) >= M1_ADDR_BASE:
                assert dut.m1_rdy_o.value == 1
                m1_active = False
                m1_grants += 1
            else:
                assert dut.m0_rdy_o.value == 1
                m0_active = False
                m0_grants += 1

    log_success(f"Fuzzing Finalizado. Grants M0: {m0_grants}, Grants M1: {m1_grants}")