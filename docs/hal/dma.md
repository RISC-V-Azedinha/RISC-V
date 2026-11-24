# DMA

O DMA copia blocos de palavras de 32 bits sem a CPU, a perto de uma palavra por ciclo. A HAL oferece a cópia comum, de memória para memória ou para uma porta FIFO, e a leitura de uma porta FIFO para a memória. O hardware está descrito em [Memória e DMA](../soc/memoria-dma.md).

## Referência

| Função | Uso |
|---|---|
| `hal_dma_memcpy(origem, destino, palavras, destino_fixo)` | Copia e **espera o fim**; com `destino_fixo = 1`, escreve sempre no mesmo endereço (uma porta FIFO, como as da NPU) |
| `hal_dma_drain(origem, destino, palavras)` | Lê sempre do mesmo endereço (por exemplo, a saída da NPU) e grava em posições consecutivas |
| `hal_dma_is_busy()` | 1 enquanto há uma transferência em andamento |

Os endereços são físicos, em bytes, e a quantidade é em **palavras**. Para disparar uma transferência sem esperar e ser avisado por interrupção (`PLIC_SOURCE_DMA`), o programa escreve diretamente nos registradores da estrutura `DMA` (`DMA->SRC`, `DMA->DST`, `DMA->CNT` e, por último, `DMA->CTRL = DMA_CTRL_START`), como faz o teste `fpga/sw/tests/dma_irq_test.c`.

## Exemplo: CPU contra DMA

```c
#include "hal/hal_uart.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

#define N 4096
static uint32_t src[N], dst_cpu[N], dst_dma[N];

static void print_dec(uint32_t v) {
    char buf[11]; int i = 10; buf[i] = '\0';
    do { buf[--i] = '0' + (v % 10); v /= 10; } while (v);
    hal_uart_puts(&buf[i]);
}

// Copia 16 KB pela CPU e pelo DMA e compara os tempos.
int main(void) {
    hal_uart_init();
    for (uint32_t i = 0; i < N; i++) src[i] = 0xCAFE0000u + i;

    uint64_t t0 = hal_timer_get_cycles();
    for (uint32_t i = 0; i < N; i++) dst_cpu[i] = src[i];
    uint64_t t1 = hal_timer_get_cycles();
    hal_dma_memcpy((uint32_t)src, (uint32_t)dst_dma, N, 0);   // bloqueia até o fim
    uint64_t t2 = hal_timer_get_cycles();

    uint32_t erros = 0;
    for (uint32_t i = 0; i < N; i++) erros += (dst_dma[i] != src[i]);

    hal_uart_puts("\r\nCPU: "); print_dec((uint32_t)(t1 - t0));
    hal_uart_puts(" ciclos | DMA: "); print_dec((uint32_t)(t2 - t1));
    hal_uart_puts(" ciclos | erros: "); print_dec(erros);
    hal_uart_puts("\r\n");
    while (1);
}
```

Na CPU multiciclo, cada palavra copiada custa um *load*, um *store* e o controle do laço, mais de uma dezena de ciclos; o DMA copia perto de uma palavra por ciclo, e, numa transferência assíncrona, a CPU fica livre durante a cópia.

Para executar, salve o programa em `fpga/sw/apps/demo_dma.c` e envie-o com `make upload SW=demo_dma`.
