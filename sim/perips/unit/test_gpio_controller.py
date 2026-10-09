# =====================================================================================================================
# File: test_gpio_controller.py
# =====================================================================================================================
#
# >>> Descrição: Testbench do Controlador de GPIO (portas no estilo de microcontrolador, displays de 7 segmentos
#       e PWM dos LEDs RGB). Usa o gpio_controller_wrapper, com filtro de 4 ciclos, varredura de 8 ciclos por
#       dígito e PWM sem prescaler, para não esperar milissegundos.
#
# =====================================================================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles

from sim.core.single_cycle.include.test_utils import log_header, log_info, log_success, log_error

# =====================================================================================================================
# MAPA DE REGISTRADORES
# =====================================================================================================================

PORT_JA, PORT_JB, PORT_JC, PORT_JD, PORT_LED, PORT_SW, PORT_BTN = range(7)
REG_IN, REG_OUT, REG_DIR, REG_SET, REG_CLR, REG_TGL, REG_IE, REG_IES, REG_IFG = (4 * i for i in range(9))

SEG_BASE, RGB_BASE = 0x200, 0x280
SEG_CTRL, SEG_HEX, SEG_RAW_LO, SEG_RAW_HI, SEG_DP, SEG_EN = (4 * i for i in range(6))

HEX7 = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71]

def port_addr(port, reg):
    return 0x40 * port + reg

# =====================================================================================================================
# BARRAMENTO
# =====================================================================================================================

async def reset_dut(dut):
    dut.rst.value = 1
    dut.vld_i.value = 0
    dut.we_i.value = 0
    dut.addr_i.value = 0
    dut.data_i.value = 0
    for sig in (dut.ja_i, dut.jb_i, dut.jc_i, dut.jd_i, dut.gpio_sw, dut.gpio_btn):
        sig.value = 0
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

def check(cond, msg):
    if not cond:
        log_error(msg)
        assert False, msg

# =====================================================================================================================
# TESTES
# =====================================================================================================================

@cocotb.test()
async def test_reset_state(dut):
    """Após o reset: LEDs apagados, Pmods em alta impedância, displays e RGB apagados."""
    log_header("GPIO: estado após o reset")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    await ClockCycles(dut.clk, 20)
    await ReadOnly()
    check(int(dut.gpio_leds.value) == 0, "LEDs deveriam estar apagados")
    for oe in (dut.ja_oe_o, dut.jb_oe_o, dut.jc_oe_o, dut.jd_oe_o):
        check(int(oe.value) == 0, "Pmods deveriam estar como entrada (alta impedância)")
    check(int(dut.an_n_o.value) == 0xFF, "Displays deveriam estar apagados (EN = 0)")
    check(int(dut.rgb0_o.value) == 0 and int(dut.rgb1_o.value) == 0, "LEDs RGB deveriam estar apagados")
    check(int(dut.irq_o.value) == 0, "Sem interrupção após o reset")
    await RisingEdge(dut.clk)
    log_success("Estado de reset correto")

@cocotb.test()
async def test_led_port(dut):
    """Porta de LEDs: OUT, OUTSET, OUTCLR, OUTTGL; DIR fixo em saída; IN lê o próprio OUT."""
    log_header("GPIO: porta de LEDs")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    await bus_write(dut, port_addr(PORT_LED, REG_OUT), 0x00F0)
    await bus_write(dut, port_addr(PORT_LED, REG_SET), 0x0003)
    await bus_write(dut, port_addr(PORT_LED, REG_CLR), 0x0010)
    await bus_write(dut, port_addr(PORT_LED, REG_TGL), 0x8001)
    expected = ((0x00F0 | 0x0003) & ~0x0010) ^ 0x8001
    await ReadOnly()
    check(int(dut.gpio_leds.value) == expected, f"LEDs: esperado 0x{expected:04X}, obtido 0x{int(dut.gpio_leds.value):04X}")
    await RisingEdge(dut.clk)
    check(await bus_read(dut, port_addr(PORT_LED, REG_OUT)) == expected, "Leitura de OUT")
    check(await bus_read(dut, port_addr(PORT_LED, REG_IN)) == expected, "IN da porta de LEDs deveria refletir OUT")
    await bus_write(dut, port_addr(PORT_LED, REG_DIR), 0)
    check(await bus_read(dut, port_addr(PORT_LED, REG_DIR)) == 0xFFFF, "DIR dos LEDs deveria ser fixo em saída")
    log_success("Porta de LEDs correta")

@cocotb.test()
async def test_pmod_direction(dut):
    """Pmods: direção por pino, saída só nos pinos de saída, leitura dos pinos externos."""
    log_header("GPIO: Pmods (direção + pino)")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    ports = [(PORT_JA, dut.ja_i, dut.ja_o, dut.ja_oe_o), (PORT_JB, dut.jb_i, dut.jb_o, dut.jb_oe_o),
             (PORT_JC, dut.jc_i, dut.jc_o, dut.jc_oe_o), (PORT_JD, dut.jd_i, dut.jd_o, dut.jd_oe_o)]
    for port, pin_i, pin_o, pin_oe in ports:
        dir_mask, out_val, ext_val = random.randrange(256), random.randrange(256), random.randrange(256)
        await bus_write(dut, port_addr(port, REG_DIR), dir_mask)
        await bus_write(dut, port_addr(port, REG_OUT), out_val)
        pin_i.value = ext_val
        await ClockCycles(dut.clk, 4)
        await ReadOnly()
        check(int(pin_oe.value) == dir_mask, f"Porta {port}: OE esperado 0x{dir_mask:02X}")
        check(int(pin_o.value) == out_val, f"Porta {port}: saída esperada 0x{out_val:02X}")
        await RisingEdge(dut.clk)
        check(await bus_read(dut, port_addr(port, REG_IN)) == ext_val, f"Porta {port}: IN deveria ler os pinos")
        check(await bus_read(dut, port_addr(port, REG_DIR)) == dir_mask, f"Porta {port}: leitura de DIR")
    log_success("Pmods corretos")

@cocotb.test()
async def test_switch_debounce(dut):
    """Chaves: um repique mais curto que o filtro não chega a IN; um nível estável chega."""
    log_header("GPIO: filtro das chaves")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    dut.gpio_sw.value = 0x0001
    await ClockCycles(dut.clk, 2)
    dut.gpio_sw.value = 0x0000
    await ClockCycles(dut.clk, 30)
    check(await bus_read(dut, port_addr(PORT_SW, REG_IN)) == 0, "Repique curto não deveria aparecer em IN")
    dut.gpio_sw.value = 0xA5C3
    await ClockCycles(dut.clk, 30)
    check(await bus_read(dut, port_addr(PORT_SW, REG_IN)) == 0xA5C3, "Nível estável deveria aparecer em IN")
    log_success("Filtro das chaves correto")

@cocotb.test()
async def test_button_interrupt(dut):
    """Botões: IFG marca a borda escolhida em IES, irq_o sobe com IE, e escrever 1 em IFG limpa."""
    log_header("GPIO: interrupção dos botões")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    await bus_write(dut, port_addr(PORT_BTN, REG_IFG), 0xF)
    await bus_write(dut, port_addr(PORT_BTN, REG_IES), 0b0100)          # BTNL na descida, os demais na subida
    await bus_write(dut, port_addr(PORT_BTN, REG_IE), 0b0101)           # BTNU e BTNL habilitados

    dut.gpio_btn.value = 0b0010                                         # BTND: flag sem interrupção (IE = 0)
    await ClockCycles(dut.clk, 30)
    check(await bus_read(dut, port_addr(PORT_BTN, REG_IFG)) == 0b0010, "BTND deveria marcar IFG")
    check(int(dut.irq_o.value) == 0, "BTND não deveria interromper (IE = 0)")

    dut.gpio_btn.value = 0b0011                                         # BTNU: subida, habilitado
    await ClockCycles(dut.clk, 30)
    check(int(dut.irq_o.value) == 1, "BTNU deveria interromper")
    await bus_write(dut, port_addr(PORT_BTN, REG_IFG), 0b0011)
    await ReadOnly()
    check(int(dut.irq_o.value) == 0, "Escrever 1 em IFG deveria limpar a interrupção")
    await RisingEdge(dut.clk)

    dut.gpio_btn.value = 0b0111                                         # BTNL subindo: IES = descida, nada
    await ClockCycles(dut.clk, 30)
    check(int(dut.irq_o.value) == 0, "BTNL subindo não deveria interromper (IES = descida)")
    dut.gpio_btn.value = 0b0011                                         # BTNL descendo
    await ClockCycles(dut.clk, 30)
    check(int(dut.irq_o.value) == 1, "BTNL descendo deveria interromper")
    check(await bus_read(dut, port_addr(PORT_BTN, REG_IFG)) == 0b0100, "Só BTNL deveria estar em IFG")
    log_success("Interrupções dos botões corretas")

async def capture_digits(dut, cycles=80):
    """Observa a varredura e devolve {dígito: (segmentos acesos, dp aceso)} dos dígitos ligados."""
    seen = {}
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        an = int(dut.an_n_o.value)
        if an != 0xFF:
            digit = (~an & 0xFF).bit_length() - 1
            check(bin(~an & 0xFF).count("1") == 1, "Só um dígito pode estar aceso por vez")
            seen[digit] = ((~int(dut.seg_n_o.value)) & 0x7F, int(dut.dp_n_o.value) == 0)
    return seen

@cocotb.test()
async def test_seven_segment(dut):
    """Displays: modo HEX com DP e máscara de dígitos; modo de segmentos crus."""
    log_header("GPIO: displays de 7 segmentos")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    await bus_write(dut, SEG_BASE + SEG_HEX, 0x89ABCDEF)
    await bus_write(dut, SEG_BASE + SEG_DP, 0b00000010)
    await bus_write(dut, SEG_BASE + SEG_EN, 0b00001111)
    seen = await capture_digits(dut)
    await RisingEdge(dut.clk)
    check(sorted(seen) == [0, 1, 2, 3], f"Só os dígitos 0..3 deveriam acender, vistos: {sorted(seen)}")
    for d, nib in zip(range(4), [0xF, 0xE, 0xD, 0xC]):
        check(seen[d][0] == HEX7[nib], f"Dígito {d}: segmentos de {nib:X} incorretos")
        check(seen[d][1] == (d == 1), f"Dígito {d}: ponto decimal incorreto")

    await bus_write(dut, SEG_BASE + SEG_RAW_LO, 0x00000049)                # dígito 0: segmentos a, d, g
    await bus_write(dut, SEG_BASE + SEG_RAW_HI, 0x80000000)                # dígito 7: só o ponto
    await bus_write(dut, SEG_BASE + SEG_EN, 0b10000001)
    await bus_write(dut, SEG_BASE + SEG_CTRL, 1)
    seen = await capture_digits(dut)
    await RisingEdge(dut.clk)
    check(sorted(seen) == [0, 7], "Só os dígitos 0 e 7 deveriam acender")
    check(seen[0] == (0x49, False), "Dígito 0 em modo cru incorreto")
    check(seen[7] == (0x00, True), "Dígito 7 em modo cru incorreto")
    check(await bus_read(dut, SEG_BASE + SEG_HEX) == 0x89ABCDEF, "Leitura de HEX")
    log_success("Displays corretos")

@cocotb.test()
async def test_rgb_pwm(dut):
    """LEDs RGB: o ciclo de trabalho segue o brilho, em 2048 passos (brilho máximo = 1/8 do LED direto)."""
    log_header("GPIO: PWM dos LEDs RGB")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    await bus_write(dut, RGB_BASE + 0, 0x00FF8000)                         # LD16: R = 255, G = 128, B = 0
    await bus_write(dut, RGB_BASE + 4, 0x00000040)                         # LD17: B = 64
    on = [0] * 6
    for _ in range(2048):
        await RisingEdge(dut.clk)
        await ReadOnly()
        bits = int(dut.rgb0_o.value) | (int(dut.rgb1_o.value) << 3)
        for c in range(6):
            on[c] += (bits >> c) & 1
    await RisingEdge(dut.clk)
    duty = on                                                           # ciclos acesos num período de 2048
    log_info(f"Ciclos acesos em 2048: {duty}")
    check(abs(duty[0] - 255) <= 2 and abs(duty[1] - 128) <= 2 and duty[2] == 0, "PWM do LD16 incorreto")
    check(duty[3] == 0 and duty[4] == 0 and abs(duty[5] - 64) <= 2, "PWM do LD17 incorreto")
    check(await bus_read(dut, RGB_BASE + 0) == 0xFF8000, "Leitura do RGB0")
    log_success("PWM correto")

@cocotb.test()
async def test_random_stress(dut):
    """Escritas e leituras aleatórias nas portas, comparadas com um modelo."""
    log_header("GPIO: stress aleatório")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    model = {p: {"out": 0, "dir": 0} for p in (PORT_JA, PORT_JB, PORT_JC, PORT_JD, PORT_LED)}
    for i in range(300):
        port = random.choice(list(model))
        width = 0xFFFF if port == PORT_LED else 0xFF
        reg = random.choice([REG_OUT, REG_SET, REG_CLR, REG_TGL, REG_DIR])
        val = random.randrange(0x10000)
        await bus_write(dut, port_addr(port, reg), val)
        m = model[port]
        if reg == REG_OUT: m["out"] = val & width
        elif reg == REG_SET: m["out"] |= val & width
        elif reg == REG_CLR: m["out"] &= ~val & width
        elif reg == REG_TGL: m["out"] ^= val & width
        elif reg == REG_DIR: m["dir"] = val & width
        got = await bus_read(dut, port_addr(port, REG_OUT))
        check(got == m["out"], f"Iter {i}: OUT da porta {port} esperado 0x{m['out']:X}, lido 0x{got:X}")
    check(await bus_read(dut, 0x3C0) == 0, "Endereço sem bloco deveria ler 0")
    log_success("300 operações aleatórias corretas")
