/**
 * @file blink.c
 * @brief Blink: acende e apaga um LED ligado a um pino do Pmod JA.
 *
 * Ligação (Pmod JA):
 *
 *     pino 1 (JA[0]) ──[ resistor 220-330 Ω ]──►|── pino 5 (GND)
 *                                             LED
 *
 * O pino 1 do conector é o pino 0 da porta GPIO_JA. O LD0 da placa pisca junto,
 * para dar para ver o programa funcionando mesmo sem o LED externo.
 */

#include <stdint.h>
#include "hal/hal_gpio.h"
#include "hal/hal_timer.h"
#include "hal/hal_uart.h"

#define BLINK_PORT   GPIO_JA
#define BLINK_PIN    0              // pino 1 do conector JA
#define HALF_PERIOD  500            // ms aceso e ms apagado

int main(void) {
    hal_uart_init();
    hal_uart_puts("\r\nBlink: LED no pino 1 do Pmod JA (e no LD0)\r\n");

    // Como num microcontrolador: escolhe a porta e o pino e define a direção
    hal_gpio_set_dir(BLINK_PORT, BLINK_PIN, GPIO_OUTPUT);

    while (1) {
        hal_gpio_write(BLINK_PORT, BLINK_PIN, 1);       // acende
        hal_gpio_write(GPIO_LED, 0, 1);
        hal_timer_delay_ms(HALF_PERIOD);

        hal_gpio_write(BLINK_PORT, BLINK_PIN, 0);       // apaga
        hal_gpio_write(GPIO_LED, 0, 0);
        hal_timer_delay_ms(HALF_PERIOD);
    }

    return 0;
}
