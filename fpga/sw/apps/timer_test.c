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
    hal_uart_puts("\n\r=== TIMER V2 TEST (STRICT MODE) ===\n\r");

    // ------------------------------------------------------------------------
    // 1. Teste de Reset Absoluto (Zero Test)
    // ------------------------------------------------------------------------
    hal_uart_puts("[1] Zero Test (Stop -> Reset -> Peek)... ");
    
    // 1. Garante parado e zerado
    hal_timer_stop();   
    hal_timer_reset();  
    
    // 2. SNAPSHOT 
    // Não usamos hal_timer_get_cycles() aqui porque ela força ENABLE=1.
    // Queremos tirar a foto mantendo o ENABLE=0.

    TIMER_REG_CTRL = TIMER_CMD_SNAPSHOT; // Apenas bit 2 (Enable bit 0 fica off)
    
    uint32_t lo = TIMER_REG_LOW;
    uint32_t hi = TIMER_REG_HIGH;
    uint64_t t0 = ((uint64_t)hi << 32) | lo;
    
    if (t0 == 0) {
        hal_uart_puts("PASS (Cycles=0)\n\r");
    } else {
        hal_uart_puts("FAIL. Cycles="); 
        print_hex64(t0); 
        hal_uart_puts("\n\r");
    }

    // ------------------------------------------------------------------------
    // 2. Teste de Contagem (Run Test)
    // ------------------------------------------------------------------------
    hal_uart_puts("[2] Counting Test... ");
    
    hal_timer_start(); 
    for(volatile int i=0; i<10000; i++); // Queima tempo
    
    uint64_t t1 = hal_timer_get_cycles();
    
    if (t1 > 0) {
        hal_uart_puts("PASS. Cycles=");
        print_dec((uint32_t)t1);
        hal_uart_puts("\n\r");
    } else {
        hal_uart_puts("FAIL (Timer stuck at 0)\n\r");
    }

    // ------------------------------------------------------------------------
    // 3. Teste de Precisão (1 Segundo)
    // ------------------------------------------------------------------------
    hal_uart_puts("[3] Precision Test (1000ms delay)... ");
    
    // Sequência limpa: Stop -> Reset -> Start
    hal_timer_stop();
    hal_timer_reset();
    hal_timer_start(); 
    
    // Como acabamos de resetar, o start é praticamente 0, mas lemos para garantir
    uint64_t start = hal_timer_get_cycles(); 
    hal_timer_delay_ms(1000);                
    uint64_t end = hal_timer_get_cycles();
    
    uint64_t delta = end - start;
    uint32_t expected = 100000000;
    
    hal_uart_puts("\n\r");
    hal_uart_puts("    Start:    "); print_hex64(start); hal_uart_puts("\n\r");
    hal_uart_puts("    End:      "); print_hex64(end);   hal_uart_puts("\n\r");
    hal_uart_puts("    Delta:    "); print_dec((uint32_t)delta); hal_uart_puts("\n\r");
    hal_uart_puts("    Expected: "); print_dec(expected); hal_uart_puts("\n\r");
    
    int32_t error = (int32_t)delta - (int32_t)expected;
    if (error < 0) error = -error;
    
    hal_uart_puts("    Error:    "); print_dec((uint32_t)error); hal_uart_puts(" cycles\n\r");

    // 990 ciclos = 9.9 microssegundos de overhead em 1 segundo.
    // Isso é excelente para um softcore rodando polling em C.
    if (error < 2000) { 
        hal_uart_puts(">>> TIMER CALIBRATED & READY! <<<\n\r");
    } else {
        hal_uart_puts(">>> WARNING: High overhead detected <<<\n\r");
    }

    while(1);
    return 0;
    
}