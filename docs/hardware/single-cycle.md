## 1. A Anatomia da Instrução (Decodificação e Controle)

O núcleo RISC-V (RV32I) de ciclo único processa instruções de 32 bits, operando através de um ciclo contínuo de **busca**, **decodificação** e **execução**. A compreensão da sua microarquitetura exige a análise de três pilares fundamentais: a estrutura gramatical da instrução, o módulo responsável pela extensão de imediatos e a Unidade de Controle Principal.

### Estrutura Gramatical da Instrução

Na arquitetura RISC-V, os campos da instrução possuem posições fixas para simplificar a decodificação em hardware. Uma instrução típica de 32 bits é fatiada da seguinte forma:

| Campo | Bits | Descrição |
| :--- | :--- | :--- |
| **`opcode`** | 6:0 | Indica a categoria ou formato da instrução (ex: R-Type, I-Type, Load, Store). |
| **`rd`** | 11:7 | Endereço do registrador de destino, onde o resultado da operação será guardado. |
| **`funct3`** | 14:12 | Subcódigo de operação (3 bits) utilizado para diferenciar operações dentro do mesmo `opcode` (ex: distinguir soma e subtração, ou tipos de saltos). |
| **`rs1`** | 19:15 | Endereço do registrador de origem 1. |
| **`rs2`** | 24:20 | Endereço do registrador de origem 2. |
| **`funct7`** | 31:25 | Subcódigo adicional (7 bits), tipicamente utilizado em instruções do formato R para refinar ainda mais a operação da Unidade Lógica e Aritmética (ULA). |

### Gerador de Imediatos (`imm_gen`)

O módulo `imm_gen` é responsável por extrair e estender o valor imediato das instruções de 32 bits. O seu objetivo é garantir que a ULA e a Unidade de Branch recebam operandos de 32 bits válidos. O processo avalia o `opcode` da instrução e reconstrói o imediato consoante o seu formato:

* **Formato I (Load, I-Type, JALR):** O imediato é extraído diretamente dos bits da instrução. O sinal é estendido matematicamente para 32 bits.
* **Formato S (Store):** O imediato encontra-se fragmentado. O módulo reorganiza os bits superiores e os bits `[11:7]` para formar o valor de 12 bits, que é em seguida estendido para 32 bits.
* **Formato B (Branch):** A reconstrução exige o mapeamento dos bits `[31]`, `[7]`, e `[11:8]`, forçando sempre um bit '0' na posição menos significativa (LSB) para garantir o alinhamento de 2 bytes. O valor resultante de 13 bits é assinalado e estendido para 32 bits.
* **Formato U (LUI, AUIPC):** O gerador extrai os bits e preenche os 12 bits menos significativos com zeros (`x"000"`), construindo uma constante de 32 bits sem necessidade de extensão de sinal adicional.
* **Formato J (JAL):** Os bits do imediato são agregados a partir das posições correspondentes com o LSB forçado a '0'. O valor de 21 bits é posteriormente estendido para o tamanho da palavra do processador.

### Unidade de Controle Principal (`control` e `decoder`)

A Unidade de Controle representa o circuito de comando do processador. No topo hierárquico, o módulo `control.vhd` extrai os campos `opcode`, `funct3` e `funct7` e delega a decodificação primária ao submódulo `decoder.vhd`.

O decodificador atua exclusivamente sobre os 7 bits do `opcode` (sinal `Opcode_i`) para gerar os sinais de controle de alto nível, agrupados no registo `t_decoder`:

* **`reg_write`:** Sinal lógico que habilita a escrita no banco de registradores. Fica ativo (`'1'`) em instruções do Formato R, Formato I, Load, JAL, JALR e Formato U.
* **`alu_src_a` e `alu_src_b`:** Selecionam as fontes dos operandos que alimentam a ULA. Por exemplo, no Formato R, `alu_src_b` é `'0'` para receber dados do registrador. Em instruções que usam imediatos (Load, Store, Formato I), `alu_src_b` assume o valor `'1'`.
* **`mem_write`:** Habilita a escrita na memória, sendo exclusivamente ativo (`'1'`) para operações de Store (`0100011`).
* **`wb_src`:** Define qual a origem do dado que será escrito de volta no registrador de destino (Write-Back). Pode ser proveniente da ULA (`"00"`), da memória (`"01"` para Loads) ou registar o valor do PC + 4 (`"10"` para JAL e JALR).
* **`alu_op`:** Código interno de 2 bits que categoriza a classe da operação aritmética para a ULA. A unidade emite `"00"` para operações que requerem soma implícita (cálculo de endereços de Load/Store, Formato U), `"01"` para comparações de desvio (Branch), `"10"` para o Formato R e `"11"` para o Formato I aritmético.

> **Nota:** Estes sinais de controle base ditam o comportamento de todo o caminho de dados (Datapath), assegurando que os multiplexadores encaminham corretamente os dados e a memória efetua as leituras e escritas exigidas pela instrução em curso.

### 💡 **Exemplo Prático: Rastreio da Instrução `lw` (Load Word)**

Para ilustrar como a etapa de decodificação e controle funciona na prática, vamos acompanhar o ciclo de uma instrução clássica de leitura de memória: `lw x5, 12(x10)`.

Esta instrução dita ao processador: *"Vá ao endereço de memória resultante da soma do valor do registrador `x10` com o deslocamento `12`, leia a palavra (32 bits) contida lá e guarde-a no registrador `x5`."*

---

### 1. A Instrução em Binário

A instrução assembly é traduzida pelo compilador para uma palavra de 32 bits. Quando ela chega à porta `Instruction_i` dos nossos módulos, o seu formato binário é fatiado da seguinte forma:



| Campo | Bits | Binário | Descrição |
| :--- | :--- | :--- | :--- |
| **`imm[11:0]`** | 31:20 | `000000001100` | Valor imediato (12 em decimal) |
| **`rs1`** | 19:15 | `01010` | Registrador base (`x10`) |
| **`funct3`** | 14:12 | `010` | Código da função para Load Word |
| **`rd`** | 11:7 | `00101` | Registrador de destino (`x5`) |
| **`opcode`** | 6:0 | `0000011` | Código para a categoria LOAD |

**Instrução completa recebida:** `000000001100_01010_010_00101_0000011`

### 2. O Processamento no `imm_gen`

O gerador de imediatos inspeciona o `opcode` e identifica a instrução como um Formato I (Load). Ele extrai diretamente os bits da instrução (`000000001100`) e aplica a extensão de sinal para 32 bits. O sinal de saída `Immediate_o` emite o valor `0x0000000C` (12 em decimal), que ficará disponível para ser utilizado pela ULA no cálculo do endereço.

### 3. O Processamento no `decoder`

Em paralelo, a unidade de decodificação principal lê o `opcode` (`0000011`). Através da sua lógica combinacional, ativa os seguintes sinais para preparar o Datapath:

* **`reg_write <= '1'`**: Autoriza a escrita no banco de registradores (pois o resultado final será salvo em `x5`).
* **`alu_src_b <= '1'`**: Configura o multiplexador da ULA para rejeitar o segundo registrador e aceitar o valor imediato (o 12 gerado pelo `imm_gen`).
* **`wb_src <= "01"`**: Configura o multiplexador de Write-Back para rotear o dado vindo da Memória (e não o resultado matemático da ULA) para o registrador de destino.
* **`alu_op <= "00"`**: Informa ao controlador da ULA que a operação exigida é uma soma (para calcular endereço base + deslocamento).

### 4. A Síntese no `control`

O módulo de topo desta etapa encapsula tudo. Ele confirma que a instrução não é de salto (`branch = '0'` e `jump = '0'`), mantendo o seletor do PC (`pcsrc`) em `"00"` (PC + 4). Todos os sinais gerados pelo `decoder` e pelo `alu_control` são empacotados no barramento `Control_o`.



> **Conclusão:** Neste momento, a Anatomia da Instrução está concluída. O processador "entendeu" o que deve ser feito, e os sinais de controle viajam para o hardware de execução (Datapath) para configurar fisicamente as rotas dos dados.

## 2. O Caminho de Dados (Datapath)

Enquanto a Unidade de Controle atua como o "cérebro" do processador, o Caminho de Dados (Datapath) representa os "músculos". É neste bloco que os dados transitam, são armazenados e transformados. No núcleo de ciclo único (Single-Cycle), o datapath garante que a leitura dos operandos, a execução da operação e a escrita do resultado ocorram dentro de um único ciclo de relógio (clock).



### Banco de Registradores (`reg_file`)

O banco de registradores (Register File) é a estrutura de memória interna mais rápida do processador, composto por 32 registradores de 32 bits, definidos em hardware através do tipo `t_reg_array`. A sua implementação técnica divide-se em abordagens distintas para leitura e escrita:



* **Leitura Assíncrona:** O módulo possui duas portas de leitura independentes (`rs1` e `rs2`) que funcionam de forma puramente combinacional. Assim que os endereços `ReadAddr1_i` ou `ReadAddr2_i` são alterados, os dados correspondentes surgem quase instantaneamente nas saídas `ReadData1_o` e `ReadData2_o`, sem aguardar pelo pulso de clock.
* **Escrita Síncrona:** Diferente da leitura, a atualização de um registrador exige sincronização. A escrita apenas ocorre na transição positiva do sinal de clock (`rising_edge(clk_i)`), e exclusivamente se o sinal de controle `RegWrite_i` estiver ativo (`'1'`).
* **Proteção de Hardware do Registo `x0`:** A convenção da arquitetura RISC-V dita que o registrador `x0` deve conter sempre o valor constante zero. O hardware garante esta regra forçando a saída `x"00000000"` sempre que o endereço de leitura for `"00000"`. Paralelamente, no processo de escrita, existe uma barreira lógica (`WriteAddr_i /= "00000"`) que ignora silenciosamente qualquer tentativa de alteração do registrador zero.

---

### Unidade Lógica e Aritmética (`alu` e `alu_control`)

A Unidade Lógica e Aritmética (ULA, ou ALU em inglês) é o motor computacional do processador, operando em conjunto com o seu controlador dedicado.



**O Controlador da ULA (`alu_control`)**
A Unidade de Controle Principal delega a decisão exata da operação matemática ao `alu_control`. Este módulo secundário avalia o sinal `ALUOp_i` de 2 bits (que indica a categoria da instrução) cruzando-o com os campos `Funct3_i` e `Funct7_i`. O resultado é a geração de um sinal de controle otimizado de 4 bits (`ALUControl_o`). Por exemplo, para operações R-Type (`ALUOp_i = "10"`), o módulo verifica o bit 5 do `Funct7_i` para alternar entre uma soma e uma subtração, ou entre deslocamentos lógicos e aritméticos.

**A Unidade de Execução (`alu`)**
O módulo `alu.vhd` é um bloco puramente combinacional que reage imediatamente a qualquer mudança nos operandos `A_i`, `B_i` ou no comando `ALUControl_i`. Suporta um vasto leque de operações, incluindo:

* **Aritméticas:** Soma e subtração nativas (com tratamento de sinais).
* **Comparações:** Avaliações de "menor que" com e sem sinal (SLT e SLTU).
* **Lógicas:** Operações bit-a-bit XOR, OR e AND.
* **Deslocamentos (Shifts):** Deslocamentos à esquerda (SLL), à direita lógicos (SRL) e à direita aritméticos (SRA).

> **Nota:** A par do resultado de 32 bits, a ULA gera continuamente uma flag fundamental: o sinal `Zero_o`. Esta flag assume o valor `'1'` estritamente quando o resultado numérico de toda a operação de 32 bits for igual a zero (`x"00000000"`).

---

### Unidade de Branch (`branch_unit`)

Em muitas arquiteturas clássicas, o cálculo do desvio condicional é fundido na Unidade de Controle Principal. No entanto, este núcleo RISC-V foi desenhado isolando esta responsabilidade na `branch_unit`, tornando o código mais modular e coeso.

Para decidir se o processador deve saltar para um novo endereço de memória, a `branch_unit` correlaciona três sinais de entrada: o sinal que confirma que a instrução é um desvio (`Branch_i`), a flag matemática gerada pela ULA (`ALU_Zero_i`) e o campo `Funct3_i` que dita a regra de salto. 

Com base nisto, a unidade emite o sinal `BranchTaken_o`:

* **BEQ (Branch if Equal):** Requer que os operandos sejam iguais (A - B = 0). O desvio é tomado se `ALU_Zero_i = '1'`.
* **BNE (Branch if Not Equal):** O desvio avança se a subtração gerar um valor diferente de zero (`ALU_Zero_i = '0'`).
* **Outras avaliações:** O módulo aplica lógicas análogas para BLT, BGE, BLTU e BGEU, combinando a flag Zero resultante de operações SLT/SLTU executadas pela ULA.

## 3. Integração (Top-Level)

A construção de um processador funcional exige que a inteligência da Unidade de Controlo e a força bruta do Caminho de Dados sejam interligadas de forma harmoniosa. Neste projeto, a arquitetura foi refatorada e dividida logicamente para isolar responsabilidades, culminando na união destas entidades no módulo de topo (`processor_top.vhd`).

### O Caminho de Dados (`datapath.vhd`)

O módulo `datapath.vhd` atua como o "circuito de potência" do processador RISC-V. A sua função é estritamente operacional: ele não toma decisões, limitando-se a executar as operações comandadas pelos sinais da Unidade de Controlo.

Este arquivo abriga todos os componentes estruturais responsáveis por armazenar, transportar e processar os dados, incluindo o Contador de Programa (PC), o Banco de Registradores, a ULA e o Gerador de Imediatos. Embora o processador seja de ciclo único, o código do Datapath está didaticamente organizado de forma a espelhar os cinco estágios clássicos de processamento:



* **Busca (FETCH):** Onde o PC atual é registado e utilizado para buscar a instrução na memória (`IMem_data_i`).
* **Decodificação (DECODE):** Onde os geradores de imediatos (`imm_gen`) e o banco de registradores (`reg_file`) extraem os operandos da instrução lida.
* **Execução (EXECUTE):** Onde os multiplexadores selecionam as entradas corretas (registradores ou imediatos) para a ULA calcular resultados aritméticos ou endereços.
* **Memória (MEMORY):** Onde a *Load Store Unit* (LSU) assume o interface com a Memória de Dados (DMEM), tratando do alinhamento e extensão de sinal exigidos por instruções como `lw` ou `sb`.
* **Escrita de Volta (WRITE-BACK):** Onde o multiplexador final decide se o banco de registradores vai receber um dado da ULA, da Memória ou o endereço PC + 4 (no caso de saltos JAL/JALR).

> **Nota de Fluxo:** Além disto, o Datapath calcula o próximo valor do PC, utilizando um multiplexador de prioridade que dá precedência a saltos incondicionais (Jumps) e condicionais (Branches) sobre o incremento padrão de PC + 4.

---

### A Integração no Top-Level (`processor_top.vhd`)

O arquivo `processor_top.vhd` representa a cápsula mais externa do núcleo RISC-V. Este módulo implementa uma **Arquitetura de Harvard Modificada**, expondo barramentos separados para a Memória de Instruções (IMEM) e para a Memória de Dados (DMEM). Esta topologia permite que a CPU busque a próxima instrução em simultâneo com a leitura ou escrita de dados na memória, otimizando o ciclo de processamento.



É neste arquivo que ocorre a conexão estrutural entre os dois grandes blocos do sistema:

* **A Comunicação Ascendente (Feedback):** O Datapath (circuito de potência) envia para o Control Path (circuito de comando) a instrução de 32 bits recém-buscada na IMEM (`s_instruction`) e a flag matemática de zero (`s_alu_zero`).
* **A Comunicação Descendente (Comando):** A Unidade de Controlo analisa a instrução e emite um pacote completo de diretrizes. Em vez de declarar dezenas de sinais soltos, o projeto utiliza uma abordagem elegante através de um *record* VHDL (`t_control`). O pacote `s_ctrl` encapsula todos os sinais (como `reg_write`, seletores de multiplexadores e código da ULA) e é injetado de volta no Datapath para orquestrar o ciclo.

**Conclusão da Arquitetura:**
A união entre o `U_CONTROLPATH` e o `U_DATAPATH` conclui o processador de ciclo único, onde cada instrução da arquitetura RV32I é buscada, decodificada e executada num único, e complexo, pulso de clock.