# GPIO

A HAL do GPIO segue o modelo de um microcontrolador: escolhe-se a **direção** de cada pino e depois se lê ou escreve o pino. Ela cobre os Pmods JA a JD, os LEDs, as chaves, os botões, os *displays* de 7 segmentos e os LEDs RGB. O hardware está descrito em [GPIO](../perifericos/gpio.md).

## Portas e pinos

As portas são `GPIO_JA`, `GPIO_JB`, `GPIO_JC`, `GPIO_JD` (8 pinos, entrada ou saída), `GPIO_LED` (16 pinos, só saída), `GPIO_SW` (16 pinos, só entrada) e `GPIO_BTN` (4 pinos, só entrada). Nos Pmods, o pino *i* da porta é o pino *i* do conector na ordem 1, 2, 3, 4, 7, 8, 9, 10 (os pinos 5 e 11 são GND, e 6 e 12, 3,3 V). Na porta de botões, os pinos são `GPIO_BTN_UP`, `GPIO_BTN_DOWN`, `GPIO_BTN_LEFT` e `GPIO_BTN_RIGHT`; o BTNC é o *reset* do SoC.

## Referência

| Função | Uso |
|---|---|
| `hal_gpio_set_dir(porta, pino, dir)` | Direção de um pino: `GPIO_INPUT` ou `GPIO_OUTPUT` (só tem efeito nos Pmods) |
| `hal_gpio_write(porta, pino, valor)` | Liga ou desliga um pino |
| `hal_gpio_toggle(porta, pino)` | Inverte um pino |
| `hal_gpio_read(porta, pino)` | Lê um pino (0 ou 1) |
| `hal_gpio_port_set_dir(porta, máscara)` | Direção da porta inteira: bit 1 = saída |
| `hal_gpio_port_write(porta, valor)`, `hal_gpio_port_read(porta)` | Escreve ou lê a porta inteira |
| `hal_leds_write(valor)`, `hal_leds_read()` | Os 16 LEDs |
| `hal_switches_read()`, `hal_buttons_read()` | As 16 chaves e os 4 botões |
| `hal_gpio_irq_enable(porta, pino, borda)` | Interrupção na borda `GPIO_EDGE_RISING` ou `GPIO_EDGE_FALLING` |
| `hal_gpio_irq_disable(porta, pino)` | Desabilita a interrupção do pino |
| `hal_gpio_irq_flags(porta)`, `hal_gpio_irq_clear(porta, máscara)` | Lê e limpa as *flags* de borda |
| `hal_seg7_write_hex(valor)`, `hal_seg7_write_dec(valor)` | Mostra um número nos 8 dígitos |
| `hal_seg7_set_raw(dígito, segmentos)` | Segmentos de um dígito (`SEG7_A`...`SEG7_G`, `SEG7_DP`) |
| `hal_seg7_enable(máscara)`, `hal_seg7_off()`, `hal_seg7_set_dp(máscara)` | Dígitos ligados e pontos decimais (após o *reset*, os *displays* ficam apagados) |
| `hal_rgb_set(led, r, g, b)` | Cor de `RGB_LD16` ou `RGB_LD17`, de 0 a 255 por canal |

!!! note "Por que `hal_gpio_write` não lê a porta"
    A função escreve nos registradores `OUTSET` ou `OUTCLR`, que alteram só os bits marcados. Assim, ligar um pino nunca desfaz, por acidente, a escrita que um tratador de interrupção acabou de fazer em outro pino da mesma porta, o que poderia acontecer com uma sequência "lê, altera, escreve".

## Exemplo: chaves, botões, *display* e LED RGB

```c
#include "hal/hal_gpio.h"

// Chaves nos LEDs, contador no display, botões mudam a cor do LED RGB e um LED no Pmod JA pisca.
int main(void) {
    hal_gpio_set_dir(GPIO_JA, 0, GPIO_OUTPUT);    // pino 1 do Pmod JA como saída
    hal_seg7_enable(0xFF);                        // liga os 8 dígitos

    uint32_t count = 0;
    while (1) {
        hal_leds_write(hal_switches_read());      // LEDs espelham as chaves

        if (hal_gpio_read(GPIO_BTN, GPIO_BTN_UP))    hal_rgb_set(RGB_LD16, 255, 0, 0);
        if (hal_gpio_read(GPIO_BTN, GPIO_BTN_DOWN))  hal_rgb_set(RGB_LD16, 0, 0, 255);

        if ((count & 0xFFFF) == 0) hal_gpio_toggle(GPIO_JA, 0);
        hal_seg7_write_dec(count >> 12);
        count++;
    }
}
```

## Exemplo: botão por interrupção

O laço principal só mostra a contagem; quem conta é o tratador, chamado a cada borda de subida do BTNL.

```c
#include "hal/hal_gpio.h"
#include "hal/hal_irq.h"
#include "hal/hal_plic.h"

static volatile uint32_t presses = 0;

// Tratador do GPIO: conta os toques no BTNL e limpa as flags.
static void gpio_handler(void) {
    uint32_t flags = hal_gpio_irq_flags(GPIO_BTN);
    if (flags & (1u << GPIO_BTN_LEFT)) presses++;
    hal_gpio_irq_clear(GPIO_BTN, flags);
}

int main(void) {
    hal_seg7_enable(0xFF);

    hal_irq_init();                                          // PLIC + tratador central
    hal_irq_register(PLIC_SOURCE_GPIO, gpio_handler);
    hal_plic_set_priority(PLIC_SOURCE_GPIO, 1);
    hal_plic_enable(PLIC_SOURCE_GPIO);
    hal_gpio_irq_enable(GPIO_BTN, GPIO_BTN_LEFT, GPIO_EDGE_RISING);
    hal_irq_global_enable();

    while (1) hal_seg7_write_dec(presses);                   // o laço principal só mostra o valor
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_gpio.c` e envie-o com `make upload SW=demo_gpio`.
