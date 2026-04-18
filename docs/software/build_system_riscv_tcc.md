# Infraestrutura de Compilação e Build System (GNU Make)

## Visão Geral

Esta seção documenta a infraestrutura de compilação (*toolchain*) e o
sistema de automação de tarefas (*build system*) baseado em GNU Make
utilizado no projeto.

O objetivo é descrever, sob uma perspectiva arquitetural, como
códigos-fonte escritos em C e Assembly são traduzidos em binários
executáveis para a arquitetura RISC-V (RV32I), bem como explicar como o
sistema orquestra as etapas de simulação e síntese do hardware.

O Build System atua como um componente central de integração entre:

-   o ambiente de desenvolvimento no Host (software);
-   a arquitetura do SoC RISC-V na FPGA (hardware);
-   os fluxos de simulação e implementação.

------------------------------------------------------------------------

## 1. Cadeia de Compilação RISC-V (Cross-Compilation)

O projeto utiliza o modelo de **cross-compilation**, no qual o código é
compilado em uma arquitetura Host (x86_64) para execução em uma
arquitetura distinta (RISC-V RV32I).

### 1.1 Pipeline de Compilação

``` mermaid
flowchart LR
A[C / Assembly] --> B[Pré-processamento]
B --> C[Compilação (GCC)]
C --> D[Assembly RISC-V]
D --> E[Montagem]
E --> F[Objeto (.o)]
F --> G[Linking (link.ld)]
G --> H[Executável (.elf)]
```

### 1.2 Etapas do Processo

**Pré-processamento** - Expansão de macros (`#define`); - Inclusão de
bibliotecas (`#include`); - Preparação do código fonte.

**Compilação** - Tradução do código C para assembly RISC-V; - Aplicação
de otimizações específicas.

**Montagem (Assembling)** - Conversão do assembly em código de
máquina; - Geração de arquivos objeto (`.o`).

**Linking** - Combinação dos objetos gerados; - Aplicação do script de
ligação (`link.ld`); - Definição do layout de memória do sistema.

**Saída Final** - Arquivo executável no formato `.elf`.

### 1.3 Configuração da Arquitetura

    -march=rv32i
    -mabi=ilp32

------------------------------------------------------------------------

## 2. Arquitetura Modular do Build System

``` mermaid
flowchart TB
Makefile --> config.mk
Makefile --> detect.mk
Makefile --> sources.mk
Makefile --> rules_sw.mk
Makefile --> rules_sim.mk
Makefile --> rules_fpga.mk
```

------------------------------------------------------------------------

## 3. Regras de Software

``` mermaid
flowchart LR
SRC --> OBJ --> ELF --> BIN --> HEX
```

------------------------------------------------------------------------

## 4. Geração de Artefatos

ELF → BIN/HEX via objcopy.

------------------------------------------------------------------------

## 5. Orquestração

``` mermaid
flowchart TB
User --> Make --> Software --> ELF --> BIN --> FPGA
```

------------------------------------------------------------------------

## 6. Resumo Executivo

O Build System automatiza a compilação cruzada e a execução de
aplicações RISC-V em FPGA.
