#include <stdint.h>
#include "hal/hal_gpio.h"

// =========================================================
// DEFINIÇÕES DE HARDWARE
// =========================================================
#define UART_BASE 0x10000000

#define REG_UART_DATA   (*(volatile uint32_t *)(UART_BASE + 0x00))
#define REG_UART_STATUS (*(volatile uint32_t *)(UART_BASE + 0x04))

#define UART_TX_BUSY    (1 << 0)

// =========================================================
// DRIVERS
// =========================================================
void uart_putc(char c) {
    while (REG_UART_STATUS & UART_TX_BUSY);
    REG_UART_DATA = c;
}

void uart_puts(const char* str) {
    while (*str) {
        uart_putc(*str++);
    }
}

// =========================================================
// MATEMÁTICA (Sem LibGCC)
// =========================================================
void simple_div_mod(uint32_t numerator, uint32_t denominator, uint32_t *quotient, uint32_t *remainder) {
    if (denominator == 0) { *quotient = 0; *remainder = 0; return; }
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r <<= 1;
        r |= (numerator >> i) & 1;
        if (r >= denominator) {
            r -= denominator;
            q |= (1U << i);
        }
    }
    *quotient = q;
    *remainder = r;
}

void print_dec(uint32_t n) {
    if (n == 0) { uart_putc('0'); return; }
    char buffer[12];
    int i = 0;
    uint32_t q, r;
    while (n > 0) {
        simple_div_mod(n, 10, &q, &r);
        buffer[i++] = r + '0';
        n = q;
    }
    while (i > 0) uart_putc(buffer[--i]);
}

// =========================================================
// MAIN
// =========================================================
void main() {
    volatile int i;
    uint32_t t1 = 0, t2 = 1, nextTerm = 0;

    hal_leds_write(0xFFFF);
    for (i = 0; i < 500000; i++);
    hal_leds_write(0x0000);

    uart_puts("\n\r--------------------------------\n\r");
    uart_puts(" FIBONACCI (User App @ 0x800)\n\r");
    uart_puts("--------------------------------\n\r");

    while (1) {
        t1 = 0; t2 = 1;
        uart_puts("Iniciando sequencia:\n\r");
        
        uart_puts("T1: "); print_dec(t1); uart_puts("\n\r");
        uart_puts("T2: "); print_dec(t2); uart_puts("\n\r");

        for (int count = 3; count <= 45; ++count) {
            nextTerm = t1 + t2;
            t1 = t2;
            t2 = nextTerm;

            uart_puts("T"); print_dec(count); uart_puts(": ");
            print_dec(nextTerm); uart_puts("\n\r");

            hal_leds_write(nextTerm & 0xFFFF);                  // LEDs: termo em binário
            hal_seg7_write_dec(nextTerm);                       // display: termo em decimal
            for (i = 0; i < 100000; i++); // Delay menor
        }
        uart_puts("--- Reiniciando a sequência---\n\r");
        for (i = 0; i < 1000000; i++);
    }
}