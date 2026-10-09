/**
 * @file blink.c
 * @brief Blink: um LED ligado a um pino do Pmod JA pisca; enquanto o push button estiver pressionado,
 *        o LED fica aceso.
 *
 * Ligação do LED (Pmod JA):
 *
 *     pino 1 (JA[0]) ──[ resistor 220-330 Ω ]──►|── pino 5 (GND)
 *                                             LED
 *
 * Push button: por padrão, o BTNU da placa (já tem filtro de repique, não precisa de fio).
 * Para usar um botão externo no pino 2 do Pmod JA, defina BUTTON_EXTERNAL. O pino flutua
 * em nível alto quando solto, então o botão precisa de um resistor de pull-down:
 *
 *     pino 6 (3,3 V) ──[ botão ]──┬── pino 2 (JA[1])
 *                                └──[ 10 kΩ ]── pino 5 (GND)
 *
 * O LD0 da placa acompanha o LED externo, para dar para ver o programa funcionando sem montar nada.
 */

#include <stdint.h>
#include "hal/hal_gpio.h"
#include "hal/hal_timer.h"
#include "hal/hal_uart.h"

#define LED_PORT     GPIO_JA
#define LED_PIN      0              // pino 1 do conector JA

#ifdef BUTTON_EXTERNAL
#define BTN_PORT     GPIO_JA
#define BTN_PIN      1              // pino 2 do conector JA
#else
#define BTN_PORT     GPIO_BTN
#define BTN_PIN      GPIO_BTN_UP    // BTNU da placa
#endif

#define HALF_PERIOD  500            // ms aceso e ms apagado
#define STEP         10             // ms entre leituras do botão

static void led_set(uint32_t on) {
    hal_gpio_write(LED_PORT, LED_PIN, on);
    hal_gpio_write(GPIO_LED, 0, on);
}

int main(void) {
    hal_uart_init();
    hal_uart_puts("\r\nBlink: LED no pino 1 do Pmod JA (e no LD0); segure o botao para manter aceso\r\n");

    // Como num microcontrolador: escolhe a porta e o pino e define a direção
    hal_gpio_set_dir(LED_PORT, LED_PIN, GPIO_OUTPUT);
    hal_gpio_set_dir(BTN_PORT, BTN_PIN, GPIO_INPUT);

    uint32_t led_on = 0, elapsed = 0, was_pressed = 0;

    while (1) {
        uint32_t pressed = hal_gpio_read(BTN_PORT, BTN_PIN);

        if (pressed) {
            led_set(1);                                 // botão pressionado: aceso direto
        } else {
            if (was_pressed) {                          // soltou: recomeça o pisca apagado
                led_on = 0;
                elapsed = 0;
            }
            if (elapsed >= HALF_PERIOD) {               // meio período: inverte
                led_on ^= 1;
                elapsed = 0;
            }
            led_set(led_on);
        }

        if (pressed != was_pressed) hal_uart_puts(pressed ? " botao: aceso\r\n" : " botao: piscando\r\n");
        was_pressed = pressed;

        hal_timer_delay_ms(STEP);                       // lê o botão a cada 10 ms
        elapsed += STEP;
    }

    return 0;
}
