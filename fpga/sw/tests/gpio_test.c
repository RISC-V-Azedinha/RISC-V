/**
 * @file gpio_test.c
 * @brief Teste e demonstração do GPIO: portas (direção + pino), Pmods, LEDs, chaves, botões com
 *        interrupção, displays de 7 segmentos e LEDs RGB.
 *
 * Fase 1 (autoverificação, resultado pela UART):
 *   - porta de LEDs: OUT, OUTSET, OUTCLR, OUTTGL e leitura de IN;
 *   - Pmods JA..JD como saída: o valor lido de volta no pino (IN) tem de ser o escrito;
 *   - displays e LEDs RGB: escrita e leitura dos registradores.
 * Fase 2 (demonstração, contínua):
 *   - os LEDs seguem as chaves; o display mostra a contagem de botões apertados (interrupção);
 *   - BTNU/BTND mudam a cor dos LEDs RGB; BTNL/BTNR alternam display decimal e segmentos crus.
 */

#include <stdint.h>
#include <stdbool.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_gpio.h"
#include "hal/hal_plic.h"
#include "hal/hal_irq.h"

static void put_hex(uint32_t v, int digits) {
    for (int i = digits - 1; i >= 0; i--) hal_uart_putc("0123456789ABCDEF"[(v >> (4 * i)) & 0xF]);
}

static int g_fails = 0;

static void check(const char *name, uint32_t got, uint32_t expected) {
    hal_uart_puts(got == expected ? " [ OK ] " : " [FAIL] ");
    hal_uart_puts(name);
    if (got != expected) {
        hal_uart_puts(": lido 0x"); put_hex(got, 8);
        hal_uart_puts(", esperado 0x"); put_hex(expected, 8);
        g_fails++;
    }
    hal_uart_puts("\r\n");
}

static void delay(uint32_t n) { for (volatile uint32_t i = 0; i < n; i++); }

// =========================================================
// INTERRUPÇÃO DOS BOTÕES
// =========================================================

static volatile uint32_t g_presses = 0;
static volatile uint32_t g_last_btn = 0;

static void gpio_handler(void) {
    uint32_t flags = hal_gpio_irq_flags(GPIO_BTN);
    hal_gpio_irq_clear(GPIO_BTN, flags);
    if (flags) {
        g_presses++;
        g_last_btn = flags;
    }
}

// =========================================================
// FASE 1: AUTOVERIFICAÇÃO
// =========================================================

static void self_test(void) {
    hal_uart_puts("\r\n=== GPIO: autoverificacao ===\r\n");

    // Porta de LEDs
    hal_gpio_port_write(GPIO_LED, 0x00F0);
    GPIO_REG(GPIO_LED, GPIO_REG_OUTSET) = 0x0003;
    GPIO_REG(GPIO_LED, GPIO_REG_OUTCLR) = 0x0010;
    GPIO_REG(GPIO_LED, GPIO_REG_OUTTGL) = 0x8001;
    check("LEDs: OUT/SET/CLR/TGL", hal_leds_read(), 0x80E2);
    check("LEDs: IN reflete OUT", hal_gpio_port_read(GPIO_LED), 0x80E2);
    check("LEDs: DIR fixo em saida", GPIO_REG(GPIO_LED, GPIO_REG_DIR), 0xFFFF);
    hal_gpio_write(GPIO_LED, 15, 0);
    hal_gpio_toggle(GPIO_LED, 2);
    check("LEDs: pino a pino", hal_leds_read(), 0x00E6);

    // Pmods como saída: o pino é lido de volta pelo buffer de entrada
    static const char *names[] = { "JA", "JB", "JC", "JD" };
    for (int p = GPIO_JA; p <= GPIO_JD; p++) {
        hal_gpio_port_set_dir((gpio_port_t)p, 0xFF);
        for (uint32_t pattern = 0x01; pattern; pattern = (pattern << 1) & 0xFF) {
            hal_gpio_port_write((gpio_port_t)p, pattern ^ 0xA5);
            delay(10);
            if (hal_gpio_port_read((gpio_port_t)p) != (pattern ^ 0xA5)) {
                check(names[p], hal_gpio_port_read((gpio_port_t)p), pattern ^ 0xA5);
                break;
            }
            if (pattern == 0x80) {
                hal_uart_puts(" [ OK ] Pmod "); hal_uart_puts(names[p]); hal_uart_puts(": saida lida de volta\r\n");
            }
        }
        hal_gpio_port_write((gpio_port_t)p, 0);
        hal_gpio_port_set_dir((gpio_port_t)p, 0x00);                 // devolve os pinos (alta impedância)
    }

    // Displays e LEDs RGB
    hal_seg7_write_hex(0x89ABCDEF);
    check("7 segmentos: HEX", SEG7_REG_HEX, 0x89ABCDEF);
    hal_seg7_enable(0xFF);
    check("7 segmentos: EN", SEG7_REG_EN, 0xFF);
    hal_rgb_set(RGB_LD16, 0x12, 0x34, 0x56);
    check("RGB: LD16", RGB_REG(RGB_LD16), 0x123456);

    hal_uart_puts(" Chaves (SW15..0): 0x"); put_hex(hal_switches_read(), 4);
    hal_uart_puts("   Botoes (R L D U): 0x"); put_hex(hal_buttons_read(), 1); hal_uart_puts("\r\n");

    hal_uart_puts(g_fails ? "=== FALHOU: " : "=== PASSOU: ");
    put_hex(g_fails, 2);
    hal_uart_puts(" falha(s) ===\r\n");
}

// =========================================================
// FASE 2: DEMONSTRAÇÃO
// =========================================================

int main(void) {
    hal_uart_init();
    self_test();
    delay(3000000);

    // Interrupção nos 4 botões, na borda de subida (ao apertar)
    hal_irq_init();
    hal_irq_register(PLIC_SOURCE_GPIO, gpio_handler);
    hal_plic_set_priority(PLIC_SOURCE_GPIO, 1);
    hal_plic_enable(PLIC_SOURCE_GPIO);
    for (uint32_t b = 0; b < 4; b++) hal_gpio_irq_enable(GPIO_BTN, b, GPIO_EDGE_RISING);
    hal_irq_global_enable();

    hal_uart_puts("\r\nDemo: LEDs = chaves; display = botoes apertados; U/D = cor; L/R = modo\r\n");

    static const uint8_t colors[][3] = { {255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {200, 120, 0}, {0, 140, 200}, {170, 0, 170} };
    uint32_t color = 0, raw_mode = 0, seen = 0, spin = 0;

    while (1) {
        hal_leds_write(hal_switches_read());

        if (g_presses != seen) {
            seen = g_presses;
            if (g_last_btn & (1u << GPIO_BTN_UP))    color = (color + 1) % 6;
            if (g_last_btn & (1u << GPIO_BTN_DOWN))  color = (color + 5) % 6;
            if (g_last_btn & ((1u << GPIO_BTN_LEFT) | (1u << GPIO_BTN_RIGHT))) raw_mode ^= 1;
            hal_uart_puts(" botao 0x"); put_hex(g_last_btn, 1);
            hal_uart_puts("  total "); put_hex(seen, 4); hal_uart_puts("\r\n");
        }

        hal_rgb_set(RGB_LD16, colors[color][0], colors[color][1], colors[color][2]);
        hal_rgb_set(RGB_LD17, colors[(color + 3) % 6][0], colors[(color + 3) % 6][1], colors[(color + 3) % 6][2]);

        if (raw_mode) {
            // Segmentos crus: um segmento "girando" em cada dígito
            static const uint8_t ring[] = { SEG7_A, SEG7_B, SEG7_C, SEG7_D, SEG7_E, SEG7_F };
            for (uint32_t d = 0; d < 8; d++) hal_seg7_set_raw(d, ring[(spin + d) % 6]);
            hal_seg7_enable(0xFF);
            spin++;
        } else {
            hal_seg7_write_dec(seen);
        }
        delay(400000);
    }
    return 0;
}
