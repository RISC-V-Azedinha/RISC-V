# =====================================================================================================================
# File: test_sd_spi.py
# =====================================================================================================================
#
# >>> Descrição: Testbench do mestre SPI do slot de microSD. Um modelo de escravo SPI (modo 0) recebe os bytes
#       enviados pelo controlador e devolve uma fila de bytes programada, para conferir o protocolo bit a bit.
#
# =====================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly, ClockCycles, Edge

from sim.core.single_cycle.include.test_utils import log_header, log_info, log_success, log_error

# =====================================================================================================================
# MAPA DE REGISTRADORES
# =====================================================================================================================

REG_DATA, REG_CTRL, REG_DIV, REG_STATUS = 0x0, 0x4, 0x8, 0xC
CTRL_CS, CTRL_PWR = 1 << 0, 1 << 1
STATUS_BUSY, STATUS_CD = 1 << 0, 1 << 1

# =====================================================================================================================
# BARRAMENTO
# =====================================================================================================================

async def reset_dut(dut):
    dut.rst.value = 1
    dut.vld_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    dut.sd_miso_i.value = 1
    dut.sd_cd_n_i.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def bus_access(dut, address, data=0, write=False):
    dut.addr_i.value = address
    dut.data_i.value = data
    dut.we_i.value = 1 if write else 0
    dut.vld_i.value = 1
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rdy_o.value) == 1:
            value = int(dut.data_o.value)
            break
    await RisingEdge(dut.clk)
    dut.vld_i.value = 0
    dut.we_i.value = 0
    return value

async def bus_write(dut, address, data):
    await bus_access(dut, address, data, write=True)

async def bus_read(dut, address):
    return await bus_access(dut, address)

async def transfer(dut, byte):
    """Envia um byte como o driver faz: escreve DATA, espera BUSY baixar e lê o byte recebido."""
    await bus_write(dut, REG_DATA, byte)
    while await bus_read(dut, REG_STATUS) & STATUS_BUSY:
        pass
    return await bus_read(dut, REG_DATA)

def check(cond, msg):
    if not cond:
        log_error(msg)
        assert False, msg

# =====================================================================================================================
# MODELO DO CARTÃO (ESCRAVO SPI MODO 0)
# =====================================================================================================================

class SpiSlave:
    """Amostra o MOSI na subida do SCK e muda o MISO na descida, como o cartão no modo SPI."""

    def __init__(self, dut):
        self.dut = dut
        self.replies = []                                   # bytes que o cartão devolve (0xFF quando vazio)
        self.bit = 0
        self.received = []                                  # bytes que o cartão recebeu
        self.rise_times = []                                # instantes das subidas do SCK (em ciclos)
        self.cycle = 0
        cocotb.start_soon(self._count_cycles())
        cocotb.start_soon(self._run())

    async def _count_cycles(self):
        while True:
            await RisingEdge(self.dut.clk)
            self.cycle += 1

    def load(self, replies):
        """Programa as próximas respostas; com o cartão entre bytes, o primeiro bit já vai para o MISO."""
        self.replies = list(replies)
        if self.bit == 0:
            self._start_byte()

    def _start_byte(self):
        self.out = self.replies.pop(0) if self.replies else 0xFF
        self.dut.sd_miso_i.value = (self.out >> 7) & 1

    async def _run(self):
        dut = self.dut
        self.bit, rx = 0, 0
        self._start_byte()
        while True:
            await RisingEdge(dut.sd_sck_o)
            self.rise_times.append(self.cycle)
            rx = ((rx << 1) | int(dut.sd_mosi_o.value)) & 0xFF
            await FallingEdge(dut.sd_sck_o)
            self.bit += 1
            if self.bit == 8:
                self.received.append(rx)
                self.bit, rx = 0, 0
                self._start_byte()
            else:
                dut.sd_miso_i.value = (self.out >> (7 - self.bit)) & 1

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_reset(dut):
    """Após o reset: cartão desligado e sem seleção, SCK parado, 400 kHz."""
    log_header("RESET")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    await ReadOnly()
    check(int(dut.sd_reset_o.value) == 1, "o cartão deveria ficar sem alimentação após o reset")
    check(int(dut.sd_cs_n_o.value) == 1, "CS deveria ficar em nível alto após o reset")
    check(int(dut.sd_sck_o.value) == 0, "SCK deveria ficar em nível baixo (SPI modo 0)")
    check(int(dut.sd_mosi_o.value) == 1, "MOSI deveria ficar em nível alto ocioso")
    await RisingEdge(dut.clk)

    check(await bus_read(dut, REG_DIV) == 124, "DIV deveria começar em 124 (400 kHz)")
    check(await bus_read(dut, REG_CTRL) == 0, "CTRL deveria começar em 0")
    check(await bus_read(dut, REG_STATUS) == 0, "STATUS deveria começar sem BUSY e sem cartão")
    log_success("Valores de reset corretos")

@cocotb.test()
async def test_ctrl_and_card_detect(dut):
    """CTRL liga a alimentação e o CS; STATUS.CD segue o pino de detecção (ativo em nível baixo)."""
    log_header("CTRL E DETECÇÃO DO CARTÃO")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    await bus_write(dut, REG_CTRL, CTRL_PWR)
    await ReadOnly()
    check(int(dut.sd_reset_o.value) == 0 and int(dut.sd_cs_n_o.value) == 1, "PWR deveria só alimentar o cartão")
    await RisingEdge(dut.clk)

    await bus_write(dut, REG_CTRL, CTRL_PWR | CTRL_CS)
    await ReadOnly()
    check(int(dut.sd_cs_n_o.value) == 0, "CS deveria ir a nível baixo")
    await RisingEdge(dut.clk)
    check(await bus_read(dut, REG_CTRL) == CTRL_PWR | CTRL_CS, "CTRL deveria ler o valor escrito")

    dut.sd_cd_n_i.value = 0
    await ClockCycles(dut.clk, 4)
    check(await bus_read(dut, REG_STATUS) & STATUS_CD, "CD deveria indicar cartão no slot")
    dut.sd_cd_n_i.value = 1
    await ClockCycles(dut.clk, 4)
    check(not (await bus_read(dut, REG_STATUS) & STATUS_CD), "CD deveria indicar slot vazio")
    log_success("CTRL e detecção do cartão corretos")

@cocotb.test()
async def test_transfer(dut):
    """Um byte em cada sentido, com o SCK no período programado em DIV."""
    log_header("TRANSFERÊNCIA DE UM BYTE")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    card = SpiSlave(dut)

    await bus_write(dut, REG_DIV, 3)
    card.load([0x3C])
    got = await transfer(dut, 0xA5)

    check(card.received == [0xA5], f"o cartão deveria receber 0xA5, recebeu {card.received}")
    check(got == 0x3C, f"o controlador deveria ler 0x3C, leu 0x{got:02X}")
    periods = {b - a for a, b in zip(card.rise_times, card.rise_times[1:])}
    check(periods == {2 * (3 + 1)}, f"o período do SCK deveria ser 8 ciclos, foi {periods}")

    await ReadOnly()
    check(int(dut.sd_sck_o.value) == 0 and int(dut.sd_mosi_o.value) == 1, "SCK e MOSI deveriam voltar ao repouso")
    log_success("Byte enviado e recebido com o SCK correto")

@cocotb.test()
async def test_write_while_busy(dut):
    """Uma escrita em DATA durante a transferência é ignorada."""
    log_header("ESCRITA COM BUSY")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    card = SpiSlave(dut)

    await bus_write(dut, REG_DIV, 5)
    await bus_write(dut, REG_DATA, 0x12)
    check(await bus_read(dut, REG_STATUS) & STATUS_BUSY, "BUSY deveria estar ativo")
    await bus_write(dut, REG_DATA, 0x34)
    while await bus_read(dut, REG_STATUS) & STATUS_BUSY:
        pass
    await ClockCycles(dut.clk, 40)
    check(card.received == [0x12], f"só 0x12 deveria ser enviado, foi {card.received}")
    log_success("Escrita durante a transferência ignorada")

@cocotb.test()
async def test_random_stream(dut):
    """Sequência aleatória de bytes, com divisores diferentes (incluindo o mais rápido, DIV = 1)."""
    log_header("SEQUÊNCIA ALEATÓRIA")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    card = SpiSlave(dut)
    rng = random.Random(1234)

    sent = []
    for div in (1, 2, 4, 9):
        await bus_write(dut, REG_DIV, div)
        replies = [rng.randrange(256) for _ in range(16)]
        card.load(replies)
        for expect in replies:
            byte = rng.randrange(256)
            sent.append(byte)
            got = await transfer(dut, byte)
            check(got == expect, f"DIV={div}: esperado 0x{expect:02X}, lido 0x{got:02X}")
        log_info(f"DIV={div}: 16 bytes conferidos")

    check(card.received == sent, "o cartão deveria receber todos os bytes enviados, na ordem")
    log_success("64 bytes conferidos nos dois sentidos")
