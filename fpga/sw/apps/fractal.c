#include <stdint.h>       // Tipos padrão
#include "hal/hal_vga.h"  // Usa as funções vga_plot, init, etc.
#include "memory_map.h"   // Usa MMIO32 e endereços base (para os LEDs)

// ===============================================================================
// MATEMÁTICA DE PONTO FIXO (Q10)
// ===============================================================================

// Necessário pois o CORE RV32I não tem suporte à ponto flutuante
// Usando-se 10 bits para a fração (escala de 1024)

#define SHIFT 10
#define FIXED_ONE (1 << SHIFT)

// Multiplicação (a * b) / 1024
int32_t mul_fixed(int32_t a, int32_t b) {

    int negative = (a < 0) ^ (b < 0);
    uint32_t ua = (a < 0) ? -a : a;
    uint32_t ub = (b < 0) ? -b : b;
    
    uint32_t res = 0;

    while (ub > 0) {
        if (ub & 1) res += ua;
        ua <<= 1;
        ub >>= 1;
    }
    
    res >>= SHIFT;
    return negative ? -res : res;

}

// ===============================================================================
// PALETA DE CORES
// ===============================================================================

// Seguindo o padrão RGB332 (3 bits Red, 3 bits Green, 2 bits Blue)

const uint8_t PALETTE[16] = {
    0x00, 0x01, 0x02, 0x03, 0x07, 0x0B, 0x0F, 0x13,
    0x17, 0x1B, 0x1F, 0x3F, 0x5F, 0x9F, 0xDF, 0xFF
};

// ===============================================================================
// MAIN - RENDERIZADOR MANDELBROT
// ===============================================================================

void main() {

    // 1. Inicializa o Vídeo via HAL

    hal_vga_init(); // Limpa a tela automaticamente

    // Acesso direto aos LEDs (Offset 0 na GPIO)

    volatile uint32_t *leds = (volatile uint32_t *)GPIO_BASE_ADDR;
    *leds = 0;

    // --- Configuração do Fractal ---
    
    int32_t dx = 13; // Passo X
    int32_t dy = 13; // Passo Y
    
    int32_t start_x = -2560; // -2.5
    int32_t start_y = -1536; // -1.5

    int32_t cy = start_y;
    
    // --- Loop de Renderização ---

    // Y (Linhas)
    for (int py = 0; py < VGA_HEIGHT; py++) {
        
        int32_t cx = start_x;
        
        // X (Colunas)
        for (int px = 0; px < VGA_WIDTH; px++) {
            
            int32_t zx = 0;
            int32_t zy = 0;
            int iter = 0;
            
            // Loop Fractal (Z = Z^2 + C)
            while (iter < 15) { // Max 15 iterações para caber na paleta
                int32_t zx2 = mul_fixed(zx, zx);
                int32_t zy2 = mul_fixed(zy, zy);
                
                // Sai se magnitude > 2 (4.0 em fixed point)
                if ((zx2 + zy2) > 4096) break;
                
                int32_t zx_zy = mul_fixed(zx, zy);
                int32_t next_zy = (zx_zy << 1) + cy;
                int32_t next_zx = zx2 - zy2 + cx;
                
                zx = next_zx;
                zy = next_zy;
                iter++;
            }
            
            // Desenho via HAL
            // Se iter chegou no limite (15), é "dentro" do conjunto -> Preto
            // Caso contrário, usa a paleta de cores
            uint8_t color;
            if (iter == 15) {
                color = VGA_BLACK; 
            } else {
                color = PALETTE[iter];
            }
            
            hal_vga_plot(px, py, color);
            
            cx += dx;
        }
        
        cy += dy;
        
        // Feedback Visual nos LEDs (Binário da linha atual)
        *leds = py;

    }

    // --- Fim: Animação de Sucesso ---

    while(1) {

        *leds = 0xAAAA;
        for(volatile int i=0; i<200000; i++); 
        *leds = 0x5555;
        for(volatile int i=0; i<200000; i++);

    }
    
}