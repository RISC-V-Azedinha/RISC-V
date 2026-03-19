# UART Controller - Microarquitetura

**Módulo:** `uart_controller.vhd`  
**Autor:** André Maiolini  
**Data:** 01/01/2026  
**Versão:** 1.0

---

## 1. Visão Geral

O **UART Controller** é um periférico de comunicação serial assíncrona que implementa as funções de **Transmissor (TX)** e **Receptor (RX)** em um único módulo de hardware.

### 1.1 Características Principais

| Característica | Valor |
|----------------|-------|
| **Padrão** | UART (Universal Asynchronous Receiver-Transmitter) |
| **Formato de Frame** | 8N1 (8 bits de dados, sem paridade, 1 stop bit) |
| **Baud Rate Padrão** | 115.200 bps |
| **Frequência de Clock** | 100 MHz (configurável) |
| **Buffer de Recepção** | FIFO de 64 bytes (configurável) |
| **Interrupções** | Geradas quando dados estão disponíveis na FIFO |

---

## 2. Teoria do Protocolo UART

### 2.1 Estrutura do Frame UART

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FRAME UART (8N1)                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│   IDLE (High)                                                               │
│   │                                                                         │
│   ▼                                                                         │
│   ┌───────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬───┐ │
│   │ START │   D0    │   D1    │   D2    │   D3    │   D4    │   D5    │...│ │
│   │  BIT  │ (LSB)   │         │         │         │         │         │   │ │
│   │  '0'  │         │         │         │         │         │         │   │ │
│   └───────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴───┘ │
│       │                                                                         │
│       ▼                                                                         │
│   Start Bit (sempre '0')                                                     │
│       │                                                                         │
│       └──┬─────────┬──┬────────┬──┴──┐                                       │
│          └─────────┘  └────────┘    │                                       │
│                                     ▼                                        │
│                              Stop Bit (sempre '1')                           │
│                                                                             │
│   IDLE (High) ◄────────────────────────────────────────────────────────────│
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Componentes do Frame

| Componente | Descrição | Nível Lógico |
|------------|-----------|--------------|
| **Start Bit** | Marca o início da transmissão | `0` (Space) |
| **Data Bits** | Dados úteis (8 bits, LSB primeiro) | `0` ou `1` |
| **Stop Bit** | Marca o fim da transmissão | `1` (Mark) |
| **Idle** | Linha em repouso | `1` (Mark) |

### 2.3 Baud Rate (Taxa de Transmissão)

```
Baud Rate = Bits por segundo (bps)
Exemplo: 115.200 baud = 115.200 bits/segundo

Tempo por bit = 1 / 115.200 = 8,68 µs/bit
```

---

## 3. Diagrama de Blocos

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              UART CONTROLLER                                         │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   BARRAMENTO DO SOC                              PINOS EXTERNOS                      │
│   ┌──────────────────┐                           ┌────────────────────┐              │
│   │    addr_i[3:0]  │─────────────────────────▶│                    │              │
│   │    data_i[31:0] │─────────────────────────▶│                    │              │
│   │    we_i, vld_i  │─────────────────────────▶│   LOGICA DE        │              │
│   │                  │                           │   CONTROLE         │              │
│   │    data_o[31:0] │◀──────────────────────────│                    │              │
│   │    rdy_o, irq_o │◀──────────────────────────│                    │              │
│   └──────────────────┘                           └────────┬───────────┘              │
│                                                          │                          │
│                                                          ▼                          │
│   ┌───────────────────────────────────────────────────────────────────────────────┐ │
│   │                         ARQUITETURA INTERNA                                   │ │
│   │                                                                               │ │
│   │   ┌─────────────────┐              ┌─────────────────┐                       │ │
│   │   │   TX FSM        │              │   RX FSM        │                       │ │
│   │   │  TX_IDLE/START/│   uart_tx     │  RX_IDLE/START/ │   uart_rx             │ │
│   │   │  DATA/STOP     │──────┐        │  DATA/STOP      │◀──────┐              │ │
│   │   └─────────────────┘      │       └───────┬───────┘      │              │ │
│   │           │                │               │              │              │ │
│   │           │ shift register│               │ shift register│              │ │
│   │           ▼                │               ▼              │              │ │
│   │   ┌─────────────────┐      │       ┌─────────────────┐    │              │ │
│   │   │  tx_shifter[7:0]│      │       │  rx_shifter[7:0]│    │              │ │
│   │   └────────┬────────┘      │       └────────┬────────┘    │              │ │
│   │            │               │                │              │              │ │
│   │            └────────────────┼────────────────┘              │              │ │
│   │                             │                               │              │ │
│   │                    ┌────────┴────────┐                      │              │ │
│   │                    │                 │                      │              │ │
│   │                    ▼                 ▼                      │              │ │
│   │            ┌──────────────┐  ┌──────────────┐              │              │ │
│   │            │  TX_DATA_REG │  │     FIFO     │              │              │ │
│   │            │  (latch)     │  │   (buffer)   │              │              │ │
│   │            └──────────────┘  └──────┬───────┘              │              │ │
│   │                                      │                      │              │ │
│   │                                      ▼                      │              │ │
│   │                               ┌──────────────┐               │              │ │
│   │                               │  FIFO_MEM    │               │              │ │
│   │                               │  [0:63][7:0] │               │              │ │
│   │                               └──────────────┘               │              │ │
│   │                                                          │              │ │
│   └──────────────────────────────────────────────────────────┴─────────────────┘ │
│                                                                                 │ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                                                                 
                    UART RX PIN ◀────────────────────────────────────────────────
```

---

## 4. Mapa de Memória

### 4.1 Registrador DATA (Offset 0x0)

| Operação | Comportamento |
|----------|---------------|
| **WRITE** | Escreve byte na latch TX. Se `TX_BUSY = 0`, inicia transmissão automaticamente |
| **READ** | Lê byte na cabeça da FIFO (operação **peek** - não remove da fila) |

### 4.2 Registrador STATUS (Offset 0x4)

| Bit | Nome | Direção | Descrição |
|-----|------|---------|-----------|
| 0 | TX_BUSY | Leitura | `1` = Transmissor ocupado, `0` = Livre |
| 1 | RX_VALID | Leitura | `1` = FIFO contém dados, `0` = FIFO vazia |
| 2 | FLUSH | Escrita | `1` = Limpa toda a FIFO |

### 4.3 Sequências de Uso

**Transmissão (TX):**
```c
while (STATUS & TX_BUSY);     // Aguardar TX livre
DATA = byte_to_send;         // Inicia transmissão
```

**Recepção (RX):**
```c
while (!(STATUS & RX_VALID)); // Aguardar dados
byte = DATA;                  // Ler (peek)
STATUS = RX_POP;             // Avançar fila
```

---

## 5. Geração de Baud Rate

### 5.1 Cálculo do Período de Bit

O hardware utiliza um **divisor de frequência** para gerar o Baud Rate:

```vhdl
constant c_bit_period : integer := CLK_FREQ / BAUD_RATE;
```

**Cálculo para 115200 baud @ 100 MHz:**

```
CLK_FREQ   = 100.000.000 Hz (100 MHz)
BAUD_RATE  = 115.200 bps

c_bit_period = 100.000.000 / 115.200
             = 868 ciclos (arredondado)
```

### 5.2 Equação Geral

```
Período de 1 bit (ciclos) = ⌊ CLK_FREQ ÷ BAUD_RATE ⌋
Período de 1 bit (ns)     = c_bit_period × (1 / CLK_FREQ)
```

| Baud Rate | CLK_FREQ | c_bit_period | Tempo/bit |
|-----------|----------|--------------|-----------|
| 115.200 | 100 MHz | 868 | 8,68 µs |
| 57.600 | 100 MHz | 1736 | 17,36 µs |
| 9.600 | 100 MHz | 10417 | 104,17 µs |

---

## 6. Transmissor (TX)

### 6.1 Arquitetura do TX

```
┌─────────────────────────────────────────────────────────────────┐
│                     TRANSMITTER (TX)                           │
├─────────────────────────────────────────────────────────────────┤
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐      │
│   │ TX_DATA    │     │   TX FSM    │     │   SHIFT     │      │
│   │ LATCH      │────▶│  (Control)  │────▶│  REGISTER   │─────▶│
│   │            │     │             │     │ [7:0]       │      │
│   └─────────────┘     └──────┬──────┘     └─────────────┘      │
│                              │                                   │
│                              │ timer_en                          │
│                              ▼                                   │
│                    ┌─────────────────┐                         │
│                    │   BIT TIMER     │◀── c_bit_period          │
│                    │   [0..868]      │                          │
│                    └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Máquina de Estados TX

```
              ┌──────────────────┐    tx_start_pulse=1         │
              │                  │◀─────────────────────────────┐│
              │    TX_IDLE       │                              ││
              │  uart_tx_pin='1' │                              ││
              │  tx_busy_flag='0'│                              ││
              └────────┬─────────┘                              ││
                       │                                         │
                       │ timer=0                                 │
                       ▼                                         │
              ┌──────────────────┐    timer = c_bit_period - 1  ││
              │                  │──────────────────────────────┐│
              │    TX_START       │                               ││
              │  uart_tx_pin='0' │                               ││
              └────────┬─────────┘                               ││
                       │                                         │
                       │ timer=0, bit_idx=0                      │
                       ▼                                         │
              ┌──────────────────┐    bit_idx=7                  ││
              │                  │──────────────────────────────┐│
              │    TX_DATA       │                               ││
              │  uart_tx_pin =   │                               ││
              │  tx_shifter[n]   │                               ││
              └────────┬─────────┘                               ││
                       │                                         │
                       │ timer=0                                 │
                       ▼                                         │
              ┌──────────────────┐    timer = c_bit_period - 1    │
              │                  │──────────────────────────────┘│
              │    TX_STOP       │                               │
              │  uart_tx_pin='1' │                               │
              └────────┬─────────┘                               │
                       │                                         │
                       ▼                                         │
              ┌──────────────────┐                              │
              │    TX_IDLE       │                              │
              └──────────────────┘                              │
```

### 6.3 Implementação VHDL

```vhdl
type t_tx_state is (TX_IDLE, TX_START, TX_DATA, TX_STOP);

process(clk)
begin
    if rising_edge(clk) then
        case tx_state is
            when TX_IDLE =>
                uart_tx_pin <= '1';
                if tx_start_pulse = '1' then
                    tx_shifter   <= r_tx_data_latch;
                    tx_state     <= TX_START;
                    tx_busy_flag <= '1';
                end if;
                tx_timer <= 0;

            when TX_START =>
                uart_tx_pin <= '0';
                if tx_timer < c_bit_period - 1 then
                    tx_timer <= tx_timer + 1;
                else
                    tx_timer <= 0;
                    tx_state <= TX_DATA;
                    tx_bit_idx <= 0;
                end if;

            when TX_DATA =>
                uart_tx_pin <= tx_shifter(tx_bit_idx);
                if tx_timer < c_bit_period - 1 then
                    tx_timer <= tx_timer + 1;
                else
                    tx_timer <= 0;
                    if tx_bit_idx < 7 then
                        tx_bit_idx <= tx_bit_idx + 1;
                    else
                        tx_state <= TX_STOP;
                    end if;
                end if;

            when TX_STOP =>
                uart_tx_pin <= '1';
                if tx_timer < c_bit_period - 1 then
                    tx_timer <= tx_timer + 1;
                else
                    tx_state <= TX_IDLE;
                end if;
        end case;
    end if;
end process;
```

---

## 7. Receptor (RX)

### 7.1 Desafios da Recepção Assíncrona

1. **Cross-Domain Crossing (CDC):** O sinal `uart_rx_pin` vem de fora do domínio de clock
2. **Sincronização de Tempo:** O receptor deve amostrar os bits **no centro** de cada período

### 7.2 Sincronizador Cross-Domain (2-FF)

```vhdl
signal rx_pin_sync : std_logic_vector(1 downto 0);

process(clk)
begin
    if rising_edge(clk) then
        rx_pin_sync <= rx_pin_sync(0) & uart_rx_pin;
    end if;
end process;

rx_bit_val <= rx_pin_sync(1);
```

**Diagrama:**
```
uart_rx_pin (assíncrono) ──┬──▶ FF1 ──▶ FF2 ──▶ rx_pin_sync(0)
                           │       (async) (sync)
                           └──▶ FF2 ──▶ FF3 ──▶ rx_pin_sync(1) = rx_bit_val
```

### 7.3 Máquina de Estados RX

```
              ┌──────────────────┐                              │
              │    RX_IDLE       │                              │
              │  rx_bit_val='1'  │                              │
              └────────┬─────────┘                              │
                       │ rx_bit_val='0'                         │
                       ▼                                        │
              ┌──────────────────┐    timer = c_bit_period/2   │
              │                  │    AND rx_bit_val='1'         ││
              │   RX_START       │──────────────────────────────┐│
              │  (validação)     │                              ││
              │  Timer: 0→433    │    timer = c_bit_period/2   ││
              │  (meio período)  │    AND rx_bit_val='0'        ││
              │                  │    (start bit confirmado)     ││
              └────────┬─────────┘                              ││
                       │                                        │
                       ▼                                        │
              ┌──────────────────┐    bit_idx=7                  ││
              │                  │──────────────────────────────┐│
              │   RX_DATA        │                               ││
              │  Amostra bits    │                               ││
              │  no CENTRO       │                               ││
              │  rx_shifter[n]=  │                               ││
              │    rx_bit_val    │                               ││
              └────────┬─────────┘                               ││
                       │                                        │
                       ▼                                        │
              ┌──────────────────┐    timer = c_bit_period - 1   │
              │                  │──────────────────────────────┘│
              │   RX_STOP        │                               │
              │  w_wr_en <= '1'  │                               │
              └────────┬─────────┘                               │
                       ▼                                         │
              ┌──────────────────┐                               │
              │    RX_IDLE       │                               │
              └──────────────────┘                               │
```

---

## 8. Oversampling e Amostragem no Centro do Bit

### 8.1 O Problema

Sinais UART estão sujeitos a:
- **Ruído elétrico** (interferência eletromagnética)
- **Distorção de borda** (bordas não são perfeitamente verticais)
- **Jitter** (variações no tempo de chegada)

### 8.2 A Solução: Amostragem no Centro

A estratégia é amostrar cada bit **no meio de seu período**, onde o sinal está mais estável:

```
                INÍCIO DO BIT (borda)          CENTRO DO BIT          FIM DO BIT
                     │                              │                         │
                     ▼                              ▼                         ▼
                 ┌───────────────────────────────────────────────────────────────────┐
TX/RX Pin        │                                   │                                   │
                 ├───────────────────────────────────┼───────────────────────────────────┤
                 │                                   │          ┌──────────┐              │
                 │                                   │          │ AMOSTRA  │              │
                 │                                   │          │ SEGURA   │              │
                 │                                   │          └──────────┘              │
                 │                                   │                                   │
                 └───────────────────────────────────┴───────────────────────────────────┘
                                      ▲                    ▲
                                      │                    │
                                 BORDAS               CENTRO DO BIT
                                 (instável)            (amostragem ideal)
```

### 8.3 Cálculo do Ponto de Amostragem

**Para 115200 baud @ 100 MHz (c_bit_period = 868):**

```
Ponto de amostragem do Start Bit = c_bit_period / 2 = 868 / 2 = 434 ciclos

Código VHDL:
    if rx_timer < (c_bit_period / 2) - 1 then
        rx_timer <= rx_timer + 1;
    else
        if rx_bit_val = '0' then rx_state <= RX_DATA;
        else rx_state <= RX_IDLE;  -- Ruído
        end if;
    end if;
```

### 8.4 Análise de Robustez

```
Margem até borda esquerda = 434 ciclos = 4.340 ns
Margem até borda direita  = 868 - 434 = 434 ciclos = 4.340 ns

Margem de ruído = ±50% do período do bit!
```

---

## 9. Implementação VHDL Completa do RX

```vhdl
type t_rx_state is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
signal rx_state    : t_rx_state;
signal rx_timer    : integer range 0 to c_bit_period;
signal rx_bit_idx  : integer range 0 to 7;
signal rx_shifter  : std_logic_vector(7 downto 0);

process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            rx_state <= RX_IDLE;
            rx_timer <= 0;
            rx_bit_idx <= 0;
            rx_shifter <= (others => '0');
            w_wr_en <= '0';
        else
            w_wr_en <= '0';

            case rx_state is
                when RX_IDLE =>
                    rx_timer <= 0;
                    rx_bit_idx <= 0;
                    if rx_bit_val = '0' then
                        rx_state <= RX_START;
                    end if;

                when RX_START =>
                    if rx_timer < (c_bit_period / 2) - 1 then
                        rx_timer <= rx_timer + 1;
                    else
                        rx_timer <= 0;
                        if rx_bit_val = '0' then
                            rx_state <= RX_DATA;
                        else
                            rx_state <= RX_IDLE;
                        end if;
                    end if;

                when RX_DATA =>
                    if rx_timer < c_bit_period - 1 then
                        rx_timer <= rx_timer + 1;
                    else
                        rx_timer <= 0;
                        rx_shifter(rx_bit_idx) <= rx_bit_val;
                        if rx_bit_idx < 7 then
                            rx_bit_idx <= rx_bit_idx + 1;
                        else
                            rx_state <= RX_STOP;
                        end if;
                    end if;

                when RX_STOP =>
                    if rx_timer < c_bit_period - 1 then
                        rx_timer <= rx_timer + 1;
                    else
                        w_wr_en <= '1';
                        rx_state <= RX_IDLE;
                    end if;
            end case;
        end if;
    end if;
end process;
```

---

## 10. FIFO de Recepção

### 10.1 Arquitetura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            FIFO BUFFER                                  │
│                      (64 × 8 bits)                                      │
├─────────────────────────────────────────────────────────────────────────┤
│   ┌────────┐     ┌────────────────────────────────────────────┐         │
│   │        │     │                                            │         │
│   │  r_head│────▶│   w_wr_en='1'                              │         │
│   │  (ptr) │     │   r_fifo(r_head) <= rx_shifter            │         │
│   │        │     │                                            │         │
│   │   0    │     │   [0] [1] [2] ... [62] [63]              │         │
│   │        │     │   ┌────┬────┬────┬────┬───┬────┬────┐     │         │
│   │        │     │   │ 0x7B│ 0x41│ 0x00│    │    │    │     │         │
│   │        │     │   └────┴────┴────┴────┴───┴────┴────┘     │         │
│   │        │     │     ▲                               │       │         │
│   │        │     │     │                               │       │         │
│   │        │     │     │ r_head++                     │       │         │
│   │        │     │     │                               ▼       │         │
│   │        │     │   ┌────┐  r_tail (read ptr)                    │         │
│   │        │     │   │    │───────────────────────────────────────┼──────▶ data_o
│   │        │     │   │ 0  │  r_fifo(r_tail)                       │         │
│   │        │     │   └────┘                                      │         │
│   └────────┘     └────────────────────────────────────────────────────┘         │
│                                                                          │
│   r_count = número de itens na FIFO                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Flags de Status

```vhdl
w_fifo_full  <= '1' when r_count = FIFO_DEPTH else '0';
w_fifo_empty <= '1' when r_count = 0 else '0';
```

### 10.3 Contador de Itens

```vhdl
if w_wr_en = '1' and w_rd_en = '0' and w_fifo_full = '0' then
    r_count <= r_count + 1;
elsif w_wr_en = '0' and w_rd_en = '1' and w_fifo_empty = '0' then
    r_count <= r_count - 1;
end if;
```

---

## 11. Interface de Barramento

### 11.1 Protocolo de Handshake

```
CPU                                 UART Controller
───                                 ───────────────
1. vld_i='1'                       3. Detecta vld_i='1'
   + we_i, addr_i, data_i             (no clock edge)
                                     │
                                     ▼
                           4. rdy_o <= '1' (T+1)
                                     │
                                     ▼
2. Aguarda rdy_o='1' ◀───────────────┘
```

### 11.2 Mapeamento de Operações

| addr_i | we_i | Operação | Ação |
|--------|------|----------|------|
| 0x0 | 1 | WRITE DATA | Se `TX_BUSY=0`: inicia transmissão |
| 0x0 | 0 | READ DATA | `data_o(7:0) <= r_fifo(r_tail)` (peek) |
| 0x4 | 1 | WRITE CMD | `data_i(0)=1`: pop; `data_i(2)=1`: flush |
| 0x4 | 0 | READ STATUS | `data_o(0)<=TX_BUSY`, `data_o(1)<=RX_VALID` |

### 11.3 Interrupção

```vhdl
irq_o <= not w_fifo_empty;  -- Level-triggered quando há dados
```

---

## 12. Temporização TX

```
Ciclos:     IDLE    START    D0      D1      D2      D3      D4      D5      D6      D7      STOP
            │       │       │       │       │       │       │       │       │       │       │       │
       ─────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴──────
TX Pin      1       0       1       0       0       0       0       0       1       0       1       1
            │       │       │       │       │       │       │       │       │       │       │       │
       Idle │ Start │  LSB  │       │       │       │       │       │       │  MSB  │ Stop  │ Idle
             │       │       │       │       │       │       │       │       │       │       │
       ◄──────────────────────────────────────────────────────────────────────────────────────────────►
                                          868 ciclos por bit (8,68 µs)
```

---

## 13. Temporização RX

```
uart_rx:    1       0       1       1       1       1       1       0       1       1       1       1
            │       │       │       │       │       │       │       │       │       │       │       │
        IDLE│ START │  D0   │  D1   │  D2   │  D3   │  D4   │  D5   │  D6   │  D7   │ STOP  │IDLE
             │       │       │       │       │       │       │       │       │       │       │
        ▼───┴───┬───┴───┬───┴───┬───┴───┬───┴───┬───┴───┬───┴───┬───┴───┬───┴───┬───┴───┴───┴───
               │       │       │       │       │       │       │       │       │       │
rx_state:  IDLE│ START │ DATA  │ DATA  │ DATA  │ DATA  │ DATA  │ DATA  │ DATA  │ DATA  │ STOP  │IDLE
             │   │       │       │       │       │       │       │       │       │       │
rx_timer:   0  │ 0-433 │ 0-868 │ 0-868 │ 0-868 │ 0-868 │ 0-868 │ 0-868 │ 0-868 │ 0-868 │ 0-868│
             │   │(valida)      │       │       │       │       │       │       │       │
             │   │       │       │       │       │       │       │       │       │       │
rx_shifter: ───│ 0     │ 1     │ 11    │ 111   │ 1111  │11111  │111110 │1111101│11111011│      │
             │   │       │       │       │       │       │       │       │       │       │
w_wr_en:    0  │ 0     │ 0     │ 0     │ 0     │ 0     │ 0     │ 0     │ 0     │ 0     │  1   │ 0
                 │       │       │       │       │       │       │       │       │       │
            ◄───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼──────►
                    │       │       │       │       │       │       │       │       │       │
               Amostragem do start bit
               (centro = 433 ciclos)
                              │       │       │       │       │       │       │       │
                         Amostragem de cada bit
                         (no final do período = centro do próximo)
```

---

## 14. Referências

- **RTL Source:** `rtl/perips/uart/uart_controller.vhd`
- **Testbench:** `sim/perips/test_uart_controller.py`
- **IEEE Std 1076:** VHDL Language Reference Manual

---

## 15. Histórico de Versões

| Versão | Data       | Autor          | Descrição      |
|--------|------------|----------------|----------------|
| 1.0    | 01/01/2026 | André Maiolini | Versão inicial |
