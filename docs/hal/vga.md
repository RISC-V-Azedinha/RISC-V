# VGA

A saída VGA mostra um *framebuffer* de **320×240 pixels**, ampliado para 640×480 no monitor. Cada pixel é um byte no formato RGB332 (3 bits de vermelho, 3 de verde e 2 de azul), e a memória de vídeo é mapeada a partir de `0x3000_0000`: o pixel (x, y) fica no endereço `y × 320 + x`. O hardware está descrito em [VGA](../perifericos/vga.md).

## Referência

| Função | Uso |
|---|---|
| `hal_vga_init()` | Limpa a tela (preto) |
| `hal_vga_clear(cor)` | Pinta a tela inteira |
| `hal_vga_plot(x, y, cor)` | Um pixel |
| `hal_vga_rect(x, y, l, a, cor)` | Retângulo preenchido |
| `hal_vga_vsync_wait()` | Espera o início do próximo quadro (60 Hz) |

As cores prontas são `VGA_BLACK`, `VGA_WHITE`, `VGA_RED`, `VGA_GREEN`, `VGA_BLUE`, `VGA_YELLOW`, `VGA_CYAN` e `VGA_MAGENTA`; outras se montam como `(r << 5) | (g << 2) | b`, com `r` e `g` de 0 a 7 e `b` de 0 a 3. As dimensões estão em `VGA_WIDTH` e `VGA_HEIGHT`.

!!! tip "Animação sem cintilação"
    Desenhar enquanto o monitor varre a tela pode mostrar um quadro pela metade. Chamar `hal_vga_vsync_wait()` antes de redesenhar faz as alterações acontecerem no retraço vertical, entre dois quadros.

## Exemplo: bola quicando

```c
#include "hal/hal_vga.h"

// Uma bola quicando na tela, redesenhada a cada quadro.
int main(void) {
    hal_vga_init();                                    // limpa a tela (preto)

    int x = 40, y = 30, dx = 2, dy = 1;
    while (1) {
        hal_vga_vsync_wait();                          // desenha só no retraço vertical
        hal_vga_rect(x, y, 8, 8, VGA_BLACK);           // apaga a posição anterior
        x += dx; y += dy;
        if (x <= 0 || x >= VGA_WIDTH - 8)  dx = -dx;
        if (y <= 0 || y >= VGA_HEIGHT - 8)        dy = -dy;
        hal_vga_rect(x, y, 8, 8, VGA_YELLOW);
    }
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_vga.c` e envie-o com `make upload SW=demo_vga`.
