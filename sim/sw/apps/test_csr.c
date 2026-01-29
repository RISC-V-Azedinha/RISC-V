/*
 * Stress Test para RV32I Zicsr
 * Testa: CSRRW, Loop de Traps e Preservação de Contexto
 */

#include <stdint.h>

// Endereços para comunicação com o Testbench (log do Cocotb)
#define UART_TX_ADDR 0x10000000
#define HALT_ADDR    0x80000000

// Variáveis Globais
volatile int g_trap_counter = 0;

// -------------------------------------------------------------------------
// Funções Auxiliares (CONSOLE)
// -------------------------------------------------------------------------

void print_str(const char *str) {
    volatile char *uart = (char *)UART_TX_ADDR;
    while (*str) {
        *uart = *str++;
    }
}

// Imprime em Hexadecimal 
void print_hex(uint32_t val) {
    volatile char *uart = (char *)UART_TX_ADDR;
    print_str("0x");
    
    for (int i = 7; i >= 0; i--) {
        int nibble = (val >> (i * 4)) & 0xF; 
        if (nibble < 10) {
            *uart = nibble + '0';
        } else {
            *uart = nibble - 10 + 'A';
        }
    }
}

// -------------------------------------------------------------------------
// Trap Handler
// -------------------------------------------------------------------------

void __attribute__((naked, aligned(4))) trap_handler(void) {

    // Incrementa o contador global de forma segura
    asm volatile (
        "addi sp, sp, -8 \n\t"
        "sw t0, 0(sp) \n\t"
        "sw t1, 4(sp) \n\t"

        "la t0, g_trap_counter \n\t"
        "lw t1, 0(t0) \n\t"
        "addi t1, t1, 1 \n\t"
        "sw t1, 0(t0) \n\t"

        "lw t1, 4(sp) \n\t"
        "lw t0, 0(sp) \n\t"
        "addi sp, sp, 8 \n\t"

        // MEPC += 4 para pular o ECALL
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

    print_str("\n>>> [STRESS] Iniciando Teste Extremo Zicsr (Hex Mode)...\n");

    // -------------------------------------------------------
    // TESTE 1: Atomicidade do CSRRW
    // -------------------------------------------------------

    print_str(">>> [1/3] Testando Atomic Swap (CSRRW)...\n");
    
    // Escreve padrão 0xAAAA5555
    uint32_t val1 = 0xAAAA5555;
    uint32_t read_back = 0;
    asm volatile ("csrrw x0, 0x341, %0" : : "r"(val1));

    // Escreve 0x12345678 e lê o antigo
    uint32_t val2 = 0x12345678;
    asm volatile ("csrrw %0, 0x341, %1" : "=r"(read_back) : "r"(val2));

    if (read_back == 0xAAAA5555) {
        print_str("    [OK] Leitura retornou valor antigo corretamente.\n");
    } else {
        print_str("    [ERRO] Leitura falhou! Lido: ");
        print_hex(read_back);
        print_str("\n");
        return 1;
    }

    // Verifica persistência
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
    // TESTE 3: Loop de Stress (Ping-Pong)
    // -------------------------------------------------------

    print_str(">>> [3/3] Executando 10 Traps em Loop...\n");
    
    int i;
    int falhas = 0;
    for (i = 0; i < 10; i++) {
        int valor_antes = g_trap_counter;
        
        // Dispara Trap
        asm volatile ("ecall");
        
        if (g_trap_counter != valor_antes + 1) {
            print_str("    [ERRO] Trap falhou na iteracao: ");
            print_hex(i);
            print_str("\n");
            falhas++;
        }
    }

    if (falhas == 0) {
        print_str(">>> [SUCESSO] Todos os 10 traps executados!\n");
        print_str(">>> Contador Final: ");
        print_hex(g_trap_counter);
        print_str("\n");
    } else {
        print_str(">>> [FALHA] Ocorreram erros no loop.\n");
    }

    // Encerra
    volatile int *halt = (int *)HALT_ADDR;
    *halt = 1;
    return 0;
    
}