# Interface Gráfica Educacional e Depuração

## Visão Geral

O sistema inclui uma interface gráfica educacional executada no
computador hospedeiro (**Host**), responsável por integrar todas as
frentes do projeto em um único ambiente interativo.

A aplicação permite que alunos interajam com o SoC RISC-V na FPGA sem
necessidade de utilizar o terminal ou executar comandos manualmente.

A interface atua como uma camada de abstração entre:

-   o usuário (aluno);
-   os scripts Python do Host;
-   o acelerador de hardware implementado na FPGA.

Seu objetivo principal é transformar conceitos avançados de arquitetura
de computadores e aceleração de IA em uma experiência visual e
intuitiva.

------------------------------------------------------------------------

## Arquitetura Geral da Interface

A aplicação é implementada em **Python utilizando Tkinter**, organizada
em três camadas principais:

1.  **Camada de Interface (GUI)** --- interação com o usuário;
2.  **Camada de Controle (Driver/Host Scripts)** --- lógica de
    comunicação;
3.  **Camada de Hardware** --- execução no SoC RISC-V.

``` mermaid
flowchart TB

User[Usuário]
GUI[Interface Gráfica]
Driver[NPU Driver]
UART[Comunicação Serial]
FPGA[SoC RISC-V]

User --> GUI
GUI --> Driver
Driver --> UART
UART --> FPGA
FPGA --> UART
UART --> GUI
```

A interface gráfica centraliza todas as operações do sistema, permitindo
que o usuário execute tarefas complexas através de ações visuais
simples.

------------------------------------------------------------------------

## Integração da Interface com o Sistema

A GUI atua como um **orquestrador de operações**, disparando scripts
Python responsáveis por:

-   compilação de programas;
-   envio de binários para FPGA;
-   execução de modelos de IA;
-   comunicação serial UART;
-   operações de depuração.

O fluxo geral ocorre da seguinte forma:

``` mermaid
sequenceDiagram
participant Usuario
participant GUI
participant Host
participant FPGA

Usuario->>GUI: Ação (botão/menu)
GUI->>Host: Executa script Python
Host->>FPGA: Envia comandos UART
FPGA-->>Host: Resposta
Host-->>GUI: Resultado
GUI-->>Usuario: Atualização visual
```

------------------------------------------------------------------------

# Interface de Depuração --- API de Controle do Host

## Ferramenta de Depuração (`debugger.py`)

O arquivo `debugger.py` implementa a **interface de depuração executada
no Host**, responsável por controlar e inspecionar a execução do núcleo
RISC-V através de comunicação serial UART.

Esta ferramenta representa a camada de software do sistema de debug,
enviando comandos binários específicos interpretados pelo módulo de
hardware `debug_controller.vhd`.

------------------------------------------------------------------------

### Objetivos da ferramenta

-   interromper a execução do processador (**halt**);
-   retomar execução (**resume**);
-   executar instruções individualmente (**step**);
-   configurar e remover breakpoints;
-   ler registradores e estado interno do núcleo;
-   traduzir comandos do usuário em pacotes binários de baixo nível.

------------------------------------------------------------------------

## Arquitetura Host--Target

A arquitetura segue o modelo clássico **Host--Target**, amplamente
utilizado em sistemas embarcados e ambientes de depuração:

``` mermaid
flowchart TB

UserCLI[Usuário]
Debugger[Debugger Python]
UART[UART Serial]
DebugHW[debug_controller.vhd]
CPU[Núcleo RISC-V]

UserCLI --> Debugger
Debugger --> UART
UART --> DebugHW
DebugHW --> CPU
```

Nesse modelo:

-   o **Host** executa a ferramenta de depuração;
-   o **Target** corresponde ao hardware na FPGA;
-   a comunicação ocorre por meio de pacotes UART.

------------------------------------------------------------------------

## Construção dos Pacotes de Depuração

O `debugger.py` converte comandos de alto nível em **frames binários
UART**, compreendidos pelo controlador de depuração em hardware.

### Estrutura Conceitual do Pacote

    [HEADER][OPCODE][ARGUMENTOS][CHECKSUM]

  Campo        Função
  ------------ -------------------------------
  HEADER       Indica início do comando
  OPCODE       Tipo de operação de debug
  ARGUMENTOS   Endereços ou dados adicionais
  CHECKSUM     Validação de integridade

------------------------------------------------------------------------

### Principais Comandos

  Operação     Descrição
  ------------ --------------------------------------
  HALT         Interrompe a execução do processador
  RESUME       Retoma execução normal
  STEP         Executa uma única instrução
  READ         Lê memória ou registradores
  BREAKPOINT   Define ponto de parada

Cada comando é serializado em bytes antes do envio pela UART.

------------------------------------------------------------------------

## Fluxo de Depuração

``` mermaid
sequenceDiagram
participant Usuario
participant Debugger
participant FPGA

Usuario->>Debugger: Comando de debug
Debugger->>FPGA: Frame UART
FPGA->>FPGA: Controle do núcleo
FPGA-->>Debugger: Resposta
Debugger-->>Usuario: Estado atualizado
```

------------------------------------------------------------------------

## Papel Educacional da Interface

A integração entre GUI e debugger permite que estudantes:

-   observem a execução do processador em tempo real;
-   compreendam o ciclo de execução de instruções;
-   experimentem conceitos de arquitetura RISC-V;
-   realizem inspeção de memória e registradores sem conhecimento prévio
    de ferramentas avançadas.

Dessa forma, a interface transforma mecanismos complexos de depuração em
uma experiência acessível e pedagógica.

------------------------------------------------------------------------

## Benefícios Arquiteturais

A separação entre GUI, scripts Host e hardware proporciona:

-   modularidade do sistema;
-   facilidade de manutenção;
-   reutilização dos componentes;
-   escalabilidade para novos experimentos educacionais;
-   isolamento entre interface e lógica de baixo nível.
