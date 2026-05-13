# Interface Gráfica Educacional e Depuração

## Visão Geral

O sistema inclui uma interface gráfica educacional executada no computador hospedeiro (Host), responsável por integrar as diferentes funcionalidades do projeto em um único ambiente interativo.

A interface atua como uma camada de abstração entre:

- o usuário (aluno);
- os scripts Python do Host;
- o SoC RISC-V implementado na FPGA.

Seu objetivo principal é permitir que o usuário interaja com o sistema sem necessidade de utilizar diretamente o terminal, facilitando o acesso às funcionalidades de compilação, execução e depuração.

Mais importante do que a tecnologia utilizada para construção da interface é o seu papel dentro da arquitetura do sistema: ela funciona como um ponto de entrada para o fluxo completo de desenvolvimento e depuração.

---

## Arquitetura Geral da Interface

A interface não deve ser interpretada apenas como um componente visual, mas como um elemento integrador que conecta o usuário aos mecanismos internos do sistema.

```mermaid
flowchart TB

User[Usuário]
GUI[Interface Gráfica]
Host[Scripts Python (Host)]
UART[Comunicação Serial]
FPGA[SoC RISC-V]

User --> GUI
GUI --> Host
Host --> UART
UART --> FPGA
FPGA --> UART
UART --> Host
Host --> GUI
```

---

## Papel da Interface no Sistema

### Abstração de Complexidade

A interface permite executar tarefas sem lidar diretamente com:

- terminal;
- comandos de compilação;
- protocolos de comunicação;
- comandos de depuração.

### Orquestração de Fluxos

A GUI centraliza:

- compilação;
- upload de binários;
- execução;
- depuração.

### Integração com Debug

O principal papel da interface é servir como ponto de acesso ao toolchain de depuração.

---

## Ferramenta de Depuração (`debugger.py`)

O `debugger.py` implementa a API de controle do Host, responsável por interagir com o hardware de debug via UART.

### Fluxo de Controle

```text
Usuário → GUI → debugger.py → UART → debug_controller → CPU
```

---

## Comandos de Depuração

A ferramenta permite:

- halt;
- resume;
- step;
- leitura de memória;
- leitura de registradores.

---

## Estrutura de Pacotes

```text
[OPCODE][ENDEREÇO][DADOS]
```

---

## Integração com Hardware

O módulo `debug_controller.vhd` interpreta os comandos e executa:

- parada da CPU;
- leitura/escrita de memória;
- retorno de dados ao Host.

---

## Insight Arquitetural

!!! note "Insight"

    A interface gráfica não implementa lógica de depuração.
    Ela apenas expõe o toolchain de debug de forma acessível.

---

