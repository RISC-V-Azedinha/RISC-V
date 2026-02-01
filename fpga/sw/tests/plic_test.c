#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_plic.h"
#include "memory_map.h"

// Definições de CSR
#define CSR_MIE_MEIE    (1 << 11) 
#define CSR_MSTATUS_MIE (1 << 3)  
#define MCAUSE_MEI      0x8000000B 

volatile bool g_uart_irq_fired = false;
volatile char g_rx_char = 0;

// --- Trap Handler ---
void __attribute__((interrupt("machine"))) trap_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    // Verifica se é Interrupção Externa (PLIC)
    if (mcause == MCAUSE_MEI) {
        
        // 1. CLAIM: Pergunta ao PLIC quem chamou
        uint32_t source_id = hal_plic_claim();

        if (source_id == PLIC_SOURCE_UART) {
            // Confia no PLIC
            g_rx_char = hal_uart_getc(); 
            g_uart_irq_fired = true;
        }

        // 2. COMPLETE: Avisa o PLIC que terminamos
        hal_plic_complete(source_id);
    }
}

// --- Main ---
int main() {
    hal_uart_init();
    hal_uart_puts("\n\r=== PLIC + UART INTERRUPT TEST ===\n\r");

    // 1. Inicializa o PLIC
    hal_plic_init();

    // 2. Configura a UART no PLIC
    hal_plic_set_priority(PLIC_SOURCE_UART, 1);
    hal_plic_enable(PLIC_SOURCE_UART); // <--- AQUI "ligamos" a interrupção da UART

    volatile uint32_t prio_readback = PLIC_PRIORITY(PLIC_SOURCE_UART);
    volatile uint32_t enable_readback = PLIC_ENABLE;
    
    hal_uart_puts(" -> DEBUG: Priority set to 1. Readback: ");
    hal_uart_putc(prio_readback + '0'); // Esperado '1'
    hal_uart_puts("\n\r");

    hal_uart_puts(" -> DEBUG: Enable set for UART. Readback: ");
    // Verifica se o bit 1 está aceso
    if (enable_readback & (1 << PLIC_SOURCE_UART)) {
        hal_uart_puts("OK (Bit 1 is HIGH)\n\r");
    } else {
        hal_uart_puts("FAIL (Bit 1 is LOW)\n\r");
    }

    hal_uart_puts(" -> PLIC Configured. Enabling CPU Interrupts...\n\r");

    // 3. Configura CPU
    asm volatile ("csrw mtvec, %0" :: "r"(&trap_handler));
    asm volatile ("csrs mie, %0" :: "r"(CSR_MIE_MEIE));
    asm volatile ("csrs mstatus, %0" :: "r"(CSR_MSTATUS_MIE));

    hal_uart_puts(" -> Waiting for key press (Type anything)...\n\r");

    while(1) {
        if (g_uart_irq_fired) {
            // Desabilita IRQ global brevemente para printar
            asm volatile ("csrc mstatus, %0" :: "r"(CSR_MSTATUS_MIE));
            
            hal_uart_puts(" -> [IRQ] Received: ");
            hal_uart_putc(g_rx_char);
            hal_uart_puts("\n\r");
            
            g_uart_irq_fired = false;
            
            asm volatile ("csrs mstatus, %0" :: "r"(CSR_MSTATUS_MIE));
        }
    }

    return 0;
}