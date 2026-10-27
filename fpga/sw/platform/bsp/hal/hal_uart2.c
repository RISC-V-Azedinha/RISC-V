#include "hal_uart2.h"
#include "memory_map.h"

void hal_uart2_init(void) {
    /* Descarta o que chegou antes e só então toma os pinos do Pmod */
    MMIO32(UART2_CTRL_REG_ADDR) = UART_CMD_RX_FLUSH;
    MMIO32(UART2_EN_REG_ADDR)   = UART_EN;
}

void hal_uart2_disable(void) {
    /* Espera o último byte sair antes de devolver o pino de TX ao GPIO */
    while (MMIO32(UART2_CTRL_REG_ADDR) & UART_STATUS_TX_BUSY);
    MMIO32(UART2_EN_REG_ADDR) = 0;
}

void hal_uart2_putc(char c) {
    while (MMIO32(UART2_CTRL_REG_ADDR) & UART_STATUS_TX_BUSY);
    MMIO32(UART2_DATA_REG_ADDR) = c;
}

void hal_uart2_puts(const char *s) {
    while (*s) {
        hal_uart2_putc(*s++);
    }
}

int hal_uart2_kbhit(void) {
    return (MMIO32(UART2_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) ? 1 : 0;
}

char hal_uart2_getc(void) {
    while ((MMIO32(UART2_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) == 0);
    char c = (char)MMIO32(UART2_DATA_REG_ADDR);
    MMIO32(UART2_CTRL_REG_ADDR) = UART_CMD_RX_POP;
    return c;
}
