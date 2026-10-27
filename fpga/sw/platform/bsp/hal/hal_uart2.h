#ifndef HAL_UART2_H
#define HAL_UART2_H

#include <stdint.h>

/*
 * UART2: segunda UART do SoC, nos pinos 2 (TX) e 3 (RX) do Pmod JA (padrão Pmod UART, Tipo 3).
 * Enquanto desabilitada, esses pinos continuam sendo GPIO comuns da porta JA.
 */

/*
 * Habilita a UART2: descarta o que estiver na FIFO e toma os pinos do Pmod JA.
 */
void hal_uart2_init(void);

/*
 * Desabilita a UART2 e devolve os pinos ao GPIO.
 */
void hal_uart2_disable(void);

/*
 * Envia um único caractere (Blocking).
 */
void hal_uart2_putc(char c);

/*
 * Envia uma string terminada em nulo (Blocking).
 */
void hal_uart2_puts(const char *s);

/*
 * Retorna 1 se houver dados na FIFO de recepção, 0 se estiver vazia.
 */
int hal_uart2_kbhit(void);

/*
 * Recebe um único caractere (Blocking).
 */
char hal_uart2_getc(void);

#endif /* HAL_UART2_H */
