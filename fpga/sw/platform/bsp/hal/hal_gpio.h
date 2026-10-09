#ifndef HAL_GPIO_H
#define HAL_GPIO_H

#include <stdint.h>
#include <stdbool.h>
#include "memory_map.h"

// ============================================================================
// PORTAS E PINOS
// ============================================================================
//
// Como num microcontrolador: escolhe-se a porta e o pino, define-se a direção e
// depois lê-se ou escreve-se o pino.
//
//   hal_gpio_set_dir(GPIO_JA, 0, GPIO_OUTPUT);
//   hal_gpio_write(GPIO_JA, 0, 1);
//   if (hal_gpio_read(GPIO_BTN, GPIO_BTN_UP)) ...
//
// Pmods: o pino i da porta é o pino i do conector na ordem 1, 2, 3, 4, 7, 8, 9, 10
// (pinos 5/11 são GND e 6/12 são 3,3 V).

typedef enum {
    GPIO_JA  = 0,               // Pmod JA (8 pinos, entrada ou saída)
    GPIO_JB  = 1,               // Pmod JB
    GPIO_JC  = 2,               // Pmod JC
    GPIO_JD  = 3,               // Pmod JD
    GPIO_LED = 4,               // LD0..LD15 (só saída)
    GPIO_SW  = 5,               // SW0..SW15 (só entrada, com filtro de repique)
    GPIO_BTN = 6                // Botões (só entrada, com filtro de repique)
} gpio_port_t;

typedef enum {
    GPIO_INPUT  = 0,
    GPIO_OUTPUT = 1
} gpio_dir_t;

typedef enum {
    GPIO_EDGE_RISING  = 0,
    GPIO_EDGE_FALLING = 1
} gpio_edge_t;

// Pinos da porta de botões (o BTNC é o reset do SoC)
#define GPIO_BTN_UP     0
#define GPIO_BTN_DOWN   1
#define GPIO_BTN_LEFT   2
#define GPIO_BTN_RIGHT  3

// --- Pino a pino ------------------------------------------------------------

static inline void hal_gpio_set_dir(gpio_port_t port, uint32_t pin, gpio_dir_t dir) {
    if (dir == GPIO_OUTPUT) GPIO_REG(port, GPIO_REG_DIR) |=  (1u << pin);
    else                    GPIO_REG(port, GPIO_REG_DIR) &= ~(1u << pin);
}

static inline void hal_gpio_write(gpio_port_t port, uint32_t pin, uint32_t value) {
    if (value) GPIO_REG(port, GPIO_REG_OUTSET) = 1u << pin;
    else       GPIO_REG(port, GPIO_REG_OUTCLR) = 1u << pin;
}

static inline void hal_gpio_toggle(gpio_port_t port, uint32_t pin) {
    GPIO_REG(port, GPIO_REG_OUTTGL) = 1u << pin;
}

static inline uint32_t hal_gpio_read(gpio_port_t port, uint32_t pin) {
    return (GPIO_REG(port, GPIO_REG_IN) >> pin) & 1u;
}

// --- Porta inteira ----------------------------------------------------------

static inline void hal_gpio_port_set_dir(gpio_port_t port, uint32_t mask) {
    GPIO_REG(port, GPIO_REG_DIR) = mask;                 // bit i = 1: pino i é saída
}

static inline void hal_gpio_port_write(gpio_port_t port, uint32_t value) {
    GPIO_REG(port, GPIO_REG_OUT) = value;
}

static inline uint32_t hal_gpio_port_read(gpio_port_t port) {
    return GPIO_REG(port, GPIO_REG_IN);
}

// --- Atalhos para LEDs e chaves --------------------------------------------

static inline void     hal_leds_write(uint16_t value) { hal_gpio_port_write(GPIO_LED, value); }
static inline uint16_t hal_leds_read(void)            { return (uint16_t)GPIO_REG(GPIO_LED, GPIO_REG_OUT); }
static inline uint16_t hal_switches_read(void)        { return (uint16_t)hal_gpio_port_read(GPIO_SW); }
static inline uint8_t  hal_buttons_read(void)         { return (uint8_t)hal_gpio_port_read(GPIO_BTN); }

// --- Interrupções (PLIC fonte PLIC_SOURCE_GPIO) ----------------------------
//
// A flag do pino (IFG) é marcada na borda escolhida mesmo sem a interrupção
// habilitada, então dá para consultar bordas sem usar interrupções.

static inline void hal_gpio_irq_enable(gpio_port_t port, uint32_t pin, gpio_edge_t edge) {
    if (edge == GPIO_EDGE_FALLING) GPIO_REG(port, GPIO_REG_IES) |=  (1u << pin);
    else                           GPIO_REG(port, GPIO_REG_IES) &= ~(1u << pin);
    GPIO_REG(port, GPIO_REG_IFG) = 1u << pin;            // descarta bordas antigas
    GPIO_REG(port, GPIO_REG_IE) |= (1u << pin);
}

static inline void hal_gpio_irq_disable(gpio_port_t port, uint32_t pin) {
    GPIO_REG(port, GPIO_REG_IE) &= ~(1u << pin);
}

static inline uint32_t hal_gpio_irq_flags(gpio_port_t port) {
    return GPIO_REG(port, GPIO_REG_IFG);
}

static inline void hal_gpio_irq_clear(gpio_port_t port, uint32_t mask) {
    GPIO_REG(port, GPIO_REG_IFG) = mask;
}

// ============================================================================
// DISPLAYS DE 7 SEGMENTOS
// ============================================================================
//
// O hardware varre os 8 dígitos sozinho; o dígito 0 é o da direita.

// Segmentos crus: bit 0 = a ... bit 6 = g, bit 7 = ponto decimal
#define SEG7_A   (1u << 0)
#define SEG7_B   (1u << 1)
#define SEG7_C   (1u << 2)
#define SEG7_D   (1u << 3)
#define SEG7_E   (1u << 4)
#define SEG7_F   (1u << 5)
#define SEG7_G   (1u << 6)
#define SEG7_DP  (1u << 7)

static inline void hal_seg7_enable(uint8_t digits_mask) { SEG7_REG_EN = digits_mask; }
static inline void hal_seg7_off(void)                   { SEG7_REG_EN = 0; }
static inline void hal_seg7_set_dp(uint8_t dp_mask)     { SEG7_REG_DP = dp_mask; }

/** Mostra um valor em hexadecimal (8 dígitos). */
static inline void hal_seg7_write_hex(uint32_t value) {
    SEG7_REG_CTRL = 0;
    SEG7_REG_HEX  = value;
}

/** Mostra um número decimal (sem sinal), acendendo só os dígitos necessários. */
void hal_seg7_write_dec(uint32_t value);

/** Modo de segmentos crus: define os segmentos de um dígito (0..7). */
void hal_seg7_set_raw(uint32_t digit, uint8_t segments);

// ============================================================================
// LEDs RGB
// ============================================================================

#define RGB_LD16  0
#define RGB_LD17  1

/** Brilho 0..255 de cada cor (255 = 1/8 do LED ligado direto; os LEDs da placa são muito fortes). */
static inline void hal_rgb_set(uint32_t led, uint8_t r, uint8_t g, uint8_t b) {
    RGB_REG(led) = ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

#endif // HAL_GPIO_H
