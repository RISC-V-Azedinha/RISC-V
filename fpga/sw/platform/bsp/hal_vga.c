#include "hal_vga.h"
#include "memory_map.h"

void hal_vga_init(void) {
    // Hardware inicializa pronto, mas podemos limpar a tela aqui
    hal_vga_clear(VGA_BLACK);
}

void hal_vga_vsync_wait(void) {
    // 1. Se já estivermos no pulso (0), espera ele acabar (virar 1)
    while ((MMIO32(VGA_VSYNC_ADDR) & VGA_VSYNC_BIT) == 0);

    // 2. Espera o próximo pulso começar (virar 0)
    // Este é o topo do quadro (Front Porch/Sync)
    while ((MMIO32(VGA_VSYNC_ADDR) & VGA_VSYNC_BIT) != 0);
}

void hal_vga_plot(int x, int y, uint8_t color) {
    if (x >= VGA_WIDTH || y >= VGA_HEIGHT) return;

    // Cálculo do endereço linear: Base + (Y * Largura + X)
    uint32_t offset = (y * VGA_WIDTH) + x;
    
    // Escrita de 8 bits (Byte)
    MMIO8(VGA_BASE_ADDR + offset) = color;
}

void hal_vga_clear(uint8_t color) {
    // Loop linear é mais eficiente que chamar plot() várias vezes
    for (uint32_t i = 0; i < (VGA_WIDTH * VGA_HEIGHT); i++) {
        MMIO8(VGA_BASE_ADDR + i) = color;
    }
}

void hal_vga_rect(int x, int y, int w, int h, uint8_t color) {
    // Clipping: Garante que não vamos desenhar fora da memória
    if (x >= VGA_WIDTH || y >= VGA_HEIGHT) return;
    if (x < 0) { w += x; x = 0; } // Se x for -5, começa no 0 e diminui largura
    if (y < 0) { h += y; y = 0; }
    
    if (x + w > VGA_WIDTH)  w = VGA_WIDTH - x;
    if (y + h > VGA_HEIGHT) h = VGA_HEIGHT - y;

    // Desenha linha por linha
    for (int row = 0; row < h; row++) {
        uint32_t offset_base = ((y + row) * VGA_WIDTH) + x;
        for (int col = 0; col < w; col++) {
            MMIO8(VGA_BASE_ADDR + offset_base + col) = color;
        }
    }
}