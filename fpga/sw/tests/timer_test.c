#include <stdint.h>
#include "hal/hal_uart.h"
#include "hal/hal_timer.h"

// Helpers de Impressão
void print_dec(uint32_t n) {
    if (n == 0) { hal_uart_putc('0'); return; }
    char buffer[12];
    int i = 0;
    while (n > 0) { buffer[i++] = (n % 10) + '0'; n /= 10; }
    while (i > 0) hal_uart_putc(buffer[--i]);
}

void print_hex64(uint64_t n) {
    hal_uart_puts("0x");
    char hex[] = "0123456789ABCDEF";
    for (int i = 60; i >= 0; i -= 4) hal_uart_putc(hex[(n >> i) & 0xF]);
}

int main() {
    hal_uart_init();
    hal_uart_puts("\n\r=== CLINT TIMER TEST (CLEAN API) ===\n\r");

    // ------------------------------------------------------------------------
    // 1. Teste de Reset (Zero Test)
    // ------------------------------------------------------------------------
    hal_uart_puts("[1] Reset Test... ");
    
    hal_timer_reset(); 
    uint64_t t0 = hal_timer_get_cycles();
    
    if (t0 < 200) {
        hal_uart_puts("PASS (Cycles ~ 0)\n\r");
    } else {
        hal_uart_puts("FAIL. Cycles="); print_hex64(t0); hal_uart_puts("\n\r");
    }

    // ------------------------------------------------------------------------
    // 2. Teste de Contagem (Run Test)
    // ------------------------------------------------------------------------
    hal_uart_puts("[2] Counting Test... ");
    
    uint64_t t_start = hal_timer_get_cycles();
    for(volatile int i=0; i<10000; i++); // Queima tempo
    uint64_t t_end = hal_timer_get_cycles();
    
    if (t_end > t_start) {
        hal_uart_puts("PASS. Delta=");
        print_dec((uint32_t)(t_end - t_start));
        hal_uart_puts("\n\r");
    } else {
        hal_uart_puts("FAIL (Timer stuck)\n\r");
    }

    // ------------------------------------------------------------------------
    // 3. Teste de Precisão (1 Segundo)
    // ------------------------------------------------------------------------
    hal_uart_puts("[3] Precision Test (1000ms delay)... ");
    
    hal_timer_reset();
    uint64_t start = hal_timer_get_cycles(); 
    hal_timer_delay_ms(1000);                
    uint64_t end = hal_timer_get_cycles();
    
    uint64_t delta = end - start;
    uint32_t expected = 100000000; // 100 MHz * 1s
    
    hal_uart_puts("\n\r");
    hal_uart_puts("    Start:    "); print_hex64(start); hal_uart_puts("\n\r");
    hal_uart_puts("    End:      "); print_hex64(end);   hal_uart_puts("\n\r");
    hal_uart_puts("    Delta:    "); print_dec((uint32_t)delta); hal_uart_puts("\n\r");
    hal_uart_puts("    Expected: "); print_dec(expected); hal_uart_puts("\n\r");
    
    int32_t error = (int32_t)delta - (int32_t)expected;
    if (error < 0) error = -error;
    
    hal_uart_puts("    Error:    "); print_dec((uint32_t)error); hal_uart_puts(" cycles\n\r");

    if (error < 5000) { 
        hal_uart_puts(">>> TIMER CALIBRATED & READY! <<<\n\r");
    } else {
        hal_uart_puts(">>> WARNING: High overhead detected <<<\n\r");
    }

    while(1);
    return 0;
}