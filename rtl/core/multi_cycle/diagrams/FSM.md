# 🤖 Introdução às Máquinas de Estados Finitos (FSM)

Computadores digitais armazenam e processam informações em formato binário. A cada instante, o hardware encontra-se em uma configuração específica de bits, definindo o que chamamos de **estado**. Como a memória e os registradores de um computador são finitos, o número de estados possíveis também é finito.

Em sistemas síncronos, o relógio interno (`clock`) dita o ritmo das operações. A cada pulso de clock, o sistema pode transitar para um novo estado. Essa transição não é aleatória; ela é **determinística** e depende de dois fatores:
1.  O **Estado Atual** da máquina;
2.  Os **Dados de Entrada** (*inputs*) recebidos naquele ciclo.

Conhecendo-se o estado atual e as entradas, o próximo estado é inteiramente previsível. A lógica que governa essas transições e as saídas geradas constitui uma **Máquina de Estados Finitos** (*Finite-State Machine* - FSM).

> **Definição:** Uma FSM é um modelo matemático de computação que representa um sistema com um número limitado de estados, transitando entre eles com base em uma lógica predefinida de eventos ou entradas.

No contexto de processadores (como o RISC-V Multiciclo), a FSM é fundamental para a Unidade de Controle, onde cada passo de uma instrução (Busca, Decodificação, Execução, etc.) representa um estado diferente.

## 📃 Características da Máquina Abstrata 

O comportamento dessa máquina é definido por:
1.  **Sincronismo:** Operações coordenadas por pulsos discretos de clock.
2.  **Determinismo:** As ações em resposta a uma sequência de entradas são previsíveis.
3.  **Entradas e Saídas:** A máquina reage a estímulos (*inputs*) e produz sinais de controle (*outputs*).
4.  **Memória de Estado:** A capacidade de "lembrar" o contexto atual (o estado em que se encontra).

Em uma **FSM do tipo Moore**, os sinais de saída dependem exclusivamente do **estado atual**, e não diretamente das entradas, o que torna o comportamento do controle mais estável e alinhado à divisão do processamento em ciclos bem definidos.

## 🎓 Definição Formal 

Matematicamente, uma máquina de estados finitos $M$ é definida pela 6-upla $M = (S, I, O, f, g, s_0)$, onde:

1.  $S$: Um conjunto finito de **estados** possíveis.
2.  $I$: Um alfabeto finito de símbolos de **entrada** (ex: *Opcode* da instrução).
3.  $O$: Um alfabeto finito de símbolos de **saída** (ex: sinais de controle como *MemWrite*, *ALUSrc*).
4. $f$: A **função de transição de estado** (*Next State Logic*), que define o próximo estado com base no estado atual e nas entradas:
   $$
   f: S \times I \rightarrow S
   $$
5. $g$: A **função de saída** (*Output Logic*), que, no modelo de Moore, depende **exclusivamente do estado atual**:
   $$
   g: S \rightarrow O \quad \text{(Modelo Moore)}
   $$
6.  $s_0$: O **estado inicial**, tal que $s_0 \in S$ (o estado em que a máquina começa, geralmente o *Reset* ou *Fetch*).

> **Resumo:** A cada pulso de clock, o sistema atualiza seu estado por meio da função de transição, e as saídas associadas a esse novo estado passam a valer durante todo o ciclo seguinte.

# 💻 Projeto da Unidade de Controle

A Unidade de Controle é o "cérebro" do processador. No contexto de uma arquitetura **Multi-Cycle** (Multiciclo), ela é implementada como uma Máquina de Estados Finitos (FSM) sequencial. Diferente da arquitetura Single-Cycle, onde todos os sinais de controle são gerados simultaneamente, no Multi-Cycle a unidade de controle orquestra a execução da instrução passo a passo, dividindo-a em ciclos de clock distintos.

A FSM utiliza o *opcode* (e campos auxiliares como *funct3* e *funct7*) da instrução atual para navegar pelo diagrama de estados, ativando os sinais de controle apropriados para os componentes do Caminho de Dados (*Datapath*) em cada estágio.

### Estrutura dos Estados

O ciclo de vida de uma instrução é dividido **em até cinco estágios principais**. A FSM garante que, em cada pulso de clock, apenas os componentes necessários para aquele estágio estejam ativos. Como apenas um estágio ocorre por vez, a arquitetura multi-cycle permite que os mesmos blocos funcionais sejam utilizados em diferentes estágios do fluxo da instrução, promovendo a reutilização de hardware. 

Além disso, o acesso à memória de instruções (IMem) e à memória de dados (DMem) ocorre em ciclos de clock distintos, o que viabiliza a utilização de memórias single-port sem conflitos de acesso.

#### **1. Instruction Fetch (IF) - Estado Inicial**
Neste estado, comum a todas as instruções, o objetivo é carregar a instrução da memória e atualizar o Program Counter ($PC$).
* **Ação:** A memória é lida no endereço apontado pelo $PC$.
* **Transição**: invariavelmente, IF transitará para ID (estágio de decodificação da intrução em `IR`).

#### **2. Instruction Decode (ID)**
A instrução armazenada no `IR` é decodificada. Como o RISC-V é regular, os campos dos registradores fonte ($rs1$, $rs2$) estão em posições fixas, permitindo a leitura do Banco de Registradores (*Register File*) antes mesmo de saber qual é a instrução exata.
* **Ação:** Leitura dos operandos e extensão de sinal dos imediatos.
* **Transição:** A FSM avalia o *Opcode* para decidir o próximo estado (ex: se for uma instrução tipo-R, vai para Execução; se for *Load*, prepara o cálculo de endereço).

#### **3. Execution (EX)**
O comportamento deste estado varia drasticamente conforme o tipo da instrução:
* **Tipo-R:** A ALU realiza a operação lógica ou aritmética definida pelos campos *funct*.
* **Load/Store:** A ALU calcula o endereço efetivo de memória (Base + Deslocamento).
* **Branch:** A ALU compara os operandos e calcula o endereço de desvio. Se a condição for verdadeira, o $PC$ é atualizado aqui.
* [...]

#### **4. Memory Access (MEM)**
Necessário apenas para instruções de carga (`LW`) e armazenamento (`SW`).
* **Load:** O dado é lido da Memória de Dados.
* **Store:** O dado do registrador é escrito na Memória de Dados.
* **Nota:** Instruções aritméticas (Tipo-R) pulam este estágio.

#### **5. Write-Back (WB)**
É o estágio final para instruções que escrevem no registrador de destino ($rd$).
* **Ação:** O resultado vindo da ALU (em operações R/I) ou da Memória (em Loads) é escrito no Banco de Registradores.
* **Conclusão:** Após este ciclo, a FSM retorna ao estado inicial **IF** para buscar a próxima instrução.

### Tabela Completa de Transição de Estado

| Estado Atual | Condição   | Próximo Estado | Descrição do Estado                                    | 
| :----------: | :--------: | :------------: | :----------------------------------------------------: | 
| IF           | -          | ID             | Busca instrução e incrementa PC (PC+4)                 | 
| ID           | Tipo-R/I   | EX_ALU         | Decodifica instruções aritméticas/lógicas              | 
| ID           | Load/Store | EX_ADDR        | Decodifica acesso à memória                            | 
| ID           | Branch     | EX_BR          | Decodifica desvio condicional                          | 
| ID           | JAL        | EX_JAL         | Decodifica salto incondicional imediato                | 
| ID           | JALR       | EX_JALR        | Decodifica salto incondicional via registrador         | 
| ID           | LUI        | EX_LUI         | Decodifica carregamento imediato superior              | 
| ID           | AUIPC      | EX_AUIPC       | Decodifica adição de imediato ao PC                    | 
| EX_ALU       | -          | WB_REG         | Operação da ALU concluída. Vai escrever no RegFile     | 
| EX_ADDR      | Load       | MEM_RD         | Endereço calculado. Vai ler da memória                 | 
| EX_ADDR      | Store      | MEM_WR         | Endereço calculado. Vai escrever na memória            | 
| EX_BR        | -          | IF             | Avalia condição (`Zero`) e atualiza PC se necessário   | 
| EX_JAL       | -          | WB_JAL         | Calcula alvo (`OldPC+IMM`) imediatamente               | 
| EX_JALR      | -          | WB_JALR        | Calcula alvo (`rs1+IMM`) e salva em ALUResult          | 
| EX_LUI       | -          | WB_REG         | Soma `0+IMM`. Vai para write-back                      | 
| EX_AUIPC     | -          | WB_REG         | Soma `PC+IMM`. Vai para write-back                     | 
| MEM_RD       | -          | WB_REG         | Lê `DMem[ALUResult]` e atualiza MDR                    | 
| MEM_WR       | -          | IF             | Escreve RS2 em `DMem[ALUResult]`                       | 
| WB_REG       | -          | IF             | Escrita do resultado em `rd`                           | 
| WB_JAL       | -          | IF             | Escreve retorno (`PC+4`) em `rd`. PC já foi atualizado | 
| WB_JALR      | -          | IF             | Escreve retorno (`PC+4`) em `rd`. PC é atualizado      | 

> ℹ️ **Modelo de memória**: por ora, a memória é assumida na forma de RAM Distribuída, garantindo o acesso aos dados no mesmo ciclo de clock e simplificando a lógica de controle. Pretende-se alterar isso futuramente, implementando **protocolo READY/VALID handshake**.

### Tabela Completa de Sinais de Controle

| Sinal  | Descrição do Sinal de Controle|
| :-: | :-- |
| `PCWrite` | Habilita escrita no `PC`. Permite que o PC seja atualizado apenas em estados específicos (como Fetch ou ao realizar um salto - branch/jump) |
| `OPCWrite` | Atualiza o `OldPC`. Guarda o valor atual do PC no registrador `r_OldPC`. É usado para salvar o endereço da instrução corrente - usando-o para cálculos relativos - atualizado normalmente no estado de Fetch |
| `PCSrc` | Seletor da fonte do próximo `PC`. Controla o multiplexador que define o novo valor do PC. Oppções são: `00` (`PC + 4`); `01` (Branch/JAL); `10` (JALR) |
| `IRWrite` | Habilita a escrita no `IR`. Permite carregar uma nova instrução apenas durante o estado de Fetch. | 
| `MemWrite` | Habilita a escrita na memória. Sinal enviado para a unidade de armazenamento e carga (LSU) para efetuar a gravação de um dado. |
| `ALUSrcA` | Seletor do Operando A da ALU. Opções: `00` (rs1); `01` (PC atual); `10` (zero) |
| `ALUSrcB` | Seletor do Operando B da ALU. Opções: `0` (rs2); `1` (imediato) |
| `ALUControl` | Seletor para a operação da ALU. Define qual operação a ALU deve executar (ADD, SUB, AND etc.) |
| `RegWrite` | Habilita a escrita no banco de registradores. Permite gravar no registrador `rd` durante o estágio de write-back (WB) |
| `WBSel` | Seletor do dado de write-back. Opções: `00` (resultado da ALU); `01` (MDR); `10` (próximo PC) |
| `RS1Write` | Habilita a atualização do regisitrador de RS1. Controla a capatura do valor lido de `rs1` do banco de registradores |
| `RS2Write` | Habilita a atualização do regisitrador de RS2. Controla a capatura do valor lido de `rs2` do banco de registradores |
| `ALUrWrite` | Habilita a atualização do ALUResult. Controla a captura do resultado da ALU |
| `MDRWrite` | Habilita a escrita no MDR. Captura o dado carregado da memória | 

### Tabela Completa de Sinais por Estado

#### Legenda de Sinais
* **ALUSrcA:** `00`=rs1; `01`=OldPC; `10`=Zero
* **ALUSrcB:** `0`=rs2; `1`=Imediato
* **PCSrc:** `00`=PC+4; `01`=Branch/JAL (Somador Dedicado); `10`=JALR (ALUResult)
* **WBSel:** `00`=ALUResult; `01`=MDR; `10`=PC+4 (Retorno)
* **Cond:** Habilitado apenas se a condição de Branch for satisfeita (Zero flag)
* **ALUControl:** `ADD` (Força Soma); `Funct` (Tipo-R/I); `Branch` (Resolve SUB/SLT/SLTU via funct3)

| Estado  | `PCWrite` | `OPCWrite` | `PCSrc`       | `IRWrite` | `MemWrite` | `ALUSrcA`      | `ALUSrcB`      | `ALUControl` | `RegWrite` | `WBSel`        | `RS1Write` | `RS2Write` | `ALUrWrite` | `MDRWrite` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **IF** | 1 | 1 | 00 | 1 | 0 | X | X | X | 0 | X | 0 | 0 | 0 | 0 |
| **ID** | 0 | 0 | X | 0 | 0 | X | X | X | 0 | X | 1 | 1 | 0 | 0 |
| **EX_ALU** | 0 | 0 | X | 0 | 0 | 00 | **0/1** | **Funct** | 0 | X | 0 | 0 | 1 | 0 |
| **EX_ADDR**| 0 | 0 | X | 0 | 0 | 00 | 1 | **ADD** | 0 | X | 0 | 0 | 1 | 0 |
| **EX_BR** | **Cond** | 0 | 01 | 0 | 0 | 00 | 0 | **Branch** | 0 | X | 0 | 0 | 0 | 0 |
| **EX_JAL** | 0 | 0 | X | 0 | 0 | X | X | X | 0 | X | 0 | 0 | 0 | 0 |
| **EX_JALR**| 0 | 0 | X | 0 | 0 | 00 | 1 | **ADD** | 0 | X | 0 | 0 | 1 | 0 |
| **EX_LUI** | 0 | 0 | X | 0 | 0 | 10 | 1 | **ADD** | 0 | X | 0 | 0 | 1 | 0 |
| **EX_AUIPC**| 0 | 0 | X | 0 | 0 | 01 | 1 | **ADD** | 0 | X | 0 | 0 | 1 | 0 |
| **MEM_RD** | 0 | 0 | X | 0 | 0 | X | X | X | 0 | X | 0 | 0 | 0 | 1 |
| **MEM_WR** | 0 | 0 | X | 0 | 1 | X | X | X | 0 | X | 0 | 0 | 0 | 0 |
| **WB_REG** | 0 | 0 | X | 0 | 0 | X | X | X | 1 | **00/01** | 0 | 0 | 0 | 0 |
| **WB_JAL** | 1 | 0 | 01 | 0 | 0 | X | X | X | 1 | 10 | 0 | 0 | 0 | 0 |
| **WB_JALR**| 1 | 0 | 10 | 0 | 0 | X | X | X | 1 | 10 | 0 | 0 | 0 | 0 |
