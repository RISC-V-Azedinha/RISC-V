/*
 * Teste de Interrupção de Timer (Simulado)
 * Autor: André Maiolini
 */

#include <stdint.h>

// Endereços de IO Simulado
#define UART_TX_ADDR    0x10000000
#define IRQ_TRIGGER     0x20000000 // Endereço para pedir o trigger ao Python
#define HALT_ADDR       0x80000000

// CSRs
#define CSR_MSTATUS     0x300
#define CSR_MIE         0x304
#define CSR_MTVEC       0x305
#define CSR_MCAUSE      0x342

// Bits
#define MIE_MTIE_BIT    (1 << 7)  // Machine Timer Interrupt Enable
#define MSTATUS_MIE_BIT (1 << 3)  // Machine Interrupt Enable (Global)

volatile int g_irq_counter = 0;
volatile int g_mcause_val = 0;

// -------------------------------------------------------------------------
// Funções Auxiliares
// -------------------------------------------------------------------------
void print_str(const char *str) {
    volatile char *uart = (char *)UART_TX_ADDR;
    while (*str) *uart = *str++;
}

void print_hex(uint32_t val) {
    volatile char *uart = (char *)UART_TX_ADDR;
    print_str("0x");
    for (int i = 7; i >= 0; i--) {
        int nibble = (val >> (i * 4)) & 0xF;
        if (nibble < 10) *uart = nibble + '0';
        else *uart = nibble - 10 + 'A';
    }
}

// -------------------------------------------------------------------------
// Trap Handler
// -------------------------------------------------------------------------
void __attribute__((naked, aligned(4))) irq_handler(void) {
    asm volatile (
        // Salva Contexto
        "addi sp, sp, -16 \n\t"
        "sw t0, 0(sp) \n\t"
        "sw t1, 4(sp) \n\t"
        "sw t2, 8(sp) \n\t"
        
        // --- DEBUG VISUAL ---
        // Escreve '!' (ASCII 33) no console direto do Assembly
        // Assim saberemos INSTANTANEAMENTE se o processador pulou pra cá.
        "li t0, 0x10000000 \n\t"
        "li t1, 33 \n\t"
        "sw t1, 0(t0) \n\t"
        // --------------------

        // Incrementa Contador
        "la t1, g_irq_counter \n\t"
        "lw t2, 0(t1) \n\t"
        "addi t2, t2, 1 \n\t"
        "sw t2, 0(t1) \n\t"

        // Salva MCAUSE (para verificação)
        "csrrw t0, 0x342, x0 \n\t"
        "la t1, g_mcause_val \n\t"
        "sw t0, 0(t1) \n\t"
        
        // Restaura Contexto
        "lw t2, 8(sp) \n\t"
        "lw t1, 4(sp) \n\t"
        "lw t0, 0(sp) \n\t"
        "addi sp, sp, 16 \n\t"

        "mret"
    );
}

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------
int main() {
    print_str("\n>>> [IRQ TEST] Iniciando Configuração...\n");

    // 1. Configurar Vetor (MTVEC)
    uint32_t handler_addr = (uint32_t)&irq_handler;
    asm volatile ("csrrw x0, 0x305, %0" : : "r"(handler_addr));

    // 2. Habilitar Timer (MIE bit 7)
    uint32_t mie_val;
    asm volatile ("csrrw %0, 0x304, x0" : "=r"(mie_val)); 
    mie_val |= MIE_MTIE_BIT;
    asm volatile ("csrrw x0, 0x304, %0" : : "r"(mie_val));

    // 3. Habilitar Global (MSTATUS bit 3)
    uint32_t mstatus_val;
    asm volatile ("csrrw %0, 0x300, x0" : "=r"(mstatus_val));
    mstatus_val |= MSTATUS_MIE_BIT;
    asm volatile ("csrrw x0, 0x300, %0" : : "r"(mstatus_val));

    print_str(">>> Aguardando Trigger...\n");
    
    // Dispara o sinal para o Python
    volatile int *trigger = (int *)IRQ_TRIGGER;
    *trigger = 1; 

    // Loop de espera
    int timeout = 500000;
    while (g_irq_counter == 0 && timeout > 0) {
        timeout--;
    }

    if (g_irq_counter > 0) {
        print_str("\n>>> [SUCESSO] Interrupcao Capturada!\n");
        print_str(">>> MCAUSE: ");
        print_hex(g_mcause_val); 
        print_str("\n");
    } else {
        print_str("\n>>> [FALHA] Timeout. O Handler nao rodou.\n");
    }

    volatile int *halt = (int *)HALT_ADDR;
    *halt = 1;
    return 0;
}