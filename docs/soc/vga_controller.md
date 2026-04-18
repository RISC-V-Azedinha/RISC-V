# VGA Controller - Microarquitetura

---

## 1. Visão Geral

O **VGA Controller** é um periférico de saída de vídeo que implementa um framebuffer mapeado em memória (Memory-Mapped I/O) para controle de um monitor VGA padrão. O módulo converte dados de pixels armazenados em uma VRAM interna em sinais de vídeo analógicos sincronizados para resoluções de 640x480 a 60Hz.

### 1.1 Características Principais

| Característica | Valor |
|----------------|-------|
| **Padrão** | VGA (Video Graphics Array) |
| **Resolução Original** | 640x480 pixels |
| **Resolução VRAM** | 320x240 pixels (escalado 2x) |
| **Profundidade de Cor** | 8 bits/pixel (RRRGGGBB) |
| **Taxa de Atualização** | 60 Hz |
| **Frequência de Pixel** | 25 MHz |
| **VRAM** | 76.800 bytes (320×240) |
| **Clock de Entrada** | 100 MHz |

---

## 2. Interface de Vídeo VGA

### 2.1 Sinais de Saída

| Pino | Direção | Descrição |
|------|---------|-----------|
| vga_hs_o | Output | Sincronismo horizontal (horizontal sync) |
| vga_vs_o | Output | Sincronismo vertical (vertical sync) |
| vga_r_o[3:0] | Output | Componente vermelho (4 bits) |
| vga_g_o[3:0] | Output | Componente verde (4 bits) |
| vga_b_o[3:0] | Output | Componente azul (4 bits) |

### 2.2 Temporização VGA (640x480 @ 60Hz)

O padrão VGA utiliza sinais de sincronismo para posicionar o feixe de elétrons do monitor:

| Parâmetro | Valor (pixels) |
|-----------|----------------|
| **Largura área ativa horizontal** | 640 |
| **Front porch horizontal** | 16 |
| **Sync pulse horizontal** | 96 |
| **Back porch horizontal** | 48 |
| **Total linha** | 800 |
| **Largura área ativa vertical** | 480 |
| **Front porch vertical** | 10 |
| **Sync pulse vertical** | 2 |
| **Back porch vertical** | 33 |
| **Total frame** | 525 |

---

## 3. Diagrama de Blocos

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              VGA CONTROLLER                                         │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   BARRAMENTO DO SOC                              INTERFACE VGA                      │
│   ┌──────────────────┐                           ┌────────────────────┐              │
│   │    addr_i[16:0]  │──────────────────────────▶│                    │              │
│   │    data_i[31:0]  │──────────────────────────▶│   LOGICA DE        │              │
│   │    we_i, vld_i   │──────────────────────────▶│   CONTROLE         │              │
│   │                  │                           │                    │              │
│   │    data_o[31:0]  │◀──────────────────────────│                    │              │
│   │    rdy_o         │◀──────────────────────────│                    │              │
│   └──────────────────┘                           └────────┬───────────┘              │
│                                                          │                          │
│                                                          ▼                          │
│   ┌───────────────────────────────────────────────────────────────────────────────┐ │
│   │                         ARQUITETURA INTERNA                                   │ │
│   │                                                                               │ │
│   │   ┌─────────────────────┐           ┌─────────────────────┐                 │ │
│   │   │   LOGICA DE         │           │   ENDEREÇAMENTO     │                 │ │
│   │   │   ALINHAMENTO       │──────────▶│   VRAM (READ)       │                 │ │
│   │   │   (MUX 4:1)         │           │   addr_b            │                 │ │
│   │   └────────┬────────────┘           └──────────┬──────────┘                 │ │
│   │            │                                │                              │ │
│   │            │                          ┌──────┴───────┐                      │ │
│   │            │                          │              │                      │ │
│   │            ▼                          ▼              ▼                      │ │
│   │   ┌─────────────────┐         ┌──────────────┐  ┌──────────────┐           │ │
│   │   │      VRAM       │         │  vga_sync   │  │  EXTRATOR    │           │ │
│   │   │  (Dual-port)   │         │  (Timing)   │  │    COR       │           │ │
│   │   │  320×240×8b    │◀───────▶│              │  │              │           │ │
│   │   │                 │  addr_a │              │  │              │           │ │
│   │   │  we_a, data_a   │         │ h_count      │  │ R[3:0]        │           │ │
│   │   │  addr_b, data_b │         │ v_count      │  │ G[3:0]        │           │ │
│   │   │                 │         │ h_sync       │  │ B[3:0]        │           │ │
│   │   │                 │         │ v_sync       │  │              │           │ │
│   │   │                 │         │ video_on     │  │              │           │ │
│   │   └────────┬────────┘         └──────────────┘  └──────────────┘           │ │
│   │            │                               │                              │ │
│   └────────────┼───────────────────────────────┼──────────────────────────────┘ │
│                │                               │                                  │
│                │                         ┌─────┴─────┐                            │
│                │                         │  PINOS    │                            │
│                │                         │  VGA      │                            │
│                │                         │  OUTPUT   │                            │
│                │                         └───────────┘                            │
│                │                                                                    │
└────────────────┼─────────────────────────────────────────────────────────────────┘
                 │
                 ▼
         ┌───────────────┐
         │  MONITOR VGA  │
         │  640x480      │
         └───────────────┘
```

---

## 4. Mapa de Memória

### 4.1 Espaço de Endereçamento

| Endereço | Tamanho | Descrição |
|----------|---------|-----------|
| 0x00000 - 0x12BFF | 76.800 bytes | Framebuffer VRAM (320×240) |
| 0x1FFFF | 4 bytes | Registrador de Status (apenas leitura) |

### 4.2 Registrador de Status (Offset 0x1FFFF)

| Bit | Nome | Descrição |
|-----|------|-----------|
| 0 | VSYNC | Estado atual do sincronismo vertical ('1' = ativo) |
| 31:1 | Reserved | Reservado |

### 4.3 Aceso à VRAM

A VRAM é accessed via escrita direta de 32 bits (4 bytes por transação). O hardware de alinhamento seleciona o byte correto com base nos 2 bits menos significativos do endereço:

```c
// Endereço 0x00 -> data_i[7:0]
// Endereço 0x01 -> data_i[15:8]
// Endereço 0x02 -> data_i[23:16]
// Endereço 0x03 -> data_i[31:24]
```

---

## 5. Arquitetura do Módulo vga_sync

O módulo **vga_sync** é responsável por gerar os sinais de temporização VGA e os contadores de posição de pixel.

### 5.1 Divisor de Clock

O clock de entrada de 100MHz é dividido por 4 para obter os 25MHz necessários para a taxa de pixels:

```vhdl
if count_div = 3 then
    count_div <= 0;
    pixel_en <= '1';  -- Pulso a cada 4 ciclos (25MHz)
else
    count_div <= count_div + 1;
    pixel_en <= '0';
end if;
```

### 5.2 Contadores de Posição

Os contadores horizontal (h_count) e vertical (v_count) avançam apenas quando pixel_en = '1', garantindo a temporização correta:

```vhdl
if h_cnt_reg = 799 then
    h_cnt_reg <= 0;
    if v_cnt_reg = 524 then
        v_cnt_reg <= 0;
    else
        v_cnt_reg <= v_cnt_reg + 1;
    end if;
else
    h_cnt_reg <= h_cnt_reg + 1;
end if;
```

### 5.3 Sinais de Sincronismo

Os sinais de sincronismo são ativos em nível lógico baixo (polaridade negativa):

```vhdl
h_sync <= '0' when (h_cnt_reg >= 656 and h_cnt_reg < 752) else '1';
v_sync <= '0' when (v_cnt_reg >= 490 and v_cnt_reg < 492) else '1';
```

### 5.4 Área Ativa de Vídeo

O sinal video_on indica quando os contadores estão dentro da área visível:

```vhdl
video_on <= '1' when (h_cnt_reg < 640 and v_cnt_reg < 480) else '0';
```

---

## 6. Arquitetura do Módulo vga_peripheral

O módulo **vga_peripheral** integra a VRAM, o gerador de sincronismo e a lógica de extração de cores.

### 6.1 VRAM (Dual-Port Memory)

A Video RAM é uma memória de dupla porta que permite escritas simultâneas pela CPU (porta A) e leituras pelo hardware de vídeo (porta Porta B):

- **Capacidade**: 320 × 240 = 76.800 bytes
- **Largura de dados**: 8 bits por endereço
- **Formato de pixel**: RRRGGGBB (3 bits vermelho, 3 bits verde, 2 bits azul)

### 6.2 Lógica de Alinhamento de Dados

Quando a CPU escreve um dado de 32 bits, o hardware seleciona o byte correto baseado nos 2 bits menos significativos do endereço:

```vhdl
case addr_i(1 downto 0) is
    when "00"   => s_data_aligned <= data_i(7 downto 0);
    when "01"   => s_data_aligned <= data_i(15 downto 8);
    when "10"   => s_data_aligned <= data_i(23 downto 16);
    when "11"   => s_data_aligned <= data_i(31 downto 24);
    when others => s_data_aligned <= (others => '0');
end case;
```

### 6.3 Escalonamento de Coordenadas

Como a VRAM tem resolução 320×240 mas a saída VGA é 640×480, as coordenadas são escaladas por fator de 2:

```vhdl
x_scaled <= pixel_x / 2;
y_scaled <= pixel_y / 2;
vram_addr <= std_logic_vector(to_unsigned(y_scaled * 320 + x_scaled, 17));
```

### 6.4 Extrator de Cores

O hardware extrai os componentes de cor do byte da VRAM e os expande para 4 bits cada:

```vhdl
vga_r_o <= vram_data(7 downto 5) & "0";  -- 3 bits -> 4 bits
vga_g_o <= vram_data(4 downto 2) & "0";  -- 3 bits -> 4 bits
vga_b_o <= vram_data(1 downto 0) & "00";  -- 2 bits -> 4 bits
```

---

## 7. Interface de Barramento

### 7.1 Protocolo de Handshake

A interface de barramento implementa o protocolo padrão de handshake com sinais vld_i e rdy_o:

| Fase | CPU | VGA Controller |
|------|-----|----------------|
| 1 | Configura addr_i, data_i, we_i | - |
| 2 | Asserta vld_i = '1' | - |
| 3 | - | Detecta vld_i, processa operação |
| 4 | - | Asserta rdy_o = '1' (próximo ciclo) |
| 5 | Aguarda rdy_o = '1' | - |

### 7.2 Operações Suportadas

| addr_i | we_i | Operação | Ação |
|--------|------|----------|------|
| 0x00000 - 0x12BFF | 1 | WRITE | Escreve pixel na VRAM |
| 0x00000 - 0x12BFF | 0 | READ | Lê pixel da VRAM |
| 0x1FFFF | 0 | READ STATUS | Retorna estado do VSYNC |

### 7.3 Escrita na VRAM

A escrita na VRAM é engatilhada pelo sinal combinado:

```vhdl
s_vram_we <= we_i and vld_i;
```

A escrita ocorre na mesma borda de clock em que a operação é válida, sem esperar o handshake de conclusão.

---

## 8. Formato de Cor

### 8.1 Representação de Pixel (8 bits)

| Bits | Componente | Valores |
|------|------------|---------|
| 7:5 | Vermelho | 0-7 (8 níveis) |
| 4:2 | Verde | 0-7 (8 níveis) |
| 1:0 | Azul | 0-3 (4 níveis) |

### 8.2 Expansão para Saída (4 bits por canal)

Cada componente é expandido para 4 bits para compatibilidade com conversores DAC VGA padrão:

- Vermelho: 3 bits → 4 bits (bit mais significativo replicado)
- Verde: 3 bits → 4 bits (bit mais significativo replicado)
- Azul: 2 bits → 4 bits (bits mais significativos replicados)

---

## 9. Biblioteca HAL (Software)

### 9.1 Funções Disponíveis

| Função | Descrição |
|--------|-----------|
| hal_vga_init() | Inicializa o controlador e limpa a tela |
| hal_vga_pixel(x, y, color) | Escreve um pixel na posição (x, y) |
| hal_vga_rect(x, y, w, h, color) | Desenha um retângulo |
| hal_vga_vsync_wait() | Espera pelo próximo VSYNC |
| hal_vga_clear(color) | Limpa toda a tela com uma cor |

### 9.2 Constantes de Cor

| Constante | Valor | Cor |
|-----------|-------|-----|
| VGA_BLACK | 0x00 | Preto |
| VGA_WHITE | 0xFF | Branco |
| VGA_RED | 0xE0 | Vermelho |
| VGA_GREEN | 0x1C | Verde |
| VGA_BLUE | 0x03 | Azul |
| VGA_YELLOW | 0xFC | Amarelo |

---

## 10. Exemplo de Uso

```c
#include "hal/hal_vga.h"

void main() {
    // Inicializa o VGA
    hal_vga_init();
    
    // Desenha um retângulo vermelho no centro
    hal_vga_rect(100, 80, 120, 80, VGA_RED);
    
    // Loop principal com sincronização vertical
    while (1) {
        hal_vga_vsync_wait();  // Espera 60Hz
        
        // Atualiza framebuffer
        hal_vga_pixel(160, 120, VGA_WHITE);
    }
}
```

---

## 11. Referências

- **RTL Source:** `rtl/perips/vga/vga_sync.vhd`
- **RTL Source:** `rtl/perips/vga/vga_peripheral.vhd`
- **Test Software:** `fpga/sw/tests/vga_test.c`
- **HAL Header:** `fpga/sw/hal/hal_vga.h`
- **VGA Timing Standard:** VESA DMT Spec

---