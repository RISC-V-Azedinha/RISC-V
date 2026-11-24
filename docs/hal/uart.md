# UART e UART2

O SoC tem duas UARTs: a do **USB**, a 921.600 bit/s, usada pelo bootloader, pelo depurador e pelos programas para falar com o computador; e a **UART2**, a 115.200 bit/s, nos pinos 2 (TX) e 3 (RX) do Pmod JA, para ligar módulos externos, como uma ponte Bluetooth. As duas têm a mesma interface: o envio espera o transmissor ficar livre, e a recepção lê de uma FIFO de 64 bytes. O hardware está descrito em [UART](../perifericos/uart.md).

## Referência

| Função | Uso |
|---|---|
| `hal_uart_init()` | Prepara a UART do USB |
| `hal_uart_putc(c)` | Envia um caractere; espera o transmissor ficar livre |
| `hal_uart_puts(s)` | Envia uma *string* terminada em zero |
| `hal_uart_kbhit()` | Retorna 1 se há um caractere na FIFO de recepção, sem bloquear |
| `hal_uart_getc()` | Espera um caractere, retira-o da FIFO e o devolve |
| `hal_uart2_init()` | Habilita a UART2, descarta a FIFO e toma os pinos 2 e 3 do JA (antes, eles são GPIO) |
| `hal_uart2_disable()` | Desabilita a UART2 e devolve os pinos ao GPIO |
| `hal_uart2_putc`, `hal_uart2_puts`, `hal_uart2_kbhit`, `hal_uart2_getc` | O mesmo que as funções da UART do USB |

!!! tip "Leitura sem bloquear"
    `hal_uart_getc()` só retorna quando chega um caractere. Para um programa que faz outras coisas enquanto espera (um jogo, por exemplo), teste antes com `hal_uart_kbhit()`, ou use a [interrupção da UART](interrupcoes.md#exemplo-recepcao-por-interrupcao).

## Exemplo: eco em maiúsculas

```c
#include "hal/hal_uart.h"

// Eco em maiúsculas: devolve cada letra recebida convertida para maiúscula.
int main(void) {
    hal_uart_init();
    hal_uart_puts("\r\nDigite algo (Enter quebra a linha):\r\n");

    while (1) {
        char c = hal_uart_getc();                 // espera um caractere
        if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
        if (c == '\r') hal_uart_puts("\r\n");
        else           hal_uart_putc(c);
    }
}
```

## Exemplo: ponte entre as duas UARTs

Repassa cada byte de uma UART para a outra; com um módulo Bluetooth no Pmod JA, o computador conversa com o módulo pelo cabo USB da placa.

```c
#include "hal/hal_uart.h"
#include "hal/hal_uart2.h"

// Ponte entre a UART do USB e a UART2 do Pmod JA (por exemplo, para um módulo Bluetooth).
int main(void) {
    hal_uart_init();
    hal_uart2_init();                             // toma os pinos 2 e 3 do JA
    hal_uart_puts("\r\nPonte USB <-> Pmod JA ativa\r\n");

    while (1) {
        if (hal_uart_kbhit())  hal_uart2_putc(hal_uart_getc());
        if (hal_uart2_kbhit()) hal_uart_putc(hal_uart2_getc());
    }
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_uart.c` e envie-o com `make upload SW=demo_uart`.
