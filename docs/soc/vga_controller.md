# VGA Controller - Microarquitetura

---

## 1. Visão Geral

O **VGA Controller** é um periférico de saída de vídeo que permite ao processador RISC-V exibir gráficos em monitores VGA padrão. O sistema é composto por três módulos principais:

| Módulo | Função |
|--------|--------|
| `vga_sync` | Gera os sinais de sincronismo horizontal e vertical |
| `video_ram` | Armazena os dados de pixel (Dual-Port RAM) |
| `vga_peripheral` | Integra os módulos e gerencia a comunicação com o processador |

### 1.1 Características Principais

| Característica | Valor |
|----------------|-------|
| **Resolução** | 640×480 pixels |
| **Taxa de Atualização** | 60 Hz |
| **Profundidade de Cor** | 8 bits/pixel (RRRGGGBB) |
| **VRAM** | 320×240 = 76.800 bytes |
| **Clock do Sistema** | 100 MHz |
| **Pixel Clock** | 25 MHz |

---

## 2. Fundamentação Teórica: Padrão VGA

### 2.1 Princípio da Varredura de Tela

O padrão VGA utiliza o princípio da **varredura eletrônica** (raster scan), originado dos monitores CRT (Cathode Ray Tube):

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         VARREDURA DE TELA (RASTER SCAN)                            │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ← ESQUERDA                                                      DIREITA →         │
│   ┌───────────────────────────────────────────────────────────────────────────────┐ │
│   │                                                                               │ │
│   │                                    ▲                                          │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────  │  ──────────────────────────────────────  │ │
│   │                                    │                                          │ │
│   │  Linha 0 (retraço horizontal)     │  Linha 1                                 │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────► │  ──────────────────────────────────────►  │ │
│   │                                    │                                          │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────   │  ──────────────────────────────────────  │ │
│   │                                    │                                          │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────  │  ──────────────────────────────────────  │ │
│   │                                    │                                          │ │
│   │  ...                               │  ...                                     │ │
│   │                                    │                                          │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────  │  ──────────────────────────────────────  │ │
│   │                                    │                                          │ │
│   │  ───────────────────────────────► │  ──────────────────────────────────────►  │ │
│   │                                    │                                          │ │
│   │                                    │                                          │ │
│   │  Retorno vertical                 │  Linha 479                               │ │
│   │  (vertical blank)                 │                                          │ │
│   └───────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                     │
│       ▲                                                                             │
│       │                                                                             │
│       └── Feixe de elétrons varre a tela linha por linha, da esquerda para         │
│           direita e de cima para baixo. Ao final de cada linha, retorna              │
│           rapidamente à esquerda (retraço horizontal). Ao final da tela,            │
│           retorna ao topo (retraço vertical).                                       │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Necessidade de Porches e Sync Pulses

Os monitores CRT requerem **tempo de retorno** para o feixe de elétrons reposicionar-se. Estes intervalos são implementados como:

| Intervalo | Descrição |
|-----------|-----------|
| **Front Porch** | Espaço antes do pulso de sincronismo |
| **Sync Pulse** | Pulso que indica quando o feixe deve reposicionar-se |
| **Back Porch** | Espaço após o pulso de sincronismo |

Estes intervalos **não são visíveis** na tela, mas são necessários para que o monitor processe corretamente o sinal.

---

## 3. Temporização Horizontal

A temporização horizontal define o tempo necessário para varrer **uma linha** da tela.

### 3.1 Diagrama de Temporização

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                        TEMPORIZAÇÃO HORIZONTAL (640×480 @ 60Hz)                              │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                               │
│  Ciclo:       0         640        656        752        800                              │
│                │          │          │          │          │                                │
│                │   ATIVA  │  BACK   │  SYNC    │  FRONT   │                                │
│                │  (640px) │  PORCH  │  (96px)  │  PORCH   │                                │
│                │          │  (48px) │          │  (16px)  │                                │
│                ▼          ▼         ▼          ▼          ▼                                │
│  ────────────────────────────────────────────────────────────────────────────────────────►   │
│  (Tempo)                                                                                       │
│                                                                                               │
│  H_SYNC:       1─────────1────────0──────────0─────────1                                   │
│                │         │         ▲          ▲         │                                   │
│                │         │         │          │         │                                   │
│                │         │         └── 656 ────┘         │                                   │
│                │         │            à 752              │                                   │
│                │         │         (96 ciclos)           │                                   │
│                │         │                              │                                   │
│                │         │◄────── 48 ciclos ─────────►│                                   │
│                │         │                              │                                   │
│                │◄────────┴──────────────────────────────┴───────────────────────────────────►│
│                │                    640 ciclos                                                   │
│                │                   (display ativo)                                             │
│                │                                                                               │
│  video_on:     1─────────1─────────0──────────0─────────0                                    │
│                (ativo quando h_count < 640)                                                    │
│                                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Equações de Temporização Horizontal

```
Período de uma linha = Display + Front Porch + Sync Pulse + Back Porch
                      = 640 + 16 + 96 + 48
                      = 800 ciclos de pixel

Frequência de linha = Pixel Clock / Período de linha
                     = 25 MHz / 800
                     = 31.25 kHz
```

---

## 4. Temporização Vertical

A temporização vertical define o tempo necessário para varrer **todas as linhas** da tela (um quadro/frame).

### 4.1 Diagrama de Temporização

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                         TEMPORIZAÇÃO VERTICAL (640×480 @ 60Hz)                              │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                               │
│  Linha:      0         480        490        492        525                                │
│               │          │          │          │          │                                  │
│               │   ATIVA  │  BACK    │  VSYNC   │  FRONT   │                                  │
│               │  (480ln) │  PORCH   │  (2ln)   │  PORCH   │                                  │
│               │          │  (10ln)  │          │  (33ln)  │                                  │
│               ▼          ▼          ▼          ▼          ▼                                  │
│  V_SYNC:      1─────────1──────────0──────────0─────────1                                    │
│               │         │          ▲          ▲         │                                    │
│               │         │          │          │         │                                    │
│               │         │          └── 490 ────┘         │                                    │
│               │         │             à 492              │                                    │
│               │         │          (2 linhas)            │                                    │
│               │         │                              │                                    │
│               │         │◄──── 10 linhas ────────────►│                                    │
│               │         │                              │                                    │
│               │◄────────┴───────────────────────────────┴────────────────────────────────────►│
│               │                     480 linhas                                                 │
│               │                    (display ativo)                                             │
│               │                                                                               │
│  video_on:    1─────────1──────────0──────────0─────────0                                    │
│               (ativo quando v_count < 480)                                                   │
│                                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Equações de Temporização Vertical

```
Período de um frame = Linhas visíveis + V Back Porch + V Sync + V Front Porch
                    = 480 + 10 + 2 + 33
                    = 525 linhas

Frequência de frame (refresh rate) = Frequência de linha / Linhas por frame
                                   = 31.25 kHz / 525
                                   = 59.52 Hz ≈ 60 Hz

Período de frame = 1 / 60 Hz = 16.67 ms
```

---

## 5. Tabela de Cálculos Completa

### 5.1 640×480 @ 60Hz

| Parâmetro | Horizontal (ciclos) | Horizontal (µs) | Vertical (linhas) | Vertical (ms) |
|-----------|-------------------|-----------------|-------------------|---------------|
| **Pixel Clock** | 1 | 0.04 | - | - |
| **Display Ativo** | 640 | 25.6 | 480 | 15.36 |
| **Front Porch** | 16 | 0.64 | 33 | 1.056 |
| **Sync Pulse** | 96 | 3.84 | 2 | 0.064 |
| **Back Porch** | 48 | 1.92 | 10 | 0.32 |
| **Total por Linha/Frame** | **800** | **32.0** | **525** | **16.78** |

### 5.2 Validação dos Cálculos

```
Pixel Clock = CLK_SISTEMA / DIVISOR
            = 100 MHz / 4
            = 25 MHz

Tempo por pixel = 1 / 25 MHz = 40 ns

Tempo por linha = 800 × 40 ns = 32 µs
Frequência de linha = 1 / 32 µs = 31.25 kHz

Tempo por frame = 525 × 32 µs = 16.8 ms
Refresh Rate = 1 / 16.8 ms ≈ 59.52 Hz ✓ (dentro da tolerância de 60 Hz)
```

### 5.3 Resumo de Recursos

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              RESUMO DE RECURSOS                                            │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   Pixel Clock Eficaz:    25 MHz                                                            │
│   Linhas por Frame:      525                                                              │
│   Colunas por Linha:     800                                                              │
│   Refresh Rate:          59.52 Hz                                                         │
│   Pixels Totais/Frame:   525 × 800 = 420.000 pixels                                       │
│   Taxa de Pixels:        420.000 × 59.52 ≈ 25 MHz                                        │
│                                                                                             │
│   Pixels Visíveis/Frame: 640 × 480 = 307.200 pixels                                      │
│   Eficiência de Display:  307.200 / 420.000 ≈ 73.1%                                      │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. vga_sync: Gerador de Sincronismo

### 6.1 Interface do Módulo

```vhdl
entity vga_sync is
    port (
        clk      : in  std_logic;                    -- Clock: 100MHz
        rst      : in  std_logic;                    -- Reset
        h_count  : out integer range 0 to 799;       -- Contador horizontal
        v_count  : out integer range 0 to 524;       -- Contador vertical
        h_sync   : out std_logic;                    -- Sync horizontal
        v_sync   : out std_logic;                    -- Sync vertical
        video_on : out std_logic                     -- Área ativa
    );
end entity;
```

### 6.2 Arquitetura Interna

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    vga_sync                                               │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   clk ─────────┐                                                                             │
│               │                                                                             │
│               │    ┌───────────────────────────────────────────────────────────────────┐   │
│               ├───▶│           DIVISOR DE FREQUÊNCIA (÷4)                           │   │
│               │    │                                                               │   │
│               │    │   count_div: 0 → 1 → 2 → 3 → 0 → 1 → ...                      │   │
│               │    │   pixel_en:   0   0   0   1   0   0   ...                      │   │
│               │    │                         ▲                                        │   │
│               │    └───────────────────────┼───────────────────────────────────────┘   │
│               │                            │                                              │
│               │                            ▼                                              │
│               │    ┌───────────────────────────────────────────────────────────────────┐   │
│               │    │                    CONTADORES                                    │   │
│               │    │                                                               │   │
│               │    │   h_cnt_reg: 0 → ... → 799 → 0 → ... (incrementa com pixel_en) │   │
│               │    │   v_cnt_reg: 0 → ... → 524 → 0 → ... (incrementa quando h=799) │   │
│               │    │                                                               │   │
│               │    │   ┌───────────────────────────────────────────────────────┐   │   │
│               │    │   │ if pixel_en = '1' then                                │   │   │
│               │    │   │   if h_cnt_reg = 799 then h_cnt_reg <= 0;           │   │   │
│               │    │   │      if v_cnt_reg = 524 then v_cnt_reg <= 0;        │   │   │
│               │    │   │   else v_cnt_reg <= v_cnt_reg + 1;                  │   │   │
│               │    │   │   else h_cnt_reg <= h_cnt_reg + 1;                  │   │   │
│               │    │   │ end if;                                              │   │   │
│               │    │   └───────────────────────────────────────────────────────┘   │   │
│               │    │                                                               │   │
│               │    └───────────────────────────────────────────────────────────────────┘   │
│               │                                                                             │
│               │                            h_count ────────────────┐                      │
│               │                            v_count ────────────────┤                      │
│               │                                                 │                        │
│               │    ┌───────────────────────────────────────────────────────────────────┐   │
│               │    │                    LÓGICA COMBINACIONAL                           │   │
│               │    │                                                               │   │
│               │    │   h_sync  <= '0' when (h_count >= 656 and h_count < 752)      │   │
│               │    │           else '1';                                           │   │
│               │    │                                                               │   │
│               │    │   v_sync  <= '0' when (v_count >= 490 and v_count < 492)      │   │
│               │    │           else '1';                                           │   │
│               │    │                                                               │   │
│               │    │   video_on <= '1' when (h_count < 640 and v_count < 480)      │   │
│               │    │              else '0';                                        │   │
│               │    │                                                               │   │
│               │    └───────────────────────────────────────────────────────────────────┘   │
│               │                                                                             │
│               └─── clk                                                                       │
│                                                                                             │
│                         h_sync ────────────────┐                                          │
│                         v_sync ────────────────┤                                          │
│                         video_on ──────────────┘                                          │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.3 Implementação VHDL

```vhdl
architecture rtl of vga_sync is
    signal pixel_en   : std_logic;
    signal count_div  : integer range 0 to 3 := 0;
    signal h_cnt_reg  : integer range 0 to 799 := 0;
    signal v_cnt_reg  : integer range 0 to 524 := 0;
begin

    -- Divisor de Frequência (100MHz -> 25MHz)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count_div <= 0;
                pixel_en <= '0';
            else
                if count_div = 3 then
                    count_div <= 0;
                    pixel_en <= '1';  -- Pulso a cada 4 ciclos
                else
                    count_div <= count_div + 1;
                    pixel_en <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Contadores Horizontal e Vertical
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                h_cnt_reg <= 0;
                v_cnt_reg <= 0;
            elsif pixel_en = '1' then
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
            end if;
        end if;
    end process;

    -- Saídas
    h_count <= h_cnt_reg;
    v_count <= v_cnt_reg;

    -- Sincronismo (Polaridade Negativa)
    h_sync <= '0' when (h_cnt_reg >= 656 and h_cnt_reg < 752) else '1';
    v_sync <= '0' when (v_cnt_reg >= 490 and v_cnt_reg < 492) else '1';

    -- Área Ativa de Vídeo
    video_on <= '1' when (h_cnt_reg < 640 and v_cnt_reg < 480) else '0';

end architecture;
```

---

## 7. Divisor de Clock

### 7.1 Necessidade do Divisor

```
Clock do Sistema:  100 MHz (T = 10 ns)
Pixel Clock:        25 MHz (T = 40 ns)

Razão: 100 / 25 = 4
```

### 7.2 Implementação

```vhdl
-- Divisor por 4 (50% duty cycle)
process(clk)
begin
    if rising_edge(clk) then
        if count_div = 3 then
            count_div <= 0;
            pixel_en <= '1';  -- Pulso de 1 ciclo a cada 4
        else
            count_div <= count_div + 1;
            pixel_en <= '0';
        end if;
    end if;
end process;
```

### 7.3 Diagrama de Temporização do Divisor

```
clk:        ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐
            │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │
            │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │
            └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘
            ─────► ciclos: 0     1     2     3     0     1     2     3

count_div:  0     1     2     3     0     1     2     3     0     1     2     3
            ──────────────────────────── ──────────────────────────── ────────────
            │ 0   │ 1   │ 2   │ 3   │ 0   │ 1   │ 2   │ 3   │ 0   │ 1   │ 2   │

pixel_en:   0     0     0     1     0     0     0     1     0     0     0     1
            ────────────────     ────────────────     ────────────────     ──────
            │   OFF    │ ON │   │   OFF    │ ON │   │   OFF    │ ON │   │ OFF │
```

---

## 8. video_ram: Memória de Vídeo

### 8.1 Conceito de Dual-Port RAM

A **Dual-Port RAM** permite acesso simultâneo de duas entidades independentes:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              DUAL-PORT RAM (VIDEO_RAM)                                       │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                                     │   │
│   │                          MEMÓRIA DE VÍDEO                                           │   │
│   │                          (Block RAM)                                                │   │
│   │                                                                                     │   │
│   │   ┌───────────────────────────────────────────────────────────────────────────┐   │   │
│   │   │                                                                           │   │   │
│   │   │   Endereço 0   │  Endereço 1   │  ...  │  Endereço 76799  │              │   │   │
│   │   │   (7:0)       │   (7:0)       │        │   (7:0)          │              │   │   │
│   │   │   RRRGGGBB    │   RRRGGGBB    │        │   RRRGGGBB       │              │   │   │
│   │   │                                                                           │   │   │
│   │   └───────────────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                                     │   │
│   │                                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                             │
│                   ▲                                           ▲                             │
│                   │                                           │                             │
│           ┌───────┴───────┐                         ┌───────┴───────┐                     │
│           │   PORTA A     │                         │   PORTA B     │                     │
│           │   (Escrita)   │                         │   (Leitura)   │                     │
│           │               │                         │               │                     │
│           │ we_a          │                         │               │                     │
│           │ addr_a[16:0]  │                         │ addr_b[16:0]  │                     │
│           │ data_a[7:0]   │                         │ data_b[7:0]   │                     │
│           │               │                         │               │                     │
│           └───────┬───────┘                         └───────┬───────┘                     │
│                   │                                           │                             │
│                   ▼                                           ▼                             │
│           ┌─────────────┐                             ┌─────────────┐                     │
│           │    CPU      │                             │    VGA      │                     │
│           │  (RISC-V)  │                             │  Controller │                     │
│           │             │                             │             │                     │
│           │  Escrita    │                             │  Leitura    │                     │
│           │  Assíncrona │                             │  Contínua   │                     │
│           └─────────────┘                             └─────────────┘                     │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Interface do Módulo

```vhdl
entity video_ram is
    generic (
        ADDR_WIDTH : integer := 17;  -- 2^17 = 131072 endereços (usa 76800)
        DATA_WIDTH : integer := 8    -- 8 bits: RRRGGGBB
    );
    port (
        clk      : in std_logic;
        
        -- Porta A: Processador (Escrita)
        we_a     : in std_logic;
        addr_a   : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_a   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Porta B: VGA Core (Leitura)
        addr_b   : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_b   : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity;
```

### 8.3 Implementação (Inferência de BRAM)

```vhdl
architecture rtl of video_ram is
    type ram_type is array (0 to (2**ADDR_WIDTH)-1) 
                   of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin

    process(clk)
    begin
        if rising_edge(clk) then
            -- Escrita do Processador (Write-First)
            if we_a = '1' then
                ram(to_integer(unsigned(addr_a))) <= data_a;
            end if;
            
            -- Leitura do VGA (Sempre ativa)
            data_b <= ram(to_integer(unsigned(addr_b)));
        end if;
    end process;

end architecture;
```

### 8.4 Formato de Dados de Pixel

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    FORMATO DE PIXEL (8 bits)                                │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   bit:    7    6    5    4    3    2    1    0                                            │
│          ┌────┬────┬────┬────┬────┬────┬────┬────┐                                           │
│          │ R2 │ R1 │ R0 │ G2 │ G1 │ G0 │ B1 │ B0 │                                           │
│          ├────┴────┴────┴────┴────┴────┴────┴────┤                                           │
│          │         Vermelho (3 bits)           │         Verde (3 bits)        │ Azul (2 bits) │
│          └─────────────────────────────────────┴─────────────────────────────────┘              │
│                                                                                             │
│   Com 3 bits para R e G: 2^3 = 8 níveis cada = 256 cores possíveis                          │
│   Com 2 bits para B: 2^2 = 4 níveis                                                                     │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. vga_peripheral: Integração

### 9.1 Arquitetura Completa

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        VGA_PERIPHERAL                                                   │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                         │
│   BARRAMENTO DO SoC                              SAÍDAS VGA                                           │
│   ┌──────────────────┐                           ┌─────────────────────────────────────────────┐       │
│   │                  │                           │                                             │       │
│   │  we_i            │───┐                       │   vga_r_o[3:0]  (Vermelho 4 bits)         │       │
│   │  vld_i           │   │                       │   vga_g_o[3:0]  (Verde 4 bits)           │       │
│   │  addr_i[16:0]    │   │   ┌───────────────┐  │   vga_b_o[3:0]  (Azul 4 bits)            │       │
│   │  data_i[31:0]    │───┼──▶│  Alinhamento  │  │   vga_hs_o     (H_SYNC)                 │       │
│   │                  │   │   │  de Dados     │  │   vga_vs_o     (V_SYNC)                 │       │
│   │                  │   │   └───────┬───────┘  └─────────────────────────────────────────────┘       │
│   │                  │   │           │                                                               │
│   │  data_o[31:0]    │◀──┤           │                                                               │
│   │  rdy_o           │◀──┤           │                                                               │
│   │                  │   │           │                                                               │
│   └──────────────────┘   │           ▼                                                               │
│                           │   ┌───────────────┐                                                       │
│                           │   │               │                                                       │
│                           └──▶│    s_vram_we   │                                                       │
│                               │   (we_i AND    │                                                       │
│                               │    vld_i)      │                                                       │
│                               └───────┬────────┘                                                       │
│                                       │                                                                │
│   ┌───────────────────────────────────┼───────────────────────────────────────────────────────────┐   │
│   │                                   ▼                                                               │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                                                                                         │ │   │
│   │   │                            DUAL-PORT VIDEO RAM                                          │ │   │
│   │   │                            (320 × 240 = 76.800 bytes)                                   │ │   │
│   │   │                                                                                         │ │   │
│   │   │   ┌─────────────────────────────────────────────────────────────────────────────────┐ │ │   │
│   │   │   │                                                                         │ │ │   │
│   │   │   │   PORTA A (CPU)                      PORTA B (VGA)                          │ │ │   │
│   │   │   │   ┌───────────────┐                  ┌───────────────┐                      │ │ │   │
│   │   │   │   │               │                  │               │                      │ │ │   │
│   │   │   │   │  s_vram_we    │                  │               │                      │ │ │   │
│   │   │   │   │  addr_i       │                  │  vram_addr    │                      │ │ │   │
│   │   │   │   │  s_data_align │                  │               │                      │ │ │   │
│   │   │   │   │               │                  │  vram_data    │──────────────────────┼─┘ │   │
│   │   │   │   └───────────────┘                  └───────────────┘                      │     │   │
│   │   │   │                                                                                 │     │   │
│   │   │   └─────────────────────────────────────────────────────────────────────────────────┘     │   │
│   │   │                                                                                         │     │   │
│   │   └───────────────────────────────────────────────────────────────────────────────────────────┘     │   │
│   │                                                                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                                        VGA_SYNC                                                           │   │
│   │   ┌────────────────────────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                                                                                                │  │   │
│   │   │   100MHz ──▶ Divisor ÷4 ──▶ pixel_en ──▶ Contadores H(0-799) e V(0-524)                      │  │   │
│   │   │                                                                                                │  │   │
│   │   │                              ┌────────────────┐                                               │  │   │
│   │   │                              │                │                                               │  │   │
│   │   │   pixel_x ◀─────────────────▶│  h_count       │                                               │  │   │
│   │   │   pixel_y ◀─────────────────▶│  v_count       │                                               │  │   │
│   │   │   vga_hs_o ◀────────────────│  h_sync        │                                               │  │   │
│   │   │   s_vsync ◀─────────────────│  v_sync        │                                               │  │   │
│   │   │   video_on ◀────────────────│  video_on      │                                               │  │   │
│   │   │                              │                │                                               │  │   │
│   │   │                              └────────────────┘                                               │  │   │
│   │   │                                                                                                │  │   │
│   │   └────────────────────────────────────────────────────────────────────────────────────────────────┘  │   │
│   │                                                                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Cálculo do Endereço de Memória

O sistema utiliza **escalonamento 2:1** - cada pixel da VRAM (320×240) é exibido como 2×2 pixels no monitor (640×480).

```vhdl
-- Coordenadas escaladas (640x480 → 320x240)
x_scaled <= pixel_x / 2;  -- 0-799 → 0-399
y_scaled <= pixel_y / 2;  -- 0-524 → 0-261

-- Endereço linear: Row × Width + Column
vram_addr <= std_logic_vector(to_unsigned(y_scaled * 320 + x_scaled, 17));
```

**Exemplo de Cálculo:**

```
pixel_x = 100, pixel_y = 50 (coordenadas VGA)
x_scaled = 100 / 2 = 50
y_scaled = 50 / 2 = 25

vram_addr = 25 × 320 + 50 = 8.050
```

### 9.3 Conversão de Cor

```vhdl
-- VRAM: RRRGGGBB (3-3-2 bits)
-- VGA:  RRRR (4 bits), GGGG (4 bits), BBBB (4 bits)

-- Extensão de bits:Replication do bit mais significativo
vga_r_o <= vram_data(7 downto 5) & "0";  -- RRR → RRRR
vga_g_o <= vram_data(4 downto 2) & "0";  -- GGG → GGGG
vga_b_o <= vram_data(1 downto 0) & "00"; -- BB → BBBB
```

**Diagrama de Conversão:**

```
VRAM (8 bits)                          VGA (4+4+4 bits)
┌─────────────┐                        ┌─────────────────────┐
│ R2 R1 R0 G2 │ ─────────────────────▶│ R3 R2 R1 R0 = R2 R1 │
│ G1 G0 B1 B0 │                        │     R0   R0        │
└─────────────┘                        └─────────────────────┘
                                           Vermelho 4 bits

┌─────────────┐                        ┌─────────────────────┐
│ R2 R1 R0 G2 │ ─────────────────────▶│ G3 G2 G1 G0 = G2 G1 │
│ G1 G0 B1 B0 │                        │     G0   G0        │
└─────────────┘                        └─────────────────────┘
                                           Verde 4 bits

┌─────────────┐                        ┌─────────────────────┐
│ R2 R1 R0 G2 │ ─────────────────────▶│ B3 B2 B1 B0 = B1 B0 │
│ G1 G0 B1 B0 │                        │     00   00        │
└─────────────┘                        └─────────────────────┘
                                           Azul 4 bits
```

---

## 10. Temporização de Saída VGA

### 10.1 Sinais de Sincronismo

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                         TEMPORIZAÇÃO COMPLETA DE SAÍDA                                      │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   Ciclo de Pixel:      0          640        656        752        800                     │
│                        │           │          │          │          │                       │
│                        │    ATIVA  │  SYNC    │  SYNC    │  SYNC    │                       │
│                        │           │  HORIZ.  │  HORIZ.  │  HORIZ.  │                       │
│                        ▼           ▼          ▼          ▼          ▼                       │
│   H_SYNC:              1           1          0          0          1                       │
│                        │           │          │          │          │                       │
│                        │           │      (656-752)     │          │                       │
│                        │           │       ativo baixo   │          │                       │
│                        │           │          │          │          │                       │
│                        │           │          │          │          │                       │
│                        │           │          │          │          │                       │
│   V_SYNC:              1           1          1          1          1                       │
│   (linha 490)          │           │          │          │          │                       │
│                        │           │          │          │          │                       │
│   V_SYNC:              1           1          1          1          1                       │
│   (linha 491)          │           │          │          │          │                       │
│                        │           │          │          │          │                       │
│   V_SYNC:              1           1          0          0          1                       │
│   (linha 492)          │           │          │          │          │                       │
│                        │           │      (490-492)     │          │                       │
│                        │           │       ativo baixo   │          │                       │
│                        │           │          │          │          │                       │
│   video_on:            1           1          0          0          0                       │
│                        │           │          │          │          │                       │
│   vga_r/g/b_o:         cor         cor        000        000        000                     │
│                        (dados)     (dados)    (preto)    (preto)    (preto)               │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Polaridade dos Sinais

| Sinal | Polaridade | Descrição |
|-------|------------|-----------|
| H_SYNC | **Negativa** | Pulso ativo em '0' (656-752 ciclos) |
| V_SYNC | **Negativa** | Pulso ativo em '0' (490-492 linhas) |

---

## 11. Contenção de Memória

### 11.1 O Problema

Em sistemas com memória de vídeo compartilhada, pode ocorrer **contenção** quando CPU e controlador VGA tentam acessar a mesma posição de memória simultaneamente:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              CONTENÇÃO DE MEMÓRIA                                           │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌─────────────────────┐              ┌─────────────────────┐                              │
│   │       CPU          │              │   VGA Controller    │                              │
│   │    (RISC-V)       │              │                     │                              │
│   │                   │              │                     │                              │
│   │  Escrita: addr=X  │              │  Leitura: addr=Y    │                              │
│   │  data=cor         │              │  → dados pixels    │                              │
│   └─────────┬───────────┘              └─────────┬───────────┘                              │
│             │                                    │                                          │
│             │         ┌─────────────────┐         │                                          │
│             │         │                 │         │                                          │
│             │         │   MEMÓRIA      │         │                                          │
│             │         │   (Single-Port │         │                                          │
│             │         │    ou False    │         │                                          │
│             │         │    Dual-Port) │         │                                          │
│             │         │                 │         │                                          │
│             │         │                 │         │                                          │
│             │         └─────────────────┘         │                                          │
│             │                                    │                                          │
│             └────────────────────────────────────┘                                          │
│                           ▲                                                             │
│                           │                                                             │
│                    CONFLITO!                                                             │
│                    Quem acessa primeiro?                                                  │
│                                                                                           │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 11.2 Solução Arquitetural: Dual-Port RAM

A **Dual-Port RAM** resolve o problema de contenção por design:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                         ARQUITETURA DUAL-PORT RESOLVE CONTENÇÃO                            │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌─────────────────────┐              ┌─────────────────────┐                              │
│   │       CPU          │              │   VGA Controller    │                              │
│   │    (RISC-V)       │              │                     │                              │
│   │                   │              │                     │                              │
│   │  Escrita:         │              │  Leitura contínua:  │                              │
│   │  addr_a[X]        │              │  addr_b[Y]          │                              │
│   │  data_a[cor]      │              │  data_b[pixels]     │                              │
│   └─────────┬───────────┘              └─────────┬───────────┘                              │
│             │                                    │                                          │
│             │                                    │                                          │
│             │     ┌───────────────────────────────┴───────────────────────────────┐        │
│             │     │                                                               │        │
│             │     │                        MEMÓRIA                               │        │
│             │     │                                                               │        │
│             │     │     ┌─────────────────────────────────────────────────┐      │        │
│             │     │     │                                                 │      │        │
│             │     │     │                                                 │      │        │
│             │     │     │              Bloco de Memória                     │      │        │
│             │     │     │              (BRAM FPGA)                          │      │        │
│             │     │     │                                                 │      │        │
│             │     │     │                                                 │      │        │
│             │     │     └─────────────────────────────────────────────────┘      │        │
│             │     │                                                               │        │
│             │     └───────────────────────────────────────────────────────────────┘        │
│             │                                                                       │
│             │                                                                       │
└─────────────┴───────────────────────────────────────────────────────────────────────────┘
```

### 11.3 Análise de Casos

| Caso | CPU | VGA | Resultado |
|------|-----|-----|-----------|
| Endereços diferentes | Escrita em X | Leitura em Y | OK - Acesso simultâneo sem conflito |
| Mesmo endereço | Escrita em X | Leitura em X | OK - Write-First retorna novo valor |
| Ambos querem escrever | Escrita em X | Escrita em X | OK - Portas diferentes (CPU só escreve) |

### 11.4 Mecanismo Write-First

Quando CPU escreve no mesmo endereço que VGA está lendo:

```vhdl
-- Write-First: O dado escrito está disponível imediatamente na saída
if we_a = '1' then
    ram(addr_a) <= data_a;  -- Escrita
end if;
data_b <= ram(addr_b);       -- Leitura retorna novo valor se mesmo addr
```

**Resultado:** O VGA Controller sees immediately the new color written by CPU, sem necessidade de arbitragem ou wait states.

### 11.5 Conclusão Arquitetural

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                               CONCLUSÃO                                                     │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   A Dual-Port RAM garante:                                                                 │
│                                                                                             │
│   1. OPERAÇÃO SIMULTÂNEA: CPU e VGA acessam a memória ao mesmo tempo                      │
│                                                                                             │
│   2. SEM ARBITRAGEM: Não há lógica de prioridade ou wait states                            │
│                                                                                             │
│   3. SEM PERDA DE DADOS: Leituras e escritas coexistem sem conflitos                        │
│                                                                                             │
│   4. PERFORMANCE MÁXIMA: VGA lê continuamente a 25 MHz sem bloquear CPU                    │
│                                                                                             │
│   CUSTO: Utilização de 2 portas de BRAM (comum em FPGAs modernas)                        │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 12. Referências

- **RTL Sources:**
  - `rtl/perips/vga/vga_sync.vhd`
  - `rtl/perips/vga/video_ram.vhd`
  - `rtl/perips/vga/vga_peripheral.vhd`
- **IEEE Std 1076:** VHDL Language Reference Manual
- **VESA Standards:** Timing Specifications for VGA Displays

---
