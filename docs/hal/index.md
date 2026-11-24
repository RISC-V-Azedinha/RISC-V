# Visão geral da HAL

A **HAL** (*Hardware Abstraction Layer*) é a camada de software que esconde os registradores dos periféricos atrás de funções em C. Em vez de escrever num endereço como `0x2000_0104`, o programa chama `hal_leds_write(0x00FF)`. Ela fica em `fpga/sw/platform/bsp/` e é ligada a todo programa compilado para a FPGA.

## Organização

| Arquivo | Conteúdo |
|---|---|
| `memory_map.h` | Endereços base de cada periférico, deslocamentos e bits dos registradores, e as macros `MMIO32` e `MMIO8` |
| `hal/hal_uart.h`, `hal/hal_uart2.h` | [UART do USB e UART2 do Pmod JA](uart.md) |
| `hal/hal_gpio.h` | [GPIO](gpio.md): portas, *displays* de 7 segmentos e LEDs RGB |
| `hal/hal_timer.h` | [Temporizador](temporizador.md) (CLINT): contagem de ciclos, atrasos e interrupção periódica |
| `hal/hal_irq.h`, `hal/hal_plic.h`, `irq/irq_dispatch.c` | [Interrupções](interrupcoes.md): CSRs, PLIC e o tratador central |
| `hal/hal_dma.h` | [DMA](dma.md): cópias de memória e transferências para portas FIFO |
| `hal/hal_vga.h` | [VGA](vga.md): *framebuffer* de 320×240 |
| `hal/hal_npu.h` | [NPU](npu.md): uso básico do acelerador |
| `math_ops.h` | [Aritmética em software](aritmetica.md): multiplicação e divisão sem a extensão M |

## Acesso aos registradores

Todos os periféricos são mapeados em memória, e a HAL os acessa por ponteiros `volatile`:

```c
#define MMIO32(addr) (*(volatile uint32_t *)(addr))
#define MMIO8(addr)  (*(volatile uint8_t  *)(addr))
```

O `volatile` é essencial: ele obriga o compilador a fazer cada leitura e escrita de fato, na ordem do código. Sem ele, o GCC poderia, por exemplo, ler o registrador de estado da UART uma única vez e ficar num laço infinito com o valor guardado num registrador da CPU.

A maior parte das funções é `static inline` no próprio cabeçalho, porque se reduz a um ou dois acessos; as que têm laços (UART, VGA, NPU, DMA) ficam nos arquivos `.c` correspondentes.

## Como usar

1. Inclua o cabeçalho do periférico (`#include "hal/hal_uart.h"`); o diretório da BSP já está no caminho de busca do compilador.
2. Escreva o programa em `fpga/sw/apps/`, `fpga/sw/tests/` ou `fpga/sw/server/`.
3. Compile e envie com `make upload SW=<programa>`. O `makefile` liga automaticamente todos os arquivos da BSP (ver [Compilação e build](../software/build.md)).

Cada página desta seção traz a referência das funções e um programa de demonstração completo, compilado com as mesmas *flags* do `makefile`.
