# Microarquitetura Multiciclo (Multi-Cycle)

A microarquitetura multiciclo representa uma evolução significativa em relação ao modelo monociclo. Enquanto no monociclo cada instrução é completamente executada em um único pulso de relógio, o multiciclo divide a execução em múltiplos ciclos, permitindo frequencies de operação mais altas e melhor utilização dos recursos de hardware.

## 1. A Transição: Single-Cycle para Multi-Cycle

### 1.1. Motivação Física: O Problema do Clock

Na arquitetura monociclo, o período do clock é determinado pelo **caminho crítico** — o maior tempo de propagação combinacional ao longo do circuito. Este caminho crítico inclui obrigatoriamente:

1. Leitura da memória de instruções
2. Decodificação e leitura do banco de registradores
3. Execução na ALU
4. Acesso à memória de dados (para loads/stores)
5. Escrita no banco de registradores

Como todas essas etapas devem caber em um único ciclo, o clock deve ser lento o suficiente para acomodar o pior caso. Isso significa que instruções simples (como `ADD` entre registradores) são forçadas a esperar, pois她们的 execução real é muito mais rápida que o tempo total disponível.

**A solução multiciclo:** Ao dividir a execução em etapas menores e balanceadas, cada estágio pode ser completado em um tempo muito menor. O somatório dos estágios resulta em um caminho crítico por estágio significativamente reduzido, permitindo que o processador opere em frequências substancialmente maiores.

### 1.2. Latência de Memória

O modelo monociclo assume implicitamente que as memórias respondem em tempo zero — uma abstração útil para análise, mas irrealista para implementações práticas.

**O problema com memórias reais:**
- Memórias síncronas (block RAMs em FPGAs) tipicamente requerem 1 a 3 ciclos de latência
- Memórias externas (DDR, SRAM) podem exigir dezenas de ciclos
- O modelo monociclo não tolera essa variabilidade sem comprometer a frequência

**A solução multiciclo:**
A arquitetura multiciclo introduz estágios dedicados para acesso à memória. O processador pode "congelar" a FSM em estados de espera até que a memória retorne o sinal de `ready`, mantendo o determinismo da execução sem fixer a frequência do clock à latência máxima de memória.

---

## 2. O Novo Caminho de Dados (Datapath Multiciclo)

A principal diferença visual entre o datapath monociclo e multiciclo é a presença de **registradores de estágio** (pipeline registers) que separam logicamente cada fase da execução.

### 2.1. Registradores de Estágio

No modelo multiciclo, registradores intermediários são introduzidos para reter os resultados entre ciclos de clock para uma mesma instrução:

| Registrador | Sigla | Função |
|-------------|-------|--------|
| **Instruction Register** | `IR` | Armazena a instrução atual durante sua execução |
| **Memory Data Register** | `MDR` | Armazena o dado lido da memória antes do write-back |
| **A / B** | `RS1`, `RS2` | Armazenam os operandos lidos do banco de registradores |
| **ALUOut** | `ALUResult` | Armazena o resultado da ALU entre estágios |
| **OldPC** | `OPC` | Armazena o PC da instrução atual para cálculos relativos |

A implementação no `datapath.vhd` (linhas 157-163) demonstra esses registradores:

```vhdl
signal r_PC             : std_logic_vector(31 downto 0);
signal r_OldPC          : std_logic_vector(31 downto 0);
signal r_IR             : std_logic_vector(31 downto 0);
signal r_MDR            : std_logic_vector(31 downto 0);
signal r_RS1            : std_logic_vector(31 downto 0);
signal r_RS2            : std_logic_vector(31 downto 0);
signal r_ALUResult      : std_logic_vector(31 downto 0);
```

Cada registrador é habilitado por um sinal de controle específico (definidos em `riscv_uarch_pkg.vhd`):

```vhdl
rs1_write   : std_logic;  -- Captura rs1 do banco para o reg interno 'A'
rs2_write   : std_logic;  -- Captura rs2 do banco para o reg interno 'B'
alur_write  : std_logic;  -- Captura resultado da ALU no reg 'ALUOut'
mdr_write   : std_logic;  -- Captura dado da memória no 'MDR'
ir_write    : std_logic;  -- Atualiza o Instruction Register (IR)
```

### 2.2. Reuso de Hardware

Uma das vantagens mais significativas da arquitetura multiciclo é a **reutilização temporal** de recursos. No monociclo,硬件 duplicado é necessário para aumentar paralelismo; no multiciclo, o mesmo hardware pode ser usado em diferentes ciclos para diferentes finalidades.

**Exemplo: A ALU compartilhada**

No monociclo, são necessários somadores dedicados para:
- Calcular `PC + 4` (próxima instrução)
- Calcular `PC + imediato` (endereço de branch/jump)
- Executar operações aritméticas da instrução

No multiciclo, todas essas operações passam pela **mesma ALU** em diferentes ciclos:
- No **IF**: ALU calcula `PC + 4` para atualizar o PC
- No **EX**: ALU executa a operação aritmética da instrução
- No **EX_ADDR**: ALU calcula o endereço de memória para loads/stores

O multiplexer `ALUSrcA` seleciona a entrada correta para cada ciclo:
```vhdl
with Control_i.alu_src_a select
    s_alu_in_a <= r_RS1       when "00",    -- Operando normal (rs1)
                  r_OldPC     when "01",    -- PC para AUIPC
                  x"00000000" when "10",    -- Zero para LUI
                  r_RS1       when others;
```

Da mesma forma, o `ALUSrcB` seleciona entre o registrador `rs2` ou o imediato:
```vhdl
s_alu_in_b <= r_RS2 when Control_i.alu_src_b = '0' else s_immediate;
```

---

## 3. Unidade de Controle e Sincronização

### 3.1. A Máquina de Estados Finita (FSM)

Na arquitetura multiciclo, a Unidade de Controle é implementada como uma **FSM de Moore** — uma máquina de estados finitos onde as saídas dependem exclusivamente do estado atual. O arquivo `main_fsm.vhd` implementa esta FSM, organizada em estados que correspondem às fases lógicas de execução.

#### Estados da FSM

A FSM é definida pelo tipo `t_state` em `main_fsm.vhd:127-134`:

```vhdl
type t_state is (
    S_IF,                                                                        -- IF  (Instruction Fetch)
    S_ID,                                                                        -- ID  (Instruction Decode)
    S_EX_ALU, S_EX_ADDR, S_EX_BR, S_EX_JAL, S_EX_JALR, S_EX_LUI, S_EX_AUIPC,   -- EX  (Execution)
    S_EX_FENCE, S_EX_SYSTEM,
    S_MEM_RD, S_MEM_WR,                                                          -- MEM (Memory Access)
    S_WB_REG, S_WB_JAL, S_WB_JALR                                                -- WB  (Write-Back)
);
```

**Fluxo de Estados:**

1. **S_IF (Instruction Fetch):** 
   - PC é enviado para memória de instruções
   - Instrução é armazenada no IR
   - PC é incrementado para PC+4

2. **S_ID (Instruction Decode):**
   - Instrução é decodificada
   - Registradores rs1 e rs2 são lidos para os registradores A e B
   - Imediato é gerado

3. **S_EX_\* (Execution):**
   - A ALU executa a operação conforme o tipo de instrução
   - Cada variante (ALU, ADDR, BR, JAL, etc.) configura a ALU de forma diferente

4. **S_MEM_RD / S_MEM_WR (Memory Access):**
   - Acesso à memória de dados para loads e stores

5. **S_WB_\* (Write-Back):**
   - Resultado é escrito no registrador de destino

### 3.2. Protocolo de Sincronização (Handshake Ready/Valid)

Para tolerar memórias com latência variável, o processador implementa um protocolo de handshake `ready`/`valid` nas interfaces de memória:

#### Interface de Handshake

Em `processor_top.vhd:71-76`:
```vhdl
IMem_rdy_i  : in  std_logic;
IMem_vld_o  : out std_logic;
DMem_rdy_i  : in  std_logic;
DMem_vld_o  : out std_logic;
```

#### FSM e Handshake

A FSM permanece em estados de espera até que a memória sinalize que a transação foi completada:

**Estado S_IF (main_fsm.vhd:215-221):**
```vhdl
when S_IF =>
    -- STALL DE INSTRUÇÃO: Só avança se a memória entregar a instrução
    if imem_rdy_i = '1' then
        next_state <= S_ID;
    else
        next_state <= S_IF;  -- Permanece esperando
    end if;
```

**Estado S_MEM_RD (main_fsm.vhd:297-302):**
```vhdl
when S_MEM_RD => 
    if dmem_rdy_i = '1' then
        next_state <= S_WB_REG;
    else
        next_state <= S_MEM_RD;  -- Stall: fica esperando
    end if;
```

**Estado S_MEM_WR (main_fsm.vhd:305-310):**
```vhdl
when S_MEM_WR => 
    if dmem_rdy_i = '1' then
        next_state <= S_IF;
    else
        next_state <= S_MEM_WR;  -- Stall: fica esperando
    end if;
```

#### Geração de Sinais de Handshake

A FSM também gera os sinais `valid` para indicar ao sistema de memória que o processador está pronto para uma transação:

**Sinais de saída em S_IF (main_fsm.vhd:359-366):**
```vhdl
when S_IF =>
    imem_vld_o     <= '1';
    -- Só atualiza quando o dado chega
    if imem_rdy_i = '1' then
        IRWrite_o  <= '1';
        PCWrite_o  <= '1';
        OPCWrite_o <= '1';
    end if;
```

**Sinais de saída em S_MEM_RD (main_fsm.vhd:533-540):**
```vhdl
when S_MEM_RD =>
    dmem_vld_o <= '1';
    -- Só grava no MDR quando o dado estiver PRONTO
    if dmem_rdy_i = '1' then
        MDRWrite_o <= '1';
    end if;
```

### 3.3. Sinais de Controle

A FSM gera todos os sinais necessários para controlar o datapath:

| Sinal | Descrição |
|-------|------------|
| `PCWrite` | Habilita escrita no PC |
| `OPCWrite` | Atualiza o OldPC |
| `IRWrite` | Habilita escrita no IR |
| `MemWrite` | Habilita escrita na memória de dados |
| `RegWrite` | Habilita escrita no banco de registradores |
| `RS1Write` / `RS2Write` | Captura operandos do banco de registradores |
| `ALUrWrite` | Captura resultado da ALU |
| `MDRWrite` | Captura dado da memória |
| `ALUSrcA` | Seleciona operando A da ALU (rs1, PC, Zero) |
| `ALUSrcB` | Seleciona operando B da ALU (rs2, Imediato) |
| `PCSrc` | Seleciona fonte do próximo PC |
| `WBSel` | Seleciona dado para write-back (ALUOut, MDR, PC+4, CSR) |

---

## 4. Integração no Top-Level

O `processor_top.vhd` do multiciclo apresenta a mesma estrutura de integração que o monociclo, porém com a diferença fundamental de que o Control Path agora é uma FSM em vez de lógica puramente combinacional.

A arquitetura de Harvard Modificada é mantida, com barramentos separados para IMEM e DMEM, permitindo acesso simultâneo a instruções e dados.

### Diferenças Principais entre Single-Cycle e Multi-Cycle

| Aspecto | Single-Cycle | Multi-Cycle |
|---------|--------------|-------------|
| ** clock por instrução | 1 | 2-5 (variável) |
| **Frequência máxima** | Limitada pelo caminho crítico completo | Maior (caminho crítico por estágio) |
| **Unidade de Controle** | Lógica combinacional | FSM sequencial |
| **Recursos de hardware** | Duplicados para paralelismo | Compartilhados no tempo |
| **Registradores intermediários** | Não existem | IR, MDR, A, B, ALUOut, OldPC |
| **Handshake de memória** | Não suportado nativamente | Suportado via Ready/Valid |
| **Complexidade de controle** | Baixa | Média-Alta |

---

## 5. Conclusão

A microarquitetura multiciclo representa um compromisso entre simplicidade de controle (herdada do monociclo) e desempenho (proporcional à frequência de operação). Ao dividir a execução em múltiplos ciclos e reutilizar recursos de hardware no tempo, o processador pode atingir frequencies significativamente mais altas que o monociclo, mantendo uma complexidade controlável.

A implementação do protocolo handshake ready/valid garante que o processador pode funcionar corretamente com memórias reais de latência variável, algo impossível no modelo monociclo.
