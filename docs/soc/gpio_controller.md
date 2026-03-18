# GPIO Controller - Microarquitetura

**Módulo:** `gpio_controller.vhd`  
**Autor:** André Maiolini  
**Data:** 31/12/2025  
**Versão:** 1.0

---

## 1. Visão Geral

O **GPIO Controller** é um periférico de Entrada/Saída de Uso Geral integrado ao barramento do SoC. Este módulo gerencia a comunicação entre o processador RISC-V e dispositivos físicos externos, especificamente:

- **16 pinos de saída** conectados a LEDs
- **16 pinos de entrada** conectados a chaves (switches)

A arquitetura utiliza um protocolo de handshake para comunicação síncrona com o barramento do sistema, garantindo integridade de dados através de sinais de validade (`vld_i`) e prontidão (`rdy_o`).

---

## 2. Diagrama de Blocos

```
                           ┌─────────────────────────────────────┐
                           │         GPIO CONTROLLER              │
                           │         (gpio_controller)            │
                           └─────────────────────────────────────┘
                                    
  Barramento do SoC                              Pinos Externos
  ┌──────────────────┐                     ┌─────────────────────┐
  │   addr_i[3:0]    │────────────────────▶│                     │
  │   data_i[31:0]   │────────────────────▶│                     │
  │   we_i          │────────────────────▶│   Lógica de         │
  │   vld_i         │────────────────────▶│   Decodificação     │
  │                  │                     │   e Controle        │
  │   data_o[31:0]   │◀────────────────────│                     │
  │   rdy_o         │◀────────────────────│                     │
  └──────────────────┘                     │                     │
                                          │                     │
                                          │  ┌───────────────┐  │
                                          │  │  Registrador  │  │
                                          │  │  r_leds[15:0] │──┼───▶ gpio_leds[15:0]
                                          │  └───────────────┘  │
                                          │                     │
                                          │  ┌───────────────┐  │
                                          │  │  gpio_sw      │◀─┼──── gpio_sw[15:0]
                                          │  │  [15:0]       │  │
                                          │  └───────────────┘  │
                                          └─────────────────────┘
                                                 ▲
                                                 │ clk, rst
                                                 │
                                          ┌──────┴──────┐
                                          │   CLOCK     │
                                          │   RESET     │
                                          └─────────────┘
```

---

## 3. Mapa de Memória

| Offset | Nome          | Direção | Descrição                              | Acesso  |
|--------|---------------|---------|----------------------------------------|---------|
| `0x0`  | `LEDS`        | R/W     | Registrador de dados dos LEDs         | Leitura/Escrita |
| `0x4`  | `SWITCHES`    | R      | Registrador de estado das chaves      | Somente Leitura |

### Detalhamento dos Registradores

```
Offset 0x0 - LEDS (R/W)
┌─────────────────────────────────────────────────────────────────┐
│  31  30  29  28  27  26  25  24  23  22  21  20  19  18  17  16 │ 15  14  13  12  11  10  09  08  07  06  05  04  03  02  01  00 │
├─────────────────────────────────────────────────────────────────┤
│                          Reserved (16 bits)                      │                      LED Data (16 bits)                      │
└─────────────────────────────────────────────────────────────────┘
                                                                  ▲
                                                                  │
                                                          bits ativos para
                                                          controle dos LEDs

Offset 0x4 - SWITCHES (Read-Only)
┌─────────────────────────────────────────────────────────────────┐
│  31  30  29  28  27  26  25  24  23  22  21  20  19  18  17  16 │ 15  14  13  12  11  10  09  08  07  06  05  04  03  02  01  00 │
├─────────────────────────────────────────────────────────────────┤
│                          Reserved (16 bits)                      │                    Switch State (16 bits)                   │
└─────────────────────────────────────────────────────────────────┘
                                                                  ▲
                                                                  │
                                                          reflete o estado
                                                          físico das chaves
```

---

## 4. Arquitetura de Registradores

### 4.1 Registrador `r_leds`

**Tipo:** `std_logic_vector(15 downto 0)` - registrador interno  
**Propósito:** Armazenar o estado lógico dos 16 pinos de saída conectados aos LEDs  
**Localização física:** Sinal interno no domínio de clock  

```vhdl
signal r_leds : std_logic_vector(15 downto 0);
```

#### Comportamento

| Condição              | Ação                                      |
|-----------------------|-------------------------------------------|
| `rst = '1'`           | `r_leds <= (others => '0')` (reset)       |
| `vld_i = '1'` E `we_i = '1'` E `addr_i = 0x0` | `r_leds <= data_i(15 downto 0)` |
| Caso contrário        | Mantém valor atual (latched)              |

#### Conexão Física

```vhdl
gpio_leds <= r_leds;  -- Saída combinacional para os pinos físicos
```

A saída `gpio_leds` é uma conexão direta (wire) do registrador, atualizando-se imediatamente quando `r_leds` muda.

### 4.2 Sinal `gpio_sw`

**Tipo:** `std_logic_vector(15 downto 0)` - porta de entrada  
**Propósito:** Refletir o estado físico das 16 chaves (switches) externas  
**Características:** Não é um registrador; é uma leitura direta do hardware externo  

```vhdl
gpio_sw : in std_logic_vector(15 downto 0);  --声明在 porta
```

#### Fluxo de Dados

```
gpio_sw (pino físico) ──────────────► data_o(15 downto 0) quando addr_i = 0x4
                                      (via multiplexador no processo)
```

### 4.3 Interação Direção Dados

Este módulo implementa uma **separação fixa de direção**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ARQUITETURA DE DIREÇÃO                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Pinos de SAÍDA (LEDs)        Pinos de ENTRADA (Switches)         │
│   ┌──────────────────┐         ┌──────────────────┐               │
│   │   gpio_leds[15:0]│◀────────│     r_leds        │               │
│   │   (output port)  │         │   (16-bit reg)    │               │
│   └──────────────────┘         └──────────────────┘               │
│          ▲                            │                            │
│          │                            ▼                            │
│          │                  ┌──────────────────┐                  │
│          │                  │    data_o[15:0]   │                  │
│          │                  │ (quando leitura)  │                  │
│          │                  └──────────────────┘                  │
│          │                                                     │
│   Software escreve     Software lê              Software lê    │
│   em r_leds para       de r_leds para           de gpio_sw     │
│   controlar LEDs       verificar estado         para ver estado │
│                                                     das chaves   │
└─────────────────────────────────────────────────────────────────────┘
```

**Nota:** Este módulo **não possui** um registrador de direção (direction register) como em GPIO tradicionais. A direção é fixa:
- Bits 15:0 dos LEDs → **sempre saída**
- Bits 15:0 dos Switches → **sempre entrada**

---

## 5. Lógica de Interface

### 5.1 Sinais do Barramento

| Sinal    | Direção | Tipo       | Descrição                                      |
|----------|---------|------------|------------------------------------------------|
| `clk`    | Input   | `std_logic`| Clock do sistema (síncrono)                    |
| `rst`    | Input   | `std_logic`| Reset síncrono (ativo alto)                    |
| `vld_i`  | Input   | `std_logic`| Validade: indica transação válida no barramento |
| `we_i`   | Input   | `std_logic`| Write Enable: '1'=escrita, '0'=leitura         |
| `addr_i` | Input   | `slv(3:0)` | Offset do endereço (seleciona registrador)     |
| `data_i` | Input   | `slv(31:0)`| Dados de entrada (escrita da CPU)              |
| `data_o` | Output  | `slv(31:0)`| Dados de saída (leitura para CPU)              |
| `rdy_o`  | Output  | `std_logic`| Ready: indica que o periférico respondeu      |

### 5.2 Processo Síncrono Principal

```vhdl
process(clk)
begin
    if rising_edge(clk) then
        
        if rst = '1' then
            r_leds <= (others => '0');
            rdy_o  <= '0';
            data_o <= (others => '0');
        
        else
            -- Default: Ready baixa se não houver transação
            rdy_o  <= '0';
            data_o <= (others => '0');

            if vld_i = '1' then
                -- Handshake: Resposta no próximo ciclo (Latência 1)
                rdy_o <= '1';

                -- ESCRITA
                if we_i = '1' then
                    if unsigned(addr_i) = 0 then
                        r_leds <= data_i(15 downto 0);
                    end if;
                
                -- LEITURA
                else
                    case to_integer(unsigned(addr_i)) is
                        when 0 => data_o(15 downto 0) <= r_leds;
                        when 4 => data_o(15 downto 0) <= gpio_sw;
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end if;
end process;
```

### 5.3 Decodificação de Endereço

```
addr_i (bits)           Seleção
─────────────────────────────────
0000 (0x0)              Registrador de LEDs (r_leds)
0100 (0x4)              Registrador de Switches (gpio_sw)
outros                  Nenhuma ação (null)
```

### 5.4 Máquina de Estados Comportamental

```
                    ┌─────────────────────────────────────────────────┐
                    │                                                 │
                    ▼                                                 │
    ┌─────────┐  rst   ┌─────────┐  clk, vld_i=0   ┌──────────────┐   │
───▶│  RESET  │──────▶│  IDLE   │────────────────▶│  IDLE        │   │
    └─────────┘        └─────────┘                 │  (nop)       │   │
                            │                      └──────────────┘   │
                            │ vld_i=1                                    │
                            ▼                                            │
              ┌───────────────────────────────────┐                      │
              │          ACTIVE                   │                      │
              │  rdy_o <= '1'                     │                      │
              │  (próximo ciclo de clock)         │                      │
              └───────────────────────────────────┘                      │
                            │                                            │
              ┌─────────────┴─────────────┐                              │
              │                           │                              │
              ▼                           ▼                              │
     ┌──────────────────┐       ┌──────────────────┐                    │
     │     WRITE         │       │     READ          │                    │
     │  we_i=1, addr=0   │       │  we_i=0           │                    │
     │  r_leds <= data_i │       │  data_o <= reg    │                    │
     └──────────────────┘       └──────────────────┘                    │
                                                                    loops back
```

---

## 6. Diagrama de Temporização

### 6.1 Operação de Escrita (Write)

```
Ciclo:     0       1       2       3       4
           │       │       │       │       │
clk        ┌───────┐┌───────┐┌───────┐┌───────┐
           │       │       │       │       │
           └───────┘└───────┘└───────┘└───────┘
             ▲       ▲       ▲       ▲
             │       │       │       │
             │       │       │       │
vld_i        ┌───────────────┐       (volta a 0)
             │               │
             └───────────────┘
             │       │
             │       │
we_i         ┌───────────────┐
             │               │
             └───────────────┘
             │       │
             │       │
addr_i       ────────┬───────
             │       │
             │   0x0 (LED addr)
             │
data_i       ────────┬────────────────
             │       │
             │   Dado escrito
             │
rdy_o                    ┌───────────────┐
                         │               │
                         └───────────────┘
                         │       │
                         │   Ready no ciclo 1
                         │
r_leds                   ════════════════
                         │   Dado aparece
                         │   no registrador
                         │
gpio_leds                ════════════════
                         │ (saída física)
                         │
                         Legenda:
                         ═ = valor estável
                         ▲ = borda de clock
```

**Análise:** A escrita ocorre na borda de clock do ciclo 1. `rdy_o` é asserted no ciclo 1 (resposta ao `vld_i` do ciclo 0).

### 6.2 Operação de Leitura (Read LED)

```
Ciclo:     0       1       2       3
           │       │       │       │
clk        ┌───────┐┌───────┐┌───────┐
           │       │       │       │
           └───────┘└───────┘└───────┘
             ▲       ▲       ▲
             │       │       │
vld_i        ┌───────────────┐
             │               │
             └───────────────┘
             │       │
we_i         0               (leitura)
             │
addr_i       ────────┬───────
             │   0x0 (LED)
             │
data_o               ┌──────────────────────
                     │  r_leds aparece
                     │  neste ciclo (1)
                     │
rdy_o                    ┌───────────────┐
                         │               │
                         └───────────────┘
```

**Análise:** A CPU coloca `addr_i=0x0` e `vld_i=1` no ciclo 0. No ciclo 1, `rdy_o=1` e `data_o` contém o valor de `r_leds`.

### 6.3 Operação de Leitura (Read Switch)

```
Ciclo:     0       1       2
           │       │       │
clk        ┌───────┐┌───────┐
           │       │       │
           └───────┘└───────┘
             ▲       ▲
vld_i        ┌───────────────┐
             │               │
addr_i       ────────┬───────
             │   0x4 (SW)
             │
gpio_sw      ════════════════
             (estado físico)
             │
data_o               ┌───────────────────
                     │ gpio_sw é
                     │ amostrado aqui
                     │
rdy_o                    ┌───────────────┐
                         │               │
                         └───────────────┘
```

### 6.4 Reset Síncrono

```
Ciclo:     0       1       2       3
           │       │       │       │
clk        ┌───────┐┌───────┐┌───────┐
           │       │       │       │
           └───────┘└───────┘└───────┘
             ▲       ▲       ▲
rst              ┌───────────┐
             │   │   1 (ativo)
             └───┘       └──
                         (libera reset)
                         
r_leds       0       0       0       0
             ▲
             Reset para 0
             (borda de clock)
             
rdy_o        0       0       0       0
             (forçado a 0 durante reset)
```

---

## 7. Protocolo de Handshake

### 7.1 Descrição

O GPIO Controller implementa um protocolo **handshake com latência 1** para comunicação com o barramento do SoC:

```
┌──────────────────────────────────────────────────────────────┐
│                  PROTOCOLO DE HANDSHAKE                      │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   CPU                                 GPIO Controller        │
│   ───                                 ───────────────        │
│                                                              │
│   1. Coloca vld_i = '1'              4. Detecta vld_i = 1   │
│      (solicita transação)                  (no clock edge)  │
│      + we_i, addr_i, data_i                                     │
│                                                      │        │
│                                                      ▼        │
│                                            5. rdy_o <= '1'   │
│                                               (próximo ciclo)│
│                                                      │        │
│                                                      ▼        │
│   2. Aguarda rdy_o = '1' ◀─────────────────────────┘        │
│      (no próximo ciclo)                                      │
│                                                              │
│   3. Processa resposta                                      │
│      (lê data_o / confirma escrita)                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 7.2 Diagrama de Estados do Handshake

```
                    ┌─────────────────┐
                    │                 │
                    │     IDLE         │
                    │  vld_i = '0'     │
                    │                 │
                    └────────┬────────┘
                             │
                             │ vld_i = '1'
                             ▼
                    ┌─────────────────┐
                    │                 │
                    │    ACTIVE       │──────┐
                    │  rdy_o = '1'    │      │
                    │                 │      │ (retorna a
                    └─────────────────┘      │  IDLE)
                             ▲               │
                             │               │
                             └───────────────┘
```

### 7.3 Timing do Handshake

| Ciclo | `vld_i` | `we_i` | `addr_i` | `data_i` | `rdy_o` | Ação |
|-------|---------|--------|----------|----------|---------|------|
| N     | 1       | 0/1    | 0x0/0x4  | valor    | 0       | CPU inicia transação |
| N+1   | 0       | -      | -        | -        | 1       | GPIO responde |
| N+2   | -       | -      | -        | -        | 0       | Idle novamente |

---

## 8. Tabela de Operações Completa

| `vld_i` | `we_i` | `addr_i` | `data_i`     | `data_o`      | `rdy_o` | Ação                                    |
|---------|--------|----------|--------------|---------------|---------|-----------------------------------------|
| 0       | X      | X        | X            | (zera)        | 0       | Nenhuma operação                        |
| 1       | 1      | 0x0      | `xxxx_xxxx`  | (zera)        | 1       | Escrita em `r_leds`                     |
| 1       | 1      | 0x4      | X            | (zera)        | 1       | Escrita ignorada (endereço read-only)   |
| 1       | 1      | Outro    | X            | (zera)        | 1       | Escrita ignorada (endereço inválido)    |
| 1       | 0      | 0x0      | X            | `r_leds`      | 1       | Leitura de LEDs                         |
| 1       | 0      | 0x4      | X            | `gpio_sw`     | 1       | Leitura de Switches                     |
| 1       | 0      | Outro    | X            | (zera)        | 1       | Leitura inválida (retorna 0)            |

---

## 9. Considerações de Projeto

### 9.1 Domínio de Clock

- **Síncrono:** Todos os registradores operam na borda de subida do `clk`
- **Reset:** Síncrono, ativo alto, zera `r_leds` para `0x0000`

### 9.2 Latência

- **Latência de resposta:** 1 ciclo de clock
- A CPU deve aguardar `rdy_o = '1'` antes de considerar a transação completa

### 9.3 Largura de Dados

- Barramento: 32 bits (`data_i`, `data_o`)
- Dados úteis: 16 bits (LSB)
- Bits superiores (31:16): Reservados, retornam 0 em leituras

### 9.4 Limitações

1. **Direção fixa:** Não há registrador de direção configurável
2. **Sem interrupções:** O módulo não suporta geração de interrupções
3. **Sem máscaras individuais:** Escrita afeta todos os 16 bits simultaneamente

---

## 10. Referências

- **RTL Source:** `rtl/perips/gpio/gpio_controller.vhd`
- **Testbench:** `sim/perips/test_gpio_controller.py`
- **IEEE Std 1076:** VHDL Language Reference Manual

---

## 11. Histórico de Versões

| Versão | Data       | Autor          | Descrição      |
|--------|------------|----------------|----------------|
| 1.0    | 31/12/2025 | André Maiolini | Versão inicial |
