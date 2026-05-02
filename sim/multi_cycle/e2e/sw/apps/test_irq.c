/*
 * Teste Completo de Interrupções (Software, Timer, External)
 * Plataforma: Simulação (test_processor.py)
 */

#include <stdint.h>

// ============================================================================
// ENDEREÇOS DE SIMULAÇÃO
// ============================================================================
#define UART_TX_ADDR        0x10000000
#define IRQ_TRIGGER_ADDR    0x20000000 
#define HALT_ADDR           0x10000008 // Alterei para bater com seu test_processor (0x10000008)

// ============================================================================
// DEFINIÇÕES RISC-V CSR
// ============================================================================
#define CSR_MSTATUS     0x300
#define CSR_MIE         0x304
#define CSR_MTVEC       0x305
#define CSR_MCAUSE      0x342

// Bits MSTATUS
#define MSTATUS_MIE     (1 << 3)

// Bits MIE (Interrupt Enable)
#define MIE_MSIE        (1 << 3)  // Software
#define MIE_MTIE        (1 << 7)  // Timer
#define MIE_MEIE        (1 << 11) // External

// Códigos MCAUSE (Bit 31 = 1 para Interrupção)
#define CAUSE_MSI       0x80000003 // Machine Software Interrupt
#define CAUSE_MTI       0x80000007 // Machine Timer Interrupt
#define CAUSE_MEI       0x8000000B // Machine External Interrupt

// ============================================================================
// GLOBAIS
// ============================================================================
volatile int g_irq_fired = 0;
volatile uint32_t g_mcause_capture = 0;

// ============================================================================
// FUNÇÕES BÁSICAS
// ============================================================================
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

// ============================================================================
// TRAP HANDLER
// ============================================================================
void __attribute__((naked, aligned(4))) irq_handler(void) {
    asm volatile (
        "addi sp, sp, -16 \n\t"
        "sw t0, 0(sp) \n\t"
        "sw t1, 4(sp) \n\t"
        
        // 1. Sinaliza que IRQ ocorreu
        "la t0, g_irq_fired \n\t"
        "li t1, 1 \n\t"
        "sw t1, 0(t0) \n\t"

        // 2. Captura MCAUSE
        "csrr t1, 0x342 \n\t" // mcause
        "la t0, g_mcause_capture \n\t"
        "sw t1, 0(t0) \n\t"

        // 3. Desabilita a interrupção que causou isso no MIE 
        // (Para evitar loop infinito já que o simulador segura o pino alto por um tempo)
        // Lógica simplificada: Desabilita TUDO no MIE temporariamente
        "csrw 0x304, x0 \n\t" 

        "lw t1, 4(sp) \n\t"
        "lw t0, 0(sp) \n\t"
        "addi sp, sp, 16 \n\t"
        "mret"
    );
}

// ============================================================================
// MAIN TEST
// ============================================================================
void test_irq_type(char* name, uint32_t mie_bit, int trigger_code, uint32_t expected_mcause) {
    print_str("\n>>> TESTANDO: "); print_str(name); print_str("\n");

    // Reset Globals
    g_irq_fired = 0;
    g_mcause_capture = 0;

    // 1. Habilita Interrupção Específica (MIE)
    uint32_t mie_val = mie_bit; // Apenas a atual
    asm volatile ("csrw 0x304, %0" :: "r"(mie_val));

    // 2. Garante MSTATUS.MIE = 1
    uint32_t mstatus_val;
    asm volatile ("csrr %0, 0x300" : "=r"(mstatus_val));
    mstatus_val |= MSTATUS_MIE;
    asm volatile ("csrw 0x300, %0" :: "r"(mstatus_val));

    // 3. Solicita Trigger ao Python
    print_str(" -> Solicitando Trigger...\n");
    volatile int *trigger = (int *)IRQ_TRIGGER_ADDR;
    *trigger = trigger_code; 

    // 4. Aguarda
    int timeout = 100000;
    while (g_irq_fired == 0 && timeout > 0) {
        timeout--;
    }

    // 5. Valida
    if (g_irq_fired) {
        print_str(" -> [OK] Handler executado.\n");
        print_str(" -> MCAUSE: "); print_hex(g_mcause_capture);
        
        if (g_mcause_capture == expected_mcause) {
            print_str(" (CORRETO)\n");
        } else {
            print_str(" (ERRADO! Esperado: "); print_hex(expected_mcause); print_str(")\n");
        }
    } else {
        print_str(" -> [FALHA] Timeout! O processador ignorou a interrupcao.\n");
    }
}

int main() {
    print_str("\n=== INICIANDO VALIDACAO DE INTERRUPCOES (CORE LEVEL) ===\n");

    // Configura Vetor
    uint32_t handler_addr = (uint32_t)&irq_handler;
    asm volatile ("csrw 0x305, %0" :: "r"(handler_addr));

    // TESTE 1: Software Interrupt
    // Trigger Python: 2 -> Irq_Software_i = 1 -> MCAUSE esperado: 0x80000003
    test_irq_type("SOFTWARE INTERRUPT (MSI)", MIE_MSIE, 2, CAUSE_MSI);

    // TESTE 2: Timer Interrupt
    // Trigger Python: 1 -> Irq_Timer_i = 1 -> MCAUSE esperado: 0x80000007
    test_irq_type("TIMER INTERRUPT (MTI)", MIE_MTIE, 1, CAUSE_MTI);

    // TESTE 3: External Interrupt
    // Trigger Python: 3 -> Irq_External_i = 1 -> MCAUSE esperado: 0x8000000B
    test_irq_type("EXTERNAL INTERRUPT (MEI)", MIE_MEIE, 3, CAUSE_MEI);

    print_str("\n=== FIM DOS TESTES ===\n");
    
    // Halt Simulation
    volatile int *halt = (int *)HALT_ADDR;
    *halt = 1;
    
    return 0;
}