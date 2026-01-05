
// Inclui os headers necessários ----------------------------------------------------

#include <stdint.h>       // Tipos padrão
#include "hal_vga.h"      // Driver VGA
#include "memory_map.h"   // Definições de memória (MMIO32, GPIO_BASE_ADDR)

// Geração de Cores Aleatórias ------------------------------------------------------

static uint32_t rand_state = 12345;                // Semente inicial

uint8_t get_random_color() {                       // Gera uma cor aleatória simples

    rand_state = rand_state * 1103515245 + 12345;  
    uint8_t c = (rand_state >> 16) & 0xFF;         
    return (c == 0) ? 0xFF : c;                    // Evita preto

}

// Programa Principal ---------------------------------------------------------------

void main() {

    // --- Setup --------------------------------------------------------------------
    
    hal_vga_init(); // Limpa a tela automaticamente

    int box_size = 20;
    int x = 10, y = 10;
    int dx = 2, dy = 2;
    uint8_t color = VGA_RED;
    
    // Acesso direto aos LEDs via MMIO (já que não fizemos hal_gpio ainda)
    // Assumindo GPIO_BASE_ADDR definido no memory_map.h
    MMIO32(GPIO_BASE_ADDR) = 0; 

    // Bordas
    hal_vga_rect(0, 0, VGA_WIDTH, 2, VGA_WHITE);            // Topo
    hal_vga_rect(0, VGA_HEIGHT-2, VGA_WIDTH, 2, VGA_WHITE); // Base
    hal_vga_rect(0, 0, 2, VGA_HEIGHT, VGA_WHITE);           // Esq
    hal_vga_rect(VGA_WIDTH-2, 0, 2, VGA_HEIGHT, VGA_WHITE); // Dir

    // --- Loop ---------------------------------------------------------------------

    while (1) {
        
        // 1. Sincronia (Trava a 60 FPS)
        hal_vga_vsync_wait();

        // 2. Apaga posição anterior
        hal_vga_rect(x, y, box_size, box_size, VGA_BLACK);

        // 3. Atualiza Posição
        x += dx;
        y += dy;

        // 4. Colisão
        int hit = 0;
        
        // Eixo X
        if (x <= 3 || x + box_size >= VGA_WIDTH - 3) {
            dx = -dx;
            hit = 1;
            x = (x <= 3) ? 3 : (VGA_WIDTH - box_size - 3);
        }

        // Eixo Y
        if (y <= 3 || y + box_size >= VGA_HEIGHT - 3) {
            dy = -dy;
            hit = 1;
            y = (y <= 3) ? 3 : (VGA_HEIGHT - box_size - 3);
        }

        // 5. Reação
        if (hit) {
            color = get_random_color();
            MMIO32(GPIO_BASE_ADDR) += 1; // Incrementa LEDs
        }

        // 6. Desenha Novo
        hal_vga_rect(x, y, box_size, box_size, color);

    }
    
}

// ----------------------------------------------------------------------------------