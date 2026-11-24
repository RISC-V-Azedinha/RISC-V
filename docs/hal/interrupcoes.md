# Interrupções

As interrupções passam por dois níveis: o **PLIC** reúne as interrupções dos periféricos e escolhe a de maior prioridade, e a **CPU** decide, pelos seus CSRs, se aceita interromper o programa. A HAL cobre os dois e oferece um **tratador central** que despacha cada interrupção externa para a função registrada pelo programa. O funcionamento está em [Exceções e interrupções](../processador/interrupcoes.md).

## Referência

| Função | Uso |
|---|---|
| `hal_irq_init()` | Inicializa o PLIC, instala o tratador central em `mtvec` e habilita as interrupções externas na CPU |
| `hal_irq_register(fonte, função)` | Registra a função que trata uma fonte do PLIC |
| `hal_irq_global_enable()`, `hal_irq_global_disable()` | Liga e desliga todas as interrupções (`mstatus.MIE`) |
| `hal_irq_mask_enable(máscara)`, `hal_irq_mask_disable(máscara)` | Interrupções aceitas pela CPU: `IRQ_M_EXT`, `IRQ_M_TIMER`, `IRQ_M_SOFT` |
| `hal_irq_set_handler(função)` | Instala um tratador próprio em `mtvec` |
| `hal_plic_set_priority(fonte, p)` | Prioridade de 0 a 7; **0 desabilita a fonte** |
| `hal_plic_enable(fonte)`, `hal_plic_disable(fonte)` | Habilita ou desabilita a fonte no PLIC |
| `hal_plic_set_threshold(t)` | Só interrompe com prioridade maior que `t` |
| `hal_plic_claim()`, `hal_plic_complete(fonte)` | Usados pelo tratador central; só são chamados diretamente num tratador próprio |

As fontes são `PLIC_SOURCE_UART` (1), `PLIC_SOURCE_DMA` (2), `PLIC_SOURCE_NPU` (3), `PLIC_SOURCE_GPIO` (4) e `PLIC_SOURCE_UART2` (5).

## Sequência de configuração

Uma interrupção só chega ao tratador se estiver liberada em todos os níveis, e a ordem recomendada é:

1. `hal_irq_init()`: prepara o PLIC e a CPU;
2. `hal_irq_register(fonte, tratador)`: associa a função;
3. `hal_plic_set_priority(fonte, 1)` e `hal_plic_enable(fonte)`: libera a fonte no PLIC (a prioridade começa em 0, que a desabilita);
4. habilitar a interrupção no próprio periférico (por exemplo, `hal_gpio_irq_enable`);
5. `hal_irq_global_enable()`: por último, para que nada interrompa a configuração pela metade.

O tratador registrado é uma função comum, `void f(void)`: o tratador central faz o *claim* no PLIC, chama a função e faz o *complete*. A função precisa **remover a causa** da interrupção no periférico (ler a FIFO da UART, limpar a *flag* do GPIO); senão, o pedido continua ativo e a interrupção se repete assim que termina. Variáveis compartilhadas com o programa principal devem ser `volatile`.

## Exemplo: recepção por interrupção

```c
#include "hal/hal_uart.h"
#include "hal/hal_gpio.h"
#include "hal/hal_irq.h"
#include "hal/hal_plic.h"

static volatile char last = 0;

// Tratador da UART: retira o caractere da FIFO; sem isso, a interrupção continuaria ativa.
static void uart_handler(void) {
    while (hal_uart_kbhit()) last = hal_uart_getc();
}

int main(void) {
    hal_uart_init();
    hal_irq_init();
    hal_irq_register(PLIC_SOURCE_UART, uart_handler);
    hal_plic_set_priority(PLIC_SOURCE_UART, 1);
    hal_plic_enable(PLIC_SOURCE_UART);
    hal_irq_global_enable();

    while (1) {
        hal_leds_write((uint16_t)last);       // o último caractere recebido, em binário, nos LEDs
    }
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_plic.c` e envie-o com `make upload SW=demo_plic`.
