# Barramento: Mestres e Escravos 

Em um SoC (System on Chip), o barramento é a infraestrutura de comunicação que permite que diferentes blocos funcionais troquem informações. Imagine-o como uma rodovia com regras de trânsito bem definidas (o protocolo).

### 1. Mestres (Masters)
Os **Mestres** são os componentes que possuem "iniciativa". Eles são responsáveis por iniciar uma transação no barramento (seja um pedido de leitura ou de escrita).

* **Core RISC-V:** É o mestre principal. Ele solicita instruções para executar (via interface `IMem`) e solicita leitura/escrita de dados (via interface `DMem`).
* **DMA (Direct Memory Access):** Um mestre especializado que pode mover grandes blocos de dados entre memórias ou periféricos de forma autônoma, sem sobrecarregar o processador.

### 2. Escravos (Slaves)
Os **Escravos** são componentes "reativos". Eles nunca iniciam uma conversa; apenas respondem quando um mestre envia uma solicitação para o seu endereço específico.

* **Memórias (RAM/ROM):** Armazenam dados e instruções. Respondem com o conteúdo solicitado ou confirmam a gravação de um dado.
* **Periféricos (UART, GPIO, VGA, NPU):** Permitem a interação com o mundo exterior. Agem como escravos para que o mestre possa ler status ou configurar seus registradores internos (ex: definir um pino como saída).

---

## Interconectador de Barramento (Bus Interconnect)
O `bus_interconnect` funciona como o "sistema circulatório" do SoC, sendo responsável por conectar o processador aos diversos componentes (memórias e periféricos).

### O Papel do Interconectador
!!! info "Guarda de Trânsito"
    O arquivo `bus_interconnect.vhd` atua como o "guarda de trânsito". Ele analisa o endereço enviado pelo Mestre e decide para qual Escravo aquela mensagem deve ser entregue, garantindo que a resposta volte corretamente para quem a solicitou.

---

## Árbitro de Barramento (Bus Arbiter)

Além do interconectador que roteia os sinais para os escravos corretos, o SoC possui um **árbitro de barramento** (`bus_arbiter.vhd`) responsável por gerenciar o acesso ao barramento compartilhado entre múltiplos mestres (como CPU e DMA), evitando conflitos quando dois ou mais mestres tentam utilizar o barramento simultaneamente.

### 1. Problema da Contenção
!!! danger "Risco de Falha no Sistema"
    A contenção ocorre quando dois mestres (por exemplo, CPU e DMA) sinalizam simultaneamente seus sinais de validade (`m0_vld_i='1'` e `m1_vld_i='1'`), tentando iniciar uma transação no barramento no mesmo ciclo de clock. Sem arbitragem, isso causaria:
    
    * Corrupção de dados no barramento.
    * Comportamento indefinido dos escravos.
    * Possível travamento do sistema.

### 2. Política de Arbitragem Implementada
O árbitro implementa uma política de **prioridade fixa** onde o DMA (Mestre 1) possui prioridade absoluta sobre a CPU (Mestre 0):

* Quando ambos solicitam acesso simultaneamente, o DMA sempre ganha.
* A CPU só é atendida quando o DMA não está solicitando.
* Essa prioridade é implementada na lógica de transição de estado do IDLE.

### 3. Máquina de Estados do Árbitro
O árbitro utiliza uma FSM (Finite State Machine) de 5 estados para gerenciar a concessão e revogação do controle do barramento:

#### Estados da FSM:
* **IDLE**: Estado ocioso. Monitora as requisições dos mestres (`m0_vld_i` e `m1_vld_i`).
    * Se `m1_vld_i='1'` → `GRANT_M1` (DMA vence).
    * Se `m1_vld_i='0'` e `m0_vld_i='1'` → `GRANT_M0` (CPU atendida).
    * Se nenhum solicita → permanece em `IDLE`.

* **GRANT_M1**: Concessão ao DMA.
    * Rota os sinais do DMA para o escravo.
    * Permanece neste estado enquanto o DMA mantém `m1_vld_i='1'`.
    * Transiciona para `WAIT_M1` quando recebe `s_rdy_i='1'` (handshake concluído).

* **GRANT_M0**: Concessão à CPU (similar ao GRANT_M1, mas para a CPU).
    * Transiciona para `WAIT_M0` ao receber `s_rdy_i='1'`.

* **WAIT_M1**: Estado de espera de segurança para o DMA.
    * Mantém o barramento ocupado, mas **não gera novos válidos para o escravo** (`s_vld_r='0'`).
    * Aguarda o DMA baixar seu sinal de validade (`m1_vld_i='0'`).
    * Só libera o barramento (retorna para `IDLE`) quando isso ocorre.
    * **Propósito**: Evita que o árbitro interprete o 'Valid' antigo como uma nova requisição (prevenindo "double write").

* **WAIT_M0**: Estado de espera de segurança para a CPU (análogo ao WAIT_M1).

#### Fluxo em Caso de Contenção:
1. Ambos mestres solicitam em `IDLE` → árbitro vai para `GRANT_M1` (DMA vence por prioridade).
2. DMA realiza transação → handshake com escravo (`s_rdy_i='1'`).
3. Transiciona para `WAIT_M1`.
4. Permanece em `WAIT_M1` até que DMA baixe `m1_vld_i='0'`.
5. Retorna para `IDLE` → nova arbitragem pode ocorrer.
6. CPU fica bloqueada até que o DMA complete e libere o barramento.

### 4. Mecanismo de Prevenção de Dupla Escrita
!!! warning "Prevenção de Double Write"
    Os estados `WAIT_Mx` são cruciais para a correta operação:
    
    * Após o escravo sinalizar `s_rdy_i='1'`, o árbitro **não retorna imediatamente para IDLE**.
    * Em vez disso, entra em `WAIT_Mx` onde força `s_vld_r='0'` (desativando o válido para o escravo).
    * Só libera o controle do barramento quando o mestre correspondente baixa seu sinal de validade.
    * Isso garante que o escravo nunca veja dois pulsos de `vld` consecutivos para a mesma transação.

---

## Protocolo de Sincronização (Handshake)

O protocolo de handshake é fundamental para a operação correta do barramento, especialmente quando lidamos com componentes operando em frequências ou latências diferentes.

### Funcionamento Básico do Handshake

O protocolo utiliza dois sinais fundamentais:
* **`vld` (Valid)**: Sinalizado pelo mestre para indicar que os dados/endereço no barramento são válidos.
* **`rdy` (Ready)**: Sinalizado pelo escravo para indicar que completou o processamento da transação.

> Mais informações do protocolo em [Ready/Valid](../hardware/multi-cycle.md#32-protocolo-de-sincronização-handshake-readyvalid)

### Fluxo de Sinais na Transação

1. **Início pela Master**:
    * Master coloca endereço/dados no barramento.
    * Master afirma seu sinal `mX_vld_i = '1'`.
    * Árbitro (se concedido) roteia este sinal para o escravo como `s_vld_o = '1'`.

2. **Processamento pelo Escravo**:
    * Escravo vê `s_vld_o = '1'` e sabe que os dados são válidos.
    * Escravo processa a solicitação (leitura/escrita).
    * Quando concluído, escravo afirma `s_rdy_i = '1'`.

3. **Confirmação pela Master**:
    * Árbitro roteia `s_rdy_i` de volta para a master correspondente como `mX_rdy_o = '1'`.
    * Master vê `mX_rdy_o = '1'` e sabe que a transação foi concluída.
    * Master então baixa seu sinal `mX_vld_i = '0'`.

### Como o Barramento "Congela" a Transação
!!! tip "Gerenciando Diferenças de Tempo"
    A chave para lidar com diferenças de tempo de resposta está nos **estados WAIT** da FSM do árbitro:
    
    1. **GRANT_Mx** (Concessão ativa):
        * Árbitro mantém concessão ao master.
        * Roteia sinais do master para o escravo (`s_vld_o = mX_vld_i`).
        * Permanece neste estado enquanto aguarda `s_rdy_i = '1'`.
    
    2. **Transição para WAIT_Mx**:
        * Quando `s_rdy_i = '1'` (escravo confirma conclusão).
        * Árbitro muda para estado `WAIT_Mx`.
        * **Neste ponto, o escravo já considerou a transação completa**.
    
    3. **WAIT_Mx** (Estado de segurança):
        * O barramento está efetivamente "congelado" para novas transações.
        * Definições padrão do processo de saída definem `s_vld_r = '0'` (desativando o válido para o escravo).
        * Isso garante que o escravo **não veja um novo pulso de válido** enquanto espera o master baixar seu sinal.
        * Árbitro permanece neste estado até ver `mX_vld_i = '0'` (master baixando seu válido).
        * Só então retorna a `IDLE`, liberando o barramento para nova arbitragem.

### Garantia de Integridade em Diferenças de Tempo

Este mecanismo resolve perfeitamente o problema de um processador rápido esperando um periférico lento:

* **Para o Escravo**: Veja apenas um pulso limpo de `vld` (não há risco de "dupla escrita" porque durante `WAIT_Mx`, `s_vld_o` é forçado a '0').
* **Para o Master**: Recebe confirmação clara (`rdy = '1'`) quando o escravo terminou.
* **Para o Árbitro**: Controla precisamente quando o barramento pode ser liberado para nova arbitragem.
* **Para o Sistema**: Elimina condições de corrida e garante que dados sejam estáveis durante toda a janela de processamento do escravo.

---

## Integração no SoC de Nível Superior

No arquivo `soc_top.vhd`, podemos observar como o árbitro de barramento e o interconectador são integrados no contexto completo do SoC:

### Conexões do Árbitro de Barramento
* **CPU (Master 0)**: Conectada diretamente ao árbitro através dos sinais de DMem (`s_cpu_dmem_*`).
* **DMA (Master 1)**: Conectada ao árbitro através de seus sinais de acesso à memória (`s_dma_m_*`).
* **Slave Output**: O árbitro roteia o acesso concedido para o interconectador (`s_arb_*` → `U_BUS.dmem_*`).

### Detalhes de Integração Relevantes

#### 1. Mapeamento de Sinais do Árbitro (linhas 375-403)

* **Interface Master 0 (CPU):**
    * CPU's DMem address (`s_cpu_dmem_addr`) → árbitro `m0_addr_i`
    * CPU's DMem write data (`s_cpu_dmem_wdata`) → árbitro `m0_wdata_i`
    * CPU's DMem write enable (`s_cpu_dmem_we`) → árbitro `m0_we_i`
    * CPU's DMem valid (`s_cpu_dmem_vld`) → árbitro `m0_vld_i`
    * Árbitro's CPU read data (`m0_rdata_o`) → CPU's DMem read data (`s_cpu_dmem_rdata`)
    * Árbitro's CPU ready (`m0_rdy_o`) → CPU's DMem ready (`s_cpu_dmem_rdy`)

* **Interface Master 1 (DMA):**
    * DMA's memory address (`s_dma_m_addr`) → árbitro `m1_addr_i`
    * DMA's memory write data (`s_dma_m_wdata`) → árbitro `m1_wdata_i`
    * DMA's memory write enable (`s_dma_m_we`) → expandido para 4 bits → árbitro `m1_we_i`
    * DMA's memory valid (`s_dma_m_vld`) → árbitro `m1_vld_i`
    * Árbitro's DMA read data (`m1_rdata_o`) → DMA's memory read data (`s_dma_m_rdata`)
    * Árbitro's DMA ready (`m1_rdy_o`) → DMA's memory ready (`s_dma_m_rdy`)

---

#### 2. Conexão do Árbitro ao Interconectador (linhas 396-403 e 417-423)

* Árbitro's slave address (`s_addr_o`) → interconectador `dmem_addr_i`
* Árbitro's slave write data (`s_wdata_o`) → interconectador `dmem_data_i`
* Árbitro's slave write enable (`s_we_o`) → interconectador `dmem_we_i`
* Árbitro's slave valid (`s_vld_o`) → interconectador `dmem_vld_i`
* Interconectador's DMem read data (`dmem_data_o`) → árbitro's slave read data (`s_rdata_i`)
* Interconectador's DMem ready (`dmem_rdy_o`) → árbitro's slave ready (`s_rdy_i`)

---

#### 3. Tratamento de Sinais de Controle Específicos

!!! note "Write Enable Expansion"
    O DMA possui um sinal WE de 1 bit que é expandido para 4 bits antes de chegar ao árbitro (linhas 273-277 e 391-392):

    ```vhdl
    s_dma_we_expanded <= (others => s_dma_m_we);  -- Expande 1 bit para 4 bits
    ...
    m1_we_i     => s_dma_we_expanded,
    ```

    Isso é necessário porque o árbitro espera sinais WE de 4 bits (como da CPU), enquanto o DMA gera apenas 1 bit.

!!! abstract "Configuração do DMA como Escravo"
    Além de ser um mestre para acesso à memória, o DMA também possui uma interface de escravo para configuração (linhas 459-465):

    ```vhdl
    -- DMA Slave (Config)
    dma_addr_o   => s_dma_s_addr,
    dma_data_i   => s_dma_s_rdata, -- Interconnect lê do DMA
    dma_data_o   => s_dma_s_wdata, -- Interconnect escreve no DMA
    dma_we_o     => s_dma_s_we,
    dma_vld_o    => s_dma_s_vld,
    dma_rdy_i    => s_dma_s_rdy,
    ```

    Isso permite que a CPU programe os registradores do DMA através do barramento.

---

### Fluxo de Dados Completo no SoC

1. **Para Acesso à Memória (CPU ou DMA)**:

    * **Requisição:** Master (CPU ou DMA) coloca endereço/dados e afirma seu sinal válido.
    * **Arbitragem:** Árbitro concede acesso baseado na prioridade (DMA > CPU).
    * **Roteamento:** Árbitro roteia os sinais do master para o interconectador.
    * **Decodificação:** Interconectador decodifica o endereço e roteia para o escravo correto (RAM, ROM, etc.).
    * **Processamento:** Escravo processa e retorna sinal pronto.
    * **Retorno:** O sinal pronto retorna através do interconectador → árbitro → master correspondente.
    * **Finalização:** Master baixa seu sinal válido após receber o sinal de pronto.
    * **Reset:** Árbitro detecta o master baixando o sinal válido e retorna ao estado IDLE.

2. **Para Acesso aos Periféricos**:

    * **Roteamento:** O fluxo segue os mesmos passos da memória, mas o interconectador roteia para os periféricos (UART, GPIO, etc.) com base no endereço mapeado.
    * **Latência:** Periféricos possuem latências variáveis, tornando o *handshake* `ready/valid` essencial para a segurança dos dados.

!!! success "Separação de Responsabilidades"
    Esta arquitetura demonstra uma separação clara de responsabilidades:

    1. **CPU** tem acesso dedicado ao barramento de instruções (IMem) e acesso arbitrado ao barramento de dados (DMem).
    2. **DMA** tem acesso arbitrado ao barramento de dados (para transferências de memória) e acesso configurável via barramento de escravo (para programação do próprio DMA).
    3. **Árbitro** gerencia os conflitos de acesso ao barramento de dados compartilhado entre CPU e DMA.
    4. **Interconectador** roteia as transações aprovadas para o escravo correto baseado no endereço.
    5. **Handshake ready/valid** garante operação segura entre componentes com diferentes latências de resposta.