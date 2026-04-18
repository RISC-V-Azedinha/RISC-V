# Pipeline de Inteligência Artificial Host → FPGA

Esta seção apresenta a especificação formal do fluxo de execução dos
clientes de Inteligência Artificial, descrevendo o caminho completo
percorrido pelos dados desde o treinamento do modelo no computador
hospedeiro até a execução acelerada no SoC RISC-V implementado na FPGA.

O objetivo é consolidar, de forma arquitetural, como software de alto
nível e hardware especializado cooperam para executar inferência de IA.

------------------------------------------------------------------------

## 1. Diagrama Oficial do Pipeline IA → FPGA

O pipeline abaixo representa o fluxo completo implementado pelos
clientes:

``` mermaid
flowchart LR

A[Dataset<br>Iris / MNIST] --> B[Treinamento no Host<br>Scikit-Learn]
B --> C[Extração de Pesos e Bias]
C --> D[Quantização INT8]
D --> E[Serialização em Bytes]
E --> F[Empacotamento UART]
F --> G[Envio Serial]
G --> H[NPU / SoC RISC-V na FPGA]
H --> I[Inferência em Hardware]
I --> J[Resultados Binários]
J --> K[Desserialização]
K --> L[Interpretação no Host]
L --> M[Predição Final + Métricas]
```

### Interpretação do Pipeline

  Etapa                    Responsável
  ------------------------ -------------
  Treinamento              Host (CPU)
  Preparação de dados      Host
  Execução da inferência   FPGA
  Validação e métricas     Host

O hardware atua como um acelerador especializado, enquanto o Host
executa tarefas de alto nível.

------------------------------------------------------------------------

## 2. Protocolo UART --- Especificação Formal

A comunicação entre Host e FPGA utiliza um protocolo orientado a
comandos (*opcode-based protocol*).

Cada mensagem inicia com um opcode de 1 byte, seguido por parâmetros
opcionais.

### 2.1 Tabela Oficial de Opcodes

  --------------------------------------------------------------------------
  Opcode   ASCII   Direção      Função                    Payload
  -------- ------- ------------ ------------------------- ------------------
  0x50     P       Host → FPGA  Sincronização             nenhum

  0x4C     L       Host → FPGA  Upload de pesos           tamanho + dados

  0x43     C       Host → FPGA  Configuração NPU          parâmetros

  0x54     T       Host → FPGA  Configurar tiling         dimensões

  0x49     I       Host → FPGA  Enviar input              vetor de entrada

  0x42     B       Host → FPGA  Executar inferência       flags

  0x4B     K       FPGA → Host  ACK (OK)                  nenhum
  --------------------------------------------------------------------------

### 2.2 Estrutura Geral do Pacote

```text      
[OPCODE][TAMANHO][PAYLOAD]
```          

-   OPCODE → identifica operação\
-   TAMANHO → inteiro de 32 bits (little-endian)\
-   PAYLOAD → dados serializados

### 2.3 Exemplo --- Upload de Pesos

```text  
[L][SIZE][WEIGHTS...]
4C | 00 10 00 00 | <4096 bytes>
```   

Resposta:

    4B (ACK)

### 2.4 Protocolo de Inferência

``` mermaid
sequenceDiagram
participant Host
participant FPGA

Host->>FPGA: P (sync)
FPGA-->>Host: P

Host->>FPGA: L + pesos
FPGA-->>Host: K

Host->>FPGA: C
Host->>FPGA: T

loop Inferência
Host->>FPGA: I + input
Host->>FPGA: B
FPGA-->>Host: resultados
end
```

------------------------------------------------------------------------

!!! note "Resumo"

    Os clientes de IA realizam treinamento no Host, convertem os dados e  
    enviam para a FPGA via UART. A FPGA executa a inferência e retorna os  
    resultados.

------------------------------------------------------------------------

## Fluxo Final
``` text
    Treinamento
    ↓
    Quantização
    ↓
    Serialização
    ↓
    UART
    ↓
    FPGA
    ↓
    Inferência
    ↓
    Resultados
```