#include "hal_uart.h"
#include "memory_map.h"

/* * Implementação da Inicialização
 */
void hal_uart_init(void) {
    /* * O Baud Rate é fixado no hardware (115200 @ 100MHz).
     * Se tivéssemos interrupções, aqui seria o lugar de habilitá-las.
     * Por enquanto, deixamos vazio.
     */
}

/* * Implementação de Escrita (TX)
 */
void hal_uart_putc(char c) {
    /* 1. Polling: Espera o bit TX_BUSY (Bit 0) baixar */
    while (MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_TX_BUSY);

    /* 2. Write: Escreve o caractere no registrador de dados */
    MMIO32(UART_DATA_REG_ADDR) = c;
}

/* * Helper para enviar Strings
 */
void hal_uart_puts(const char *s) {
    while (*s) {
        hal_uart_putc(*s++);
    }
}

/* * Implementação de Verificação de Status (RX Check)
 */
int hal_uart_kbhit(void) {
    /* Verifica se o Bit 1 (RX_VALID) está alto */
    return (MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) ? 1 : 0;
}

/* * Implementação de Leitura (RX) com Handshake
 */
char hal_uart_getc(void) {
    /* 1. Polling: Espera chegar dado (RX_VALID = 1) */
    while ((MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) == 0);

    /* 2. Read (PEEK): Lê o dado que está na "cabeça" da fila */
    /* Cast para char garante que pegamos apenas os 8 bits inferiores */
    char c = (char)MMIO32(UART_DATA_REG_ADDR);

    /* * 3. COMMAND (POP): Avisa o hardware para descartar o byte lido 
     * e avançar para o próximo. Sem isso, leríamos o mesmo 'c' para sempre.
     */
    MMIO32(UART_CTRL_REG_ADDR) = UART_CMD_RX_POP;

    return c;
}