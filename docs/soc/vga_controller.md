# VGA Controller

---

## 1. Visão Geral

O **VGA Controller** é um periférico de saída de vídeo que permite ao processador RISC-V exibir gráficos em monitores VGA padrão.

| Característica | Valor |
|----------------|-------|
| **Resolução** | 640×480 pixels |
| **Taxa de Atualização** | 60 Hz |
| **Profundidade de Cor** | 8 bits/pixel (RGB332) |
| **VRAM** | 320×240 = 76.800 bytes |
| **Clock do Sistema** | 100 MHz |
| **Pixel Clock** | 25 MHz |

---

## 2. Princípio de Funcionamento

O padrão VGA utiliza o princípio da **varredura eletrônica** (raster scan), onde o monitor varre a tela linha por linha, da esquerda para direita e de cima para baixo.

### 2.1 Sinais de Sincronismo

Para que o monitor know quando reposicionar o feixe de elétrons, dois sinais são utilizados:

- **H_SYNC (Horizontal)**: Indica o momento de retornar ao início da linha
- **V_SYNC (Vertical)**: Indica o momento de retornar ao topo da tela

O monitor VGA espera pulses de sincronismo em intervalos específicos para controlar o posicionamento do feixe.

### 2.2 Área Ativa

Apenas uma região central da imagem (640×480 pixels) é visível. Os intervalos entre os pulses de sincronismo (front porch, back porch, sync pulse) são necessários para que o monitor processe o sinal, mas não aparecem na tela.

---

## 3. Memória de Vídeo

A **VRAM** (Video RAM) armazena os dados de pixel que serão exibidos na tela. O sistema utiliza uma **Dual-Port RAM** que permite acesso simultâneo de duas entidades independentes:

- **Porta A (CPU)**: O processador RISC-V escreve dados de pixel nesta porta para atualizar a tela
- **Porta B (VGA)**: O controlador VGA lê continuamente os dados para gerar a imagem

Esta separação permite que a CPU escreva na memória a qualquer momento, sem interferir na leitura contínua feita pelo controlador de vídeo.

### 3.1 Endereçamento

A VRAM é organizada como um array linear de 76.800 bytes (320 × 240). Cada byte representa um pixel no formato RGB332:

```
bit 7-5: Vermelho (3 bits)
bit 4-2: Verde   (3 bits)  
bit 1-0: Azul    (2 bits)
```

O endereço de cada pixel é calculado como:

```
endereço = (y × 320) + x
```

---

## 4. Interface com Software

A HAL VGA (`hal_vga.h`) fornece uma API simples para manipulação de gráficos:

```c
// Inicializa o controlador
hal_vga_init();

// Limpa a tela com uma cor
hal_vga_clear(VGA_BLACK);

// Desenha um pixel
hal_vga_plot(x, y, VGA_RED);

// Desenha um retângulo
hal_vga_rect(10, 10, 100, 50, VGA_GREEN);

// Espera o próximo quadro (para sincronização)
hal_vga_vsync_wait();
```

### 4.1 Cores Pré-definidas

A HAL define cores básicas em formato RGB332:

| Cor | Valor |
|-----|-------|
| `VGA_BLACK` | 0x00 |
| `VGA_WHITE` | 0xFF |
| `VGA_RED` | 0xE0 |
| `VGA_GREEN` | 0x1C |
| `VGA_BLUE` | 0x03 |
| `VGA_YELLOW` | 0xFC |
| `VGA_CYAN` | 0x1F |
| `VGA_MAGENTA` | 0xE3 |

### 4.2 Exemplo: Desenho de uma Linha

```c
void draw_line(int x0, int y0, int x1, int y1, uint8_t color) {
    int dx = abs(x1 - x0);
    int dy = -abs(y1 - y0);
    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    while (1) {
        hal_vga_plot(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}
```

---

## 5. Integração no SoC

O VGA Controller conecta-se ao barramento do SoC como um periférico mapeado em memória:

```
Endereço Base: 0x30000000
```

A CPU acessa a VRAM escrevendo bytes diretamente neste intervalo de endereços. O controlador de vídeo lê esses dados autonomamente para gerar a imagem.

---

*Documento simplificado. Para detalhes de implementação RTL, consulte o código fonte em `fpga/hw/peripherals/vga/`.*