# Requisitos e Setup

!!! warning "Dependências do Sistema"
    Para compilar, simular e interagir com este projeto, instale as seguintes ferramentas e certifique-se de que elas estão no seu PATH:

* **GHDL**: Simulador VHDL open-source.
* **GTKWave**: Visualizador de formas de onda.
* **RISC-V GCC Toolchain**: Necessário para compilar os softwares C/Assembly nativamente para a arquitetura (`riscv64-unknown-elf-gcc`).
* **COCOTB**: Framework Python para testbenches baseados em corrotinas.
* **Python 3.10+**: Necessário para rodar o Cocotb, utilitários de build e drivers de host.
* **Xilinx Vivado**: Opcional. Apenas se for realizar a síntese e gravação na placa FPGA (Nexys 4 DDR).


## Automação via Makefile

Todos os comandos devem ser executados a partir da raiz do repositório. O Makefile automatiza completamente o fluxo de simulação, compilação de software, visualização e síntese.

O sistema de build foi projetado para ser multiplataforma, detectando automaticamente se você está operando em um ambiente Linux nativo ou WSL (Windows Subsystem for Linux), ajustando as chamadas de executáveis (como vivado.exe ou python.exe) conforme necessário.

## Limpeza do Projeto

Remove todos os artefatos de build gerados (arquivos HEX, BIN, formas de onda e diretórios temporários):

```bash
make clean
```

## Compilação de Software

Compile um programa escrito em C ou Assembly (localizado no diretório sw/apps/) para uso na simulação ou FPGA:

```bash
make sw SW=<program_name>
```

## Simulação com Cocotb

Rode testes automatizados informando o nome do testbench (TEST) e da entidade de topo (TOP). Opcionalmente, você pode especificar qual microarquitetura testar (CORE) e injetar um software na memória durante a inicialização (SW):

```bash
make cocotb [CORE=<core>] TEST=<testbench_name> TOP=<top_level> [SW=<program_name>]
```

!!! example "Visualização de Ondas"
    Para abrir a última simulação gerada no GTKWave e analisar os sinais lógicos em detalhes, execute:

    ```bash
    make view [CORE=<core>] TEST=<testbench_name>
    ```


## Atalhos e Comandos Úteis

Já existem atalhos configurados no Makefile para facilitar a listagem de arquivos e execução de tarefas comuns:

- `make info`: Mostra as configurações do sistema, paths e detecção de ferramentas instaladas.
- `make list-apps`: Lista todos os programas em C/Assembly disponíveis para compilação.
- `make list-tests`: Lista todos os testbenches prontos para serem simulados (separados por integração, unidade e periféricos).
- `make fpga`: Sintetiza o hardware, implementa e gera o bitstream utilizando os scripts Tcl do Vivado.
- `make upload SW=<program_name>`: Envia o software compilado diretamente para a memória do processador na FPGA através da comunicação serial UART.