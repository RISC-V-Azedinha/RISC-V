#include <stdint.h>
#include "hal/hal_vga.h"
#include "hal/hal_uart.h"
#include "memory_map.h"

// =========================================================
// 1. MATH HELPERS (Bare-Metal)
// =========================================================

int abs_val(int x) {
    return (x < 0) ? -x : x;
}

int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    int res = 0;
    int neg = (b < 0);
    if (neg) b = -b;
    while (b > 0) {
        if (b & 1) res += a;
        a <<= 1;
        b >>= 1;
    }
    return neg ? -res : res;
}

// =========================================================
// 2. PALETA & FONTE OTIMIZADA
// =========================================================
#define COL_BG      0x01 // Azul 
#define COL_PADDLE  0x1F // Ciano 
#define COL_BALL    0xFC // Amarelo
#define COL_TEXT    0xFF // Branco
#define COL_RED     0xE0 // Vermelho 

// Apenas letras necessárias: P O N G A M E V R S T
const uint8_t CHARS[][5] = {
    {0x1E, 0x11, 0x1E, 0x10, 0x10}, // 0: P
    {0x0E, 0x11, 0x11, 0x11, 0x0E}, // 1: O
    {0x11, 0x19, 0x15, 0x13, 0x11}, // 2: N
    {0x0E, 0x10, 0x13, 0x11, 0x0E}, // 3: G
    {0x04, 0x0A, 0x11, 0x1F, 0x11}, // 4: A
    {0x11, 0x1B, 0x15, 0x11, 0x11}, // 5: M
    {0x1F, 0x10, 0x1E, 0x10, 0x1F}, // 6: E
    {0x11, 0x11, 0x11, 0x0A, 0x04}, // 7: V
    {0x1E, 0x11, 0x1E, 0x14, 0x12}, // 8: R
    {0x0E, 0x10, 0x0E, 0x01, 0x1E}, // 9: S
    {0x1F, 0x04, 0x04, 0x04, 0x04}, // 10: T
};

// =========================================================
// 3. ENGINE GRÁFICA
// =========================================================

void draw_char(int x, int y, int index, uint8_t color, int sx, int sy) {
    for (int row = 0; row < 5; row++) {
        uint8_t bits = CHARS[index][row];
        int col = 0;
        while (col < 5) {
            while (col < 5 && ((bits >> (4 - col)) & 1) == 0) col++;
            if (col >= 5) break;
            int start = col;
            while (col < 5 && ((bits >> (4 - col)) & 1)) col++;
            int run = col - start;
            int px = x + mul(start, sx);
            int py = y + mul(row, sy);
            hal_vga_rect(px, py, mul(run, sx), sy, color);
        }
    }
}

void draw_logo_clean() {
    int y = 50;
    int sx = 8; int sy = 8;
    int spacing = mul(6, sx);
    int width_text = mul(4, spacing);
    int x = (VGA_WIDTH - width_text) >> 1;
    
    // P O N G (Indices: 0, 1, 2, 3)
    draw_char(x, y, 0, COL_PADDLE, sx, sy); x += spacing; 
    draw_char(x, y, 1, COL_PADDLE, sx, sy); x += spacing; 
    draw_char(x, y, 2, COL_PADDLE, sx, sy); x += spacing; 
    draw_char(x, y, 3, COL_PADDLE, sx, sy); x += spacing; 
}

void draw_press_start(int visible) {
    int y = 160;
    int sx = 3; int sy = 3;
    int spacing = mul(6, sx);
    int width_text = mul(5, spacing);
    int x = (VGA_WIDTH - width_text) >> 1;
    
    uint8_t color = visible ? COL_TEXT : COL_BG;
    
    // S T A R T (Indices: 9, 10, 4, 8, 10)
    draw_char(x, y, 9,  color, sx, sy); x += spacing; 
    draw_char(x, y, 10, color, sx, sy); x += spacing; 
    draw_char(x, y, 4,  color, sx, sy); x += spacing; 
    draw_char(x, y, 8,  color, sx, sy); x += spacing; 
    draw_char(x, y, 10, color, sx, sy); x += spacing; 
}

void draw_game_over_msg() {
    int y = 80;
    int sx = 4; int sy = 4;
    int spacing = mul(6, sx);
    int width_text = mul(9, spacing);
    int x = (VGA_WIDTH - width_text) >> 1;
    
    // G A M E (3, 4, 5, 6)
    draw_char(x, y, 3, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 4, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 5, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 6, COL_RED, sx, sy); x += spacing;
    x += spacing; 
    // O V E R (1, 7, 6, 8)
    draw_char(x, y, 1, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 7, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 6, COL_RED, sx, sy); x += spacing;
    draw_char(x, y, 8, COL_RED, sx, sy); x += spacing;
}

void draw_border() {
    hal_vga_rect(0, 0, VGA_WIDTH, 4, COL_PADDLE);
    hal_vga_rect(0, VGA_HEIGHT-4, VGA_WIDTH, 4, COL_PADDLE);
}

void draw_circle(int x0, int y0, int r, uint8_t color) {
    int x = r; int y = 0; int err = 0;
    while (x >= y) {
        hal_vga_rect(x0 - x, y0 + y, (x << 1) + 1, 1, color);
        hal_vga_rect(x0 - x, y0 - y, (x << 1) + 1, 1, color);
        hal_vga_rect(x0 - y, y0 + x, (y << 1) + 1, 1, color);
        hal_vga_rect(x0 - y, y0 - x, (y << 1) + 1, 1, color);
        if (err <= 0) { y += 1; err += (y << 1) + 1; }
        if (err > 0) { x -= 1; err -= (x << 1) + 1; }
    }
}

// =========================================================
// 4. LÓGICA PRINCIPAL
// =========================================================
typedef struct { int x, y, dx, dy, size; } Ball;
typedef struct { int x, y, w, h; } Paddle;

int check_collision(Ball *b, Paddle *p) {
    return (b->x + b->size > p->x && b->x - b->size < p->x + p->w &&
            b->y + b->size > p->y && b->y - b->size < p->y + p->h);
}

void reset_game(Ball *ball, Paddle *paddle, int *score, volatile uint32_t *leds) {
    ball->x = VGA_WIDTH >> 1;
    ball->y = VGA_HEIGHT >> 1;
    ball->dx = 2; ball->dy = -2; ball->size = 4;
    paddle->w = 50; paddle->h = 6;
    paddle->x = (VGA_WIDTH - paddle->w) >> 1;
    paddle->y = VGA_HEIGHT - 15;
    *score = 0; 
    *leds = 0; 
}

void main() {

    hal_uart_init();
    hal_vga_init();
    volatile uint32_t *leds = (volatile uint32_t *)GPIO_BASE_ADDR;
    
    int score = 0;
    int state = 0; 
    int last_state = -1;
    int frame_count = 0;

    Ball ball;
    Paddle paddle;

    reset_game(&ball, &paddle, &score, leds);

    while(1) {
        hal_vga_vsync_wait();
        frame_count++;

        if (state != last_state) {
            hal_vga_clear(COL_BG);
            last_state = state;
            if (state == 0) {
                draw_border();
                draw_logo_clean();
            }
        }

        if (state == 0) {
            // MENU
            if ((frame_count & 63) == 0) draw_press_start(1);
            else if ((frame_count & 63) == 32) draw_press_start(0);
            
            if (hal_uart_kbhit()) {
                char c = hal_uart_getc();
                reset_game(&ball, &paddle, &score, leds);
                state = 1;
                hal_vga_clear(COL_BG);
            }

        } else if (state == 1) {
            // JOGO
            
            // 1. Apagar
            draw_circle(ball.x, ball.y, ball.size, COL_BG);
            hal_vga_rect(paddle.x, paddle.y, paddle.w, paddle.h, COL_BG);
            
            // 2. Input
            int move = 0;
            if (hal_uart_kbhit()) {
                char c = hal_uart_getc();
                if (c == 'a') move = -8;
                if (c == 'd') move = 8;
            }
            paddle.x += move;
            if (paddle.x < 2) paddle.x = 2;
            if (paddle.x + paddle.w > VGA_WIDTH - 2) paddle.x = VGA_WIDTH - paddle.w - 2;

            // 3. Física
            ball.x += ball.dx;
            ball.y += ball.dy;

            // Paredes
            if (ball.x - ball.size < 0) { ball.x = ball.size; ball.dx = -ball.dx; }
            if (ball.x + ball.size > VGA_WIDTH) { ball.x = VGA_WIDTH - ball.size; ball.dx = -ball.dx; }
            if (ball.y - ball.size < 0) {
                ball.y = ball.size; 
                ball.dy = abs_val(ball.dy); 
            }

            // Colisão Paddle
            if (check_collision(&ball, &paddle)) {
                if (ball.dy > 0) {
                    ball.dy = -ball.dy;
                    score++;
                    *leds = score; // Placar nos LEDs
                    
                    // Aumenta velocidade a cada 3 pontos
                    int temp_score = score;
                    int mod3 = 0;
                    while(temp_score >= 3) { temp_score -= 3; mod3++; }
                    if (temp_score == 0) {
                         if (ball.dy < 0) ball.dy--; else ball.dy++;
                    }
                }
            }

            if (ball.y > VGA_HEIGHT) {
                state = 2;
            }

            // 4. Renderização
            hal_vga_rect(paddle.x, paddle.y, paddle.w, paddle.h, COL_PADDLE);
            draw_circle(ball.x, ball.y, ball.size, COL_BALL);

        } else {
            // GAME OVER
            if ((frame_count & 16) == 0) {
                draw_game_over_msg();
            }

            if (hal_uart_kbhit()) {
                char c = hal_uart_getc();
                state = 0; 
            }
        }

    }

}