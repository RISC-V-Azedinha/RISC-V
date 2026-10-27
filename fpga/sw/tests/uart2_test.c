/**
 * @file uart2_test.c
 * @brief Teste da UART2 no Pmod JA (pino 2 = TX, pino 3 = RX) e ponte serial USB <-> Pmod.
 *
 * Fase 1 (autoverificação, resultado pela UART do USB):
 *   - com a UART2 desabilitada, o pino 2 do JA obedece ao GPIO;
 *   - com a UART2 habilitada, o mesmo pino passa a ser o TX (em repouso, nível 1), mesmo com o GPIO
 *     tentando escrever 0 nele;
 *   - laço de retorno opcional: com um jumper entre os pinos 2 e 3 do JA, os bytes enviados voltam;
 *   - ao desabilitar, o pino volta ao GPIO.
 * Fase 2 (contínua): ponte transparente. O que chega pelo USB sai pela UART2 (ex.: ESP32 -> Bluetooth),
 * e o que chega pela UART2 sai pelo USB.
 */

#include <stdint.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_uart2.h"
#include "hal/hal_gpio.h"

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

// Laço de retorno: devolve quantos dos bytes enviados voltaram iguais (0 = sem jumper)
static int loopback(void) {
    static const char msg[] = "UART2";
    int ok = 0;
    for (int i = 0; msg[i]; i++) {
        hal_uart2_putc(msg[i]);
        uint32_t t = 0;
        while (!hal_uart2_kbhit() && t < 20000) t++;       // ~2 bytes a 115200 bps
        if (hal_uart2_kbhit() && hal_uart2_getc() == msg[i]) ok++;
    }
    return ok;
}

int main(void) {
    hal_uart_init();
    hal_uart_puts("\r\n=== UART2 no Pmod JA (pino 2 = TX, pino 3 = RX) ===\r\n");

    // --- Fase 1: quem manda no pino ---------------------------------------------------------------
    check("EN comeca em 0", MMIO32(UART2_EN_REG_ADDR) & UART_EN, 0);

    hal_gpio_set_dir(GPIO_JA, UART2_PIN_TX, GPIO_OUTPUT);
    hal_gpio_write(GPIO_JA, UART2_PIN_TX, 0);
    delay(10);
    check("UART2 desabilitada: GPIO escreve 0 no pino 2", hal_gpio_read(GPIO_JA, UART2_PIN_TX), 0);
    hal_gpio_write(GPIO_JA, UART2_PIN_TX, 1);
    delay(10);
    check("UART2 desabilitada: GPIO escreve 1 no pino 2", hal_gpio_read(GPIO_JA, UART2_PIN_TX), 1);

    hal_gpio_write(GPIO_JA, UART2_PIN_TX, 0);              // O GPIO continua pedindo 0...
    hal_uart2_init();
    delay(10);
    check("EN = 1 apos hal_uart2_init", MMIO32(UART2_EN_REG_ADDR) & UART_EN, 1);
    check("UART2 habilitada: pino 2 e o TX em repouso (1)", hal_gpio_read(GPIO_JA, UART2_PIN_TX), 1);

    int lb = loopback();
    if (lb == 0) {
        hal_uart_puts(" [ -- ] Laco de retorno: nada voltou (sem jumper entre os pinos 2 e 3; ok)\r\n");
    } else {
        check("Laco de retorno (jumper entre os pinos 2 e 3)", (uint32_t)lb, 5);
    }

    hal_uart2_disable();
    delay(10);
    check("UART2 desabilitada de novo: pino 2 volta ao GPIO (0)", hal_gpio_read(GPIO_JA, UART2_PIN_TX), 0);
    hal_gpio_set_dir(GPIO_JA, UART2_PIN_TX, GPIO_INPUT);

    hal_uart_puts(g_fails ? ">>> FALHOU\r\n" : ">>> TUDO OK\r\n");

    // --- Fase 2: ponte USB <-> UART2 --------------------------------------------------------------
    hal_uart2_init();
    hal_uart2_puts("SoC RISC-V conectado pela UART2\r\n");
    hal_uart_puts("Ponte ativa: o que for digitado aqui sai pelo Pmod JA, e vice-versa.\r\n");

    while (1) {
        if (hal_uart_kbhit())  hal_uart2_putc(hal_uart_getc());
        if (hal_uart2_kbhit()) hal_uart_putc(hal_uart2_getc());
    }
}
