# Temporizador

O temporizador do CLINT conta os ciclos do relógio de 100 MHz num registrador de 64 bits (`mtime`) e gera uma interrupção quando a contagem alcança o comparador (`mtimecmp`). A HAL o usa para três coisas: medir tempo, esperar e gerar interrupções periódicas. O hardware está descrito em [Exceções e interrupções](../processador/interrupcoes.md).

## Referência

| Função | Uso |
|---|---|
| `hal_timer_get_cycles()` | Ciclos desde o *reset* (64 bits); 100 ciclos = 1 µs |
| `hal_timer_reset()` | Zera a contagem |
| `hal_timer_delay_us(us)`, `hal_timer_delay_ms(ms)` | Espera ativa |
| `hal_timer_set_irq_delta(ciclos)` | Agenda a interrupção para daqui a N ciclos |
| `hal_clint_set_cmp(ciclos)` | Agenda a interrupção para um instante absoluto |
| `hal_timer_irq_ack()` | Cancela a interrupção pendente (comparador no infinito) |

!!! note "Leitura de 64 bits numa CPU de 32"
    `hal_timer_get_cycles` lê a parte alta, a baixa e a alta de novo, e repete se a parte alta mudou no meio: isso evita juntar uma parte baixa que acabou de dar a volta com a parte alta antiga, o que daria um salto de 2³² ciclos (43 s) na medida.

## Exemplo: medir e esperar

```c
#include "hal/hal_uart.h"
#include "hal/hal_gpio.h"
#include "hal/hal_timer.h"

static void print_dec(uint32_t v) {
    char buf[11]; int i = 10; buf[i] = '\0';
    do { buf[--i] = '0' + (v % 10); v /= 10; } while (v);
    hal_uart_puts(&buf[i]);
}

// Mede quantos ciclos uma soma de 1.000 termos leva e pisca os LEDs a 2 Hz.
int main(void) {
    hal_uart_init();

    uint64_t t0 = hal_timer_get_cycles();
    volatile uint32_t acc = 0;
    for (uint32_t i = 0; i < 1000; i++) acc += i;
    uint64_t t1 = hal_timer_get_cycles();

    hal_uart_puts("\r\nSoma de 1000 termos: ");
    print_dec((uint32_t)(t1 - t0));
    hal_uart_puts(" ciclos\r\n");

    while (1) {
        hal_leds_write(0xFFFF); hal_timer_delay_ms(250);
        hal_leds_write(0x0000); hal_timer_delay_ms(250);
    }
}
```

## Exemplo: interrupção periódica

O tratador central da HAL (ver [Interrupções](interrupcoes.md)) atende só as interrupções externas, que passam pelo PLIC. A do temporizador chega direto à CPU, então o programa instala o seu próprio tratador. Reprogramar o comparador já baixa o pedido da interrupção.

```c
#include "hal/hal_gpio.h"
#include "hal/hal_irq.h"
#include "hal/hal_timer.h"

#define TICK (100000000 / 10)    // 100 ms a 100 MHz

static volatile uint32_t ticks = 0;

// O tratador central da HAL atende só interrupções externas; o timer usa um tratador próprio.
void __attribute__((interrupt("machine"))) trap_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));
    if (mcause == 0x80000007) {              // interrupção do temporizador
        ticks++;
        hal_timer_set_irq_delta(TICK);       // agenda o próximo tick (e baixa o pedido atual)
    }
}

int main(void) {
    hal_seg7_enable(0xFF);
    hal_irq_set_handler(trap_handler);
    hal_timer_set_irq_delta(TICK);
    hal_irq_mask_enable(IRQ_M_TIMER);
    hal_irq_global_enable();

    while (1) hal_seg7_write_dec(ticks);     // décimos de segundo desde o início
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_timer.c` e envie-o com `make upload SW=demo_timer`.
