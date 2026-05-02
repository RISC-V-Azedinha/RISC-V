// File: hello.c
#include <stdint.h>

// Endereços de I/O mapeados no Python (MMIO)
#define UART_TX *((volatile uint32_t *) 0x10000000)
#define SIM_HALT *((volatile uint32_t *) 0x10000008)

void print_char(char c) {
    UART_TX = (uint32_t) c;
}

void print_string(const char *str) {
    while (*str) {
        print_char(*str++);
    }
}

int main() {
    print_string("Iniciando Teste End-to-End...\n");
    print_string("Processador RISC-V funcionando!\n");
    
    // Sinaliza sucesso para o testbench Cocotb
    SIM_HALT = 1; 
    
    return 0;
}