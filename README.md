# RISC-V: Processador RV32I em VHDL

![VHDL](https://img.shields.io/badge/VHDL-2008-blue?style=for-the-badge&logo=vhdl)
![RISC-V](https://img.shields.io/badge/ISA-RISC--V%20RV32I-yellow?style=for-the-badge&logo=riscv)
![GHDL](https://img.shields.io/badge/Simulator-GHDL-green?style=for-the-badge&logo=ghdl)
![GTKWave](https://img.shields.io/badge/Waveform-GTKWave-9cf?style=for-the-badge&logo=gtkwave)
![Python](https://img.shields.io/badge/Python-3.10-blue?style=for-the-badge&logo=python)


```
   ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗
   ██╔══██╗██║   ██║╚════██╗╚════██╗██║
   ██████╔╝██║   ██║ █████╔╝ █████╔╝██║
   ██╔══██╗╚██╗ ██╔╝ ╚═══██╗██╔═══╝ ██║     
   ██║  ██║ ╚████╔╝ ██████╔╝███████╗██║     ->> PROJETO: Processador RISC-V (RV32I) 
   ╚═╝  ╚═╝  ╚═══╝  ╚═════╝ ╚══════╝╚═╝     ->> DATA INÍCIO: 15/09/2025

```

Este repositório contém a implementação de um processador RISC-V de 32 bits (ISA RV32I). O projeto é desenvolvido inteiramente em VHDL-2008, possui design modular e foi focado no estudo de arquitetura de computadores e design de processadores, suportando implementações físicas em FPGA.

## 📖 Documentação Completa

Toda a documentação detalhada sobre as microarquiteturas (monociclo e multiciclo), barramentos, simulação e mapeamento de memória foi organizada usando MkDocs.

👉 [Acesse a Documentação Completa Aqui!](https://RISC-V-Azedinha.github.io/RISC-V/)

## 🎯 Goals and Features

* **Target ISA:** RISC-V RV32I (Base Integer Instruction Set).
* **Microarquiteturas:** Single-cycle, multi-cycle, pipelined [on future].
* **Modularidade:** Componentes (ALU, RegFile, Control Unit) separados para clareza e fins educacionais.
* **Integração:** System-on-Chip (SoC) com suporte a Bootloader, interconexão de barramentos e mapa de memória customizável.
* **Periféricos**: Controladores integrados para GPIO, UART (Comunicação Serial) e saída de vídeo VGA.

## 🛠️ Stack Tecnológica

O projeto utiliza um ecossistema moderno para automação, compilação de software, validação de hardware e síntese:

* **VHDL-2008:** Linguagem principal de Descrição de Hardware (RTL).

* **RISC-V GCC Toolchain:** Utilizada para compilar as aplicações escritas em C e Assembly nativamente para o processador.

* **GHDL:** Simulador open-source utilizado para validação lógica.

* **Cocotb / Python 3:** Framework para testbenches baseados em corrotinas, permitindo testes ágeis e auto-verificáveis.

* **GTKWave:** Análise e debug de formas de onda (VCD).

* **Xilinx Vivado:** Síntese e implementação em FPGA (focado na placa Nexys 4 DDR).

* **Make:** Automação de todo o fluxo (simulação dinâmica, compilação de software C/ASM e deploy no hardware) totalmente compatível com Linux e WSL.

## 🧪 Verificação e Execução de Software

A validação do processador é garantida através de testes exaustivos usando Cocotb. O sistema realiza a simulação isolada de componentes unitários e testes de integração avançados no nível do SoC.

Além dos testes lógicos, a arquitetura permite a compilação e execução dinâmica de softwares reais:

1. Códigos em C/Assembly são compilados através do Makefile.
2. O binário/Hex gerado é automaticamente injetado no Boot ROM ou carregado na memória.
3. O código é executado em simulação ou diretamente na FPGA via upload UART.

Aplicações incluídas nativamente no repositório:

- 🧮 **Fibonacci & Fractals:** Cálculos matemáticos em C para benchmarking.
- 🏓 **Pong:** Jogo clássico utilizando a saída VGA e drivers de hardware implementados na plataforma.
- 🔄 **Testes ISA:** Cobertura de instruções, rotinas de interrupção (IRQ) e acesso a registradores CSR.

## 📂 Estrutura do Repositório

```text
RISC-V/
├── rtl/               # Código RTL em VHDL (Core, Periféricos, Integração SoC)
├── sim/               # Testbenches automatizados em Python (Cocotb)
├── sw/                # Aplicações C/Assembly e BSP (Simulação)
├── fpga/              # Restrições (XDC), Scripts Vivado, BSP e Upload UART
├── pkg/               # Pacotes VHDL (Definições globais da ISA RISC-V)
├── docs/              # Documentação em MkDocs e assets
└── makefile           # Sistema modular de automação (Build/Sim/Software)
```
