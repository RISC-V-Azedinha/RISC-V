/**
 * @file demo.c
 * @brief Demonstração visual da placa, para gravar no cartão SD (make upload SW=demo SAVE=1).
 *
 *   Displays  : alterna sozinho entre três animações (a cada ~6 s):
 *                 texto "rISC-U SoC nPU" rolando, uma cobra correndo pela borda dos 8 dígitos
 *                 e um contador decimal.
 *   LEDs RGB  : percorrem o arco-íris; o LD17 fica na cor oposta à do LD16.
 *   LEDs      : "Knight Rider" com rastro; com qualquer chave ligada, mostram as chaves.
 *   Botões    : BTNR / BTNL = próxima / anterior animação; BTNU / BTND = mais rápido / mais devagar.
 *               (o BTNC é o reset do SoC)
 */

#include <stdint.h>
#include "hal/hal_gpio.h"
#include "hal/hal_timer.h"
#include "hal/hal_uart.h"

#define FRAME_MS     20             // um quadro a cada 20 ms (50 quadros/s)
#define SCENE_FRAMES 300            // troca de animação a cada 300 quadros (6 s)

// =========================================================
// DISPLAYS: TEXTO, COBRA E CONTADOR
// =========================================================

// Segmentos crus: bit 0 = a ... bit 6 = g (1 = aceso)
#define SEG_R  (SEG7_E | SEG7_G)
#define SEG_I  (SEG7_C)
#define SEG_S  (SEG7_A | SEG7_F | SEG7_G | SEG7_C | SEG7_D)
#define SEG_C  (SEG7_A | SEG7_D | SEG7_E | SEG7_F)
#define SEG_O  (SEG7_C | SEG7_D | SEG7_E | SEG7_G)
#define SEG_U  (SEG7_B | SEG7_C | SEG7_D | SEG7_E | SEG7_F)
#define SEG_N  (SEG7_C | SEG7_E | SEG7_G)
#define SEG_P  (SEG7_A | SEG7_B | SEG7_E | SEG7_F | SEG7_G)
#define SEG_DASH (SEG7_G)

// "rISC-U SoC nPU", com espaços nas pontas para o texto entrar e sair do display
static const uint8_t message[] = {
    0, 0, 0, 0, 0, 0, 0, 0,
    SEG_R, SEG_I, SEG_S, SEG_C, SEG_DASH, SEG_U, 0, SEG_S, SEG_O, SEG_C, 0, SEG_N, SEG_P, SEG_U,
    0, 0, 0, 0, 0, 0, 0, 0,
};

static void scroll_text(uint32_t frame, uint32_t speed) {
    uint32_t steps = sizeof(message) - 8 + 1;
    uint32_t pos = (frame * speed / 25) % steps;            // 2 letras por segundo por nível de velocidade
    for (uint32_t d = 0; d < 8; d++) hal_seg7_set_raw(d, message[pos + 7 - d]);   // dígito 7 à esquerda
    hal_seg7_enable(0xFF);
}

// Cobra: percorre a borda dos 8 dígitos (a no topo, b/c à direita, d embaixo, e/f à esquerda)
#define SNAKE_STEPS 20
#define SNAKE_LEN   5

static void snake_cell(uint32_t step, uint32_t *digit, uint8_t *seg) {
    if (step < 8)       { *digit = 7 - step;  *seg = SEG7_A; }                  // topo, da esquerda para a direita
    else if (step < 10) { *digit = 0;         *seg = (step == 8) ? SEG7_B : SEG7_C; }
    else if (step < 18) { *digit = step - 10; *seg = SEG7_D; }                  // embaixo, da direita para a esquerda
    else                { *digit = 7;         *seg = (step == 18) ? SEG7_E : SEG7_F; }
}

static void snake(uint32_t frame, uint32_t speed) {
    uint8_t segs[8] = {0};
    uint32_t head = (frame * speed / 6) % SNAKE_STEPS;
    for (uint32_t i = 0; i < SNAKE_LEN; i++) {
        uint32_t digit; uint8_t seg;
        snake_cell((head + SNAKE_STEPS - i) % SNAKE_STEPS, &digit, &seg);
        segs[digit] |= seg;
    }
    for (uint32_t d = 0; d < 8; d++) hal_seg7_set_raw(d, segs[d]);
    hal_seg7_enable(0xFF);
}

static void counter(uint32_t frame, uint32_t speed) {
    hal_seg7_write_dec(frame * speed);
    hal_seg7_set_dp(0);
}

// =========================================================
// LEDs RGB: ARCO-ÍRIS
// =========================================================

// Matiz 0..767 -> cor (três trechos de 256: vermelho -> verde -> azul -> vermelho)
static void hue_to_rgb(uint32_t hue, uint8_t *r, uint8_t *g, uint8_t *b) {
    uint32_t x = hue & 0xFF;
    switch ((hue >> 8) % 3) {
        case 0:  *r = 255 - x; *g = x;       *b = 0;       break;
        case 1:  *r = 0;       *g = 255 - x; *b = x;       break;
        default: *r = x;       *g = 0;       *b = 255 - x; break;
    }
}

static void rainbow(uint32_t frame, uint32_t speed) {
    uint8_t r, g, b;
    uint32_t hue = (frame * speed * 3) % 768;
    hue_to_rgb(hue, &r, &g, &b);
    hal_rgb_set(RGB_LD16, r, g, b);
    hue_to_rgb((hue + 384) % 768, &r, &g, &b);              // cor oposta
    hal_rgb_set(RGB_LD17, r, g, b);
}

// =========================================================
// LEDs: KNIGHT RIDER
// =========================================================

static void knight_rider(uint32_t frame, uint32_t speed) {
    uint32_t pos = (frame * speed / 3) % 30;                // vai (0..15) e volta (14..1)
    uint32_t led = pos < 16 ? pos : 30 - pos;
    int dir = pos < 16 ? -1 : 1;                             // o rastro fica do lado de onde ele veio
    uint16_t pattern = 0;
    for (int i = 0; i < 3; i++) {
        int p = (int)led + dir * i;
        if (p >= 0 && p < 16) pattern |= (uint16_t)(1u << p);
    }
    hal_leds_write(pattern);
}

// =========================================================
// MAIN
// =========================================================

int main(void) {
    static const char *names[] = { "texto", "cobra", "contador" };
    uint32_t frame = 0, scene = 0, scene_frames = 0, speed = 2;
    uint8_t last_buttons = 0;

    hal_uart_init();
    hal_uart_puts("\r\nDemo da placa: BTNR/BTNL trocam a animacao, BTNU/BTND mudam a velocidade, "
                  "chaves aparecem nos LEDs\r\n");

    while (1) {
        // Botões: só a borda de subida (apertar) conta
        uint8_t buttons = hal_buttons_read();
        uint8_t pressed = buttons & ~last_buttons;
        last_buttons = buttons;

        if (pressed & (1u << GPIO_BTN_RIGHT)) { scene = (scene + 1) % 3; scene_frames = 0; }
        if (pressed & (1u << GPIO_BTN_LEFT))  { scene = (scene + 2) % 3; scene_frames = 0; }
        if ((pressed & (1u << GPIO_BTN_UP))   && speed < 6) speed++;
        if ((pressed & (1u << GPIO_BTN_DOWN)) && speed > 1) speed--;
        if (pressed) {
            hal_uart_puts(" animacao: "); hal_uart_puts(names[scene]);
            hal_uart_puts("  velocidade: "); hal_uart_putc('0' + speed); hal_uart_puts("\r\n");
        }

        // Troca automática de animação
        if (++scene_frames >= SCENE_FRAMES) { scene = (scene + 1) % 3; scene_frames = 0; }

        switch (scene) {
            case 0:  scroll_text(scene_frames, speed); break;
            case 1:  snake(scene_frames, speed);       break;
            default: counter(scene_frames, speed);     break;
        }

        rainbow(frame, speed);

        uint16_t switches = hal_switches_read();
        if (switches) hal_leds_write(switches);
        else          knight_rider(frame, speed);

        frame++;
        hal_timer_delay_ms(FRAME_MS);
    }
    return 0;
}
