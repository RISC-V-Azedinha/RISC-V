#ifndef HAL_UART_H
#define HAL_UART_H

#include <stdint.h>

/*
 * Inicializa o controlador UART.
 * (Neste hardware específico, não há muito o que configurar,
 * mas mantemos a função para portabilidade futura).
 */
void hal_uart_init(void);

/*
 * Envia um único caractere (Blocking).
 * Espera o transmissor ficar livre antes de escrever.
 */
void hal_uart_putc(char c);

/*
 * Envia uma string terminada em nulo (Blocking).
 */
void hal_uart_puts(const char *s);

/*
 * Verifica se há dados disponíveis para leitura.
 * Retorna: 1 se houver dados na FIFO, 0 se estiver vazia.
 */
int hal_uart_kbhit(void);

/*
 * Recebe um único caractere (Blocking).
 * Espera até que um dado chegue, lê o dado e avança a FIFO.
 */
char hal_uart_getc(void);

#endif /* HAL_UART_H */