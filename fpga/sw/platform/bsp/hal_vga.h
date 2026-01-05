#ifndef HAL_VGA_H
#define HAL_VGA_H

#include <stdint.h>

// =========================================================
// DEFINIÇÕES E CONSTANTES
// =========================================================

// Dimensões da Tela (Upscaled 320x240 -> 640x480)
#define VGA_WIDTH   320
#define VGA_HEIGHT  240

// Cores Básicas (Formato 8 bits: RGB332)
#define VGA_BLACK   0x00
#define VGA_WHITE   0xFF
#define VGA_RED     0xE0
#define VGA_GREEN   0x1C
#define VGA_BLUE    0x03
#define VGA_YELLOW  0xFC
#define VGA_CYAN    0x1F
#define VGA_MAGENTA 0xE3

// =========================================================
// PROTOTIPOS (API)
// =========================================================

/* Inicializa o controlador (se necessário) */
void hal_vga_init(void);

/* Limpa toda a tela com uma cor (Reset) */
void hal_vga_clear(uint8_t color);

/* Desenha um pixel único (Primitiva básica) */
void hal_vga_plot(int x, int y, uint8_t color);

/* Desenha um retângulo preenchido (Sólido) */
void hal_vga_rect(int x, int y, int w, int h, uint8_t color);

/* Bloqueia a execução até o início do próximo quadro (60Hz) */
void hal_vga_vsync_wait(void);

#endif /* HAL_VGA_H */