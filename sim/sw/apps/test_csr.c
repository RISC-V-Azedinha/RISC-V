/*
 * Test para RV32I Zicsr 
 * Testa: Atomic CSRRW, ECALL, EBREAK, Loop de Traps
 */

#include <stdint.h>

// Endereços para comunicação com o Testbench

#define UART_TX_ADDR 0x10000000
#define HALT_ADDR    0x80000000

// Endereços CSR

#define CSR_MTVEC    0x305
#define CSR_MEPC     0x341
#define CSR_MCAUSE   0x342

// Variáveis Globais

volatile int g_trap_counter = 0;
volatile int g_last_mcause = 0;

// -------------------------------------------------------------------------
// Funções Auxiliares (CONSOLE)
// -------------------------------------------------------------------------

void print_str(const char *str) {
    volatile char *uart = (char *)UART_TX_ADDR;
    while (*str) {
        *uart = *str++;
    }
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

void __attribute__((naked, aligned(4))) trap_handler(void) {

    asm volatile (
        "addi sp, sp, -12 \n\t"
        "sw t0, 0(sp) \n\t"
        "sw t1, 4(sp) \n\t"
        "sw t2, 8(sp) \n\t"

        // Incrementa contador global
        "la t0, g_trap_counter \n\t"
        "lw t1, 0(t0) \n\t"
        "addi t1, t1, 1 \n\t"
        "sw t1, 0(t0) \n\t"

        // Salva o MCAUSE para verificarmos no main
        "csrrw t2, 0x342, x0 \n\t" // Lê mcause (e zera, mas ok)
        "la t0, g_last_mcause \n\t"
        "sw t2, 0(t0) \n\t"
        "csrrw x0, 0x342, t2 \n\t" // Restaura mcause 

        // Restaura regs
        "lw t2, 8(sp) \n\t"
        "lw t1, 4(sp) \n\t"
        "lw t0, 0(sp) \n\t"
        "addi sp, sp, 12 \n\t"

        // MEPC += 4
        "csrrw t0, 0x341, x0 \n\t" 
        "addi t0, t0, 4 \n\t"
        "csrrw x0, 0x341, t0 \n\t"

        "mret"
    );

}

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------
int main() {
    print_str("\n>>> [STRESS] Iniciando Teste Zicsr (Hex Mode)...\n");

    // -------------------------------------------------------
    // TESTE 1: Atomicidade do CSRRW
    // -------------------------------------------------------

    print_str(">>> [1/4] Testando Atomic Swap (CSRRW)...\n");
    
    uint32_t val1 = 0xAAAA5555;
    uint32_t read_back = 0;
    asm volatile ("csrrw x0, 0x341, %0" : : "r"(val1));

    uint32_t val2 = 0x12345678;
    asm volatile ("csrrw %0, 0x341, %1" : "=r"(read_back) : "r"(val2));

    if (read_back == 0xAAAA5555) {
        print_str("    [OK] Leitura retornou valor antigo corretamente.\n");
    } else {
        print_str("    [ERRO] Leitura falhou!\n");
        return 1;
    }

    asm volatile ("csrrw %0, 0x341, x0" : "=r"(read_back)); 
    if (read_back == 0x12345678) {
        print_str("    [OK] Escrita persistiu corretamente.\n");
    } else {
        print_str("    [ERRO] Valor novo nao persistiu.\n");
        return 1;
    }

    // -------------------------------------------------------
    // TESTE 2: Configuração do Handler
    // -------------------------------------------------------

    uint32_t handler = (uint32_t)&trap_handler;
    asm volatile ("csrrw x0, 0x305, %0" : : "r"(handler));

    // -------------------------------------------------------
    // TESTE 3: Loop de Stress (ECALL)
    // -------------------------------------------------------

    print_str(">>> [3/4] Executando 10 ECALLs em Loop...\n");
    
    int i;
    int falhas = 0;
    for (i = 0; i < 10; i++) {
        g_last_mcause = 0; // Limpa antes
        int valor_antes = g_trap_counter;
        
        asm volatile ("ecall");
        
        if (g_trap_counter != valor_antes + 1) {
            print_str("    [ERRO] Contador nao subiu.\n");
            falhas++;
        }
        if (g_last_mcause != 11) { // 11 = Machine Ecall
            print_str("    [ERRO] MCAUSE Incorreto para ECALL. Lido: ");
            print_hex(g_last_mcause);
            print_str("\n");
            falhas++;
        }
    }

    if (falhas == 0) {
        print_str(">>> [SUCESSO] ECALLs processadas corretamente (Cause=11)!\n");
    } else {
        print_str(">>> [FALHA] Erros no loop ECALL.\n");
        return 1;
    }

    // -------------------------------------------------------
    // TESTE 4: Teste de Breakpoint (EBREAK)
    // -------------------------------------------------------

    print_str(">>> [4/4] Testando EBREAK...\n");
    g_last_mcause = 0;
    int contador_antes = g_trap_counter;

    asm volatile ("ebreak");

    if (g_trap_counter == contador_antes + 1) {
        if (g_last_mcause == 3) { // 3 = Breakpoint
            print_str(">>> [SUCESSO] EBREAK capturado com MCAUSE=3!\n");
        } else {
            print_str(">>> [FALHA] EBREAK capturado, mas MCAUSE errado: ");
            print_hex(g_last_mcause);
            print_str("\n");
            return 1;
        }
    } else {
        print_str(">>> [FALHA] EBREAK ignorado pelo hardware.\n");
        return 1;
    }

    // Encerra
    volatile int *halt = (int *)HALT_ADDR;
    *halt = 1;
    return 0;

}