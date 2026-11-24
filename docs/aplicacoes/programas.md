# Programas e testes

Os programas do SoC executam em ***bare-metal***: não há sistema operacional, e cada programa controla diretamente a memória e os periféricos, pelos registradores mapeados em memória. O acesso é feito pela HAL de `fpga/sw/platform/bsp/hal/`, uma camada fina de funções que encapsula os registradores de cada periférico (`hal_uart_puts`, `hal_vga_plot`, `hal_leds_write`...).

## Estrutura de um programa

O código de inicialização (`start.s`) prepara a pilha, zera a `.bss` e chama a `main`; o programa, então, inicializa os periféricos que usa e entra num laço infinito (*superloop*):

```c
#include "hal/hal_uart.h"

int main(void) {
    hal_uart_init();
    hal_uart_puts("Ola, RISC-V!\r\n");

    while (1) {
        if (hal_uart_kbhit())                  // chegou um caractere?
            hal_uart_putc(hal_uart_getc());    // devolve o mesmo caractere
    }
}
```

O programa é ligado a partir de `0x8000_0800`, depois da área reservada ao bootloader na RAM (ver [Linker scripts](../software/linker.md)), e enviado à placa com:

```bash
make upload SW=<programa>
```

## Programas de exemplo (`fpga/sw/apps/`)

| Programa | O que faz | Periféricos |
|---|---|---|
| `blink` | Pisca um LED ligado ao pino 1 do Pmod JA; com o botão BTNU pressionado, o LED fica aceso | GPIO (Pmod) |
| `demo` | Demonstração para gravar no cartão: animações nos *displays* de 7 segmentos, arco-íris nos LEDs RGB e "Knight Rider" nos LEDs; os botões trocam a animação e a velocidade | GPIO |
| `uart_echo` | Devolve cada caractere recebido pela UART | UART |
| `fibonacci` | Imprime a sequência de Fibonacci pela UART | UART |
| `fractal` | Desenha o conjunto de Mandelbrot na tela, com aritmética de ponto fixo Q10 (o RV32I não tem ponto flutuante) | VGA |
| `pong` | Jogo de *pong* na tela, controlado pelo teclado do computador (`a` e `d`) pela UART | VGA, UART |
| `benchmark` | Mede a NPU isolada: transferência por escrita da CPU (PIO) contra DMA, e reuso de dados contra sem reuso | NPU, DMA, CLINT |

## Testes na placa (`fpga/sw/tests/`)

Cada teste exercita um bloco do SoC no hardware real e informa o resultado pela UART:

| Teste | O que verifica |
|---|---|
| `gpio_test` | LEDs, chaves, botões, *displays*, LEDs RGB e os pinos dos Pmods |
| `uart2_test` | A segunda UART no Pmod JA, com laço de retorno |
| `vga_test` | Escrita e leitura da memória de vídeo |
| `timer_test`, `clint_test` | O temporizador e a interrupção de software do CLINT |
| `plic_test` | O controlador de interrupções externas |
| `dma_test`, `dma_irq_test` | Cópias por DMA e a interrupção de fim de transferência |
| `npu_test`, `npu_irq_test` | Operações da NPU, conferidas contra a CPU, e a sua interrupção |
| `debug_test` | O controlador de depuração |

## Servidores da NPU (`fpga/sw/server/`)

Os servidores mantêm o SoC atendendo um cliente no computador: recebem modelos e dados pela UART, executam na NPU e devolvem os resultados. Eles estão descritos em [Servidores da NPU](servidores-npu.md).
