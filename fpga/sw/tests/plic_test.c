#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_plic.h"
#include "hal/hal_irq.h"

volatile bool g_uart_irq_fired = false;
volatile char g_rx_char = 0;

// =========================================================
// CALLBACK HANDLER
// =========================================================

void my_uart_handler(void) {

    // Verificação de Segurança:
    // Só tentamos ler se REALMENTE houver dados na FIFO.
    if (hal_uart_kbhit()) {
        g_rx_char = hal_uart_getc(); 
        g_uart_irq_fired = true;
    }

}

// =========================================================
// MAIN
// =========================================================

int main() {

    // 1. Setup Hardware
    hal_uart_init();
    hal_uart_puts("\n\r=== PLIC UART IRQ TEST ===\n\r");

    // 2. Setup Dispatcher
    hal_irq_init(); 

    // 3. Setup Callback
    hal_irq_register(PLIC_SOURCE_UART, my_uart_handler);

    // 4. Setup PLIC
    hal_plic_set_priority(PLIC_SOURCE_UART, 1);
    hal_plic_enable(PLIC_SOURCE_UART);

    // 5. Habilita interrupções
    hal_irq_global_enable(); 

    // 6. Print após habilitar 
    hal_uart_puts(" Sistema Pronto (IRQs ja estao ativas)...\n\r");
    hal_uart_puts(" Pode digitar quando quiser.\n\r");

    while(1) {
        if (g_uart_irq_fired) {
            
            // Snapshot rápido (Seção Crítica mínima)
            hal_irq_global_disable();
            char c = g_rx_char;
            g_uart_irq_fired = false;
            hal_irq_global_enable();
            
            // Processamento pesado (com IRQs ligadas)
            hal_uart_puts(" -> [IRQ] Voce digitou: ");
            hal_uart_putc(c);
            hal_uart_puts("\n\r");
        }
    }

    return 0;

}