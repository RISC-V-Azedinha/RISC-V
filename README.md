# SoC RISC-V

![VHDL](https://img.shields.io/badge/VHDL-2008-1F5FA8?style=for-the-badge)
![RISC-V](https://img.shields.io/badge/ISA-RV32I__Zicsr-283272?style=for-the-badge)
![C](https://img.shields.io/badge/C-00599C?style=for-the-badge&logo=c&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Cocotb](https://img.shields.io/badge/Testbench-Cocotb-E07B1A?style=for-the-badge)
![FPGA](https://img.shields.io/badge/Platform-FPGA-6A5ACD?style=for-the-badge)

O **SoC RISC-V** é um sistema-em-chip didático escrito em **VHDL-2008**: um núcleo `RV32I_Zicsr` multiciclo ligado por uma interconexão *crossbar* a memórias, controladores de interrupção (CLINT e PLIC), DMA, periféricos e a uma [Unidade de Processamento Neural (NPU)](https://github.com/RISC-V-Azedinha/NPU) própria. O projeto nasceu como parte de um Trabalho de Conclusão de Curso (TCC) e foi validado em FPGA, na Digilent Nexys A7-100T a 100 MHz.

Para a microarquitetura do processador, a interconexão, os periféricos, o software e as aplicações, veja a [documentação](https://risc-v-azedinha.github.io/RISC-V/).

## Características

![Core](https://img.shields.io/badge/Core-Multi--cycle-blue)
![Bus](https://img.shields.io/badge/Bus-Crossbar-success)
![Accelerator](https://img.shields.io/badge/Accelerator-NPU_4x4-orange)

- Núcleo RV32I_Zicsr multiciclo em modo de máquina, com exceções e interrupções; também há uma versão monociclo, usada para estudo;
- Interconexão *crossbar* com arbitragem por escravo: CPU e DMA acessam escravos diferentes no mesmo ciclo;
- Boot ROM de 4 KB com bootloader, RAM de 256 KB e DMA com FIFO, perto de uma palavra por ciclo;
- Periféricos: GPIO (LEDs, chaves, botões, *displays*, LEDs RGB e Pmods), duas UARTs, VGA 320×240 e cartão microSD, com boot sem o computador;
- NPU sistólica 4×4 INT8: executa uma CNN para o MNIST em cerca de 1.500 ciclos (15 µs) por imagem;
- Controlador de depuração pela UART: pausa, passo a passo, *breakpoint* em hardware e leitura dos registradores;
- Verificação com Cocotb (testes unitários, de integração, *end-to-end* e a suíte oficial RV32I) e integração contínua no GitHub Actions.

## Começando rápido

Pré-requisitos: `ghdl`, Python 3 com `cocotb`, `riscv64-unknown-elf-gcc` e, para a FPGA, o Xilinx Vivado.

```bash
# Clonar com o submódulo da NPU
git clone --recursive https://github.com/RISC-V-Azedinha/RISC-V.git

# Simular
make test-unit-alu
make test-e2e-soc_top

# Sintetizar, programar a placa e enviar um programa
make fpga-build BOARD=nexys_a7
make fpga-prog  BOARD=nexys_a7
make upload SW=fibonacci COM=/dev/ttyUSB1
```

Sem argumentos, `make` lista todos os alvos disponíveis.

## Documentação

A documentação completa do projeto — processador, SoC, periféricos, software, aplicações e verificação — está em [`docs/`](docs/) e é servida com [MkDocs](https://www.mkdocs.org/) + [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). É acessível em: [Documentação](https://risc-v-azedinha.github.io/RISC-V/)

Para visualizar localmente:

```bash
pip install mkdocs-material mkdocs-git-revision-date-localized-plugin
mkdocs serve
```

Depois abra `http://127.0.0.1:8000`.

## Estrutura do repositório

```text
RISC-V/
├── docs/            # Documentação (MkDocs)
├── rtl/
│   ├── core/        # Núcleos monociclo e multiciclo
│   ├── soc/         # soc_top, interconexão, memórias, DMA, CLINT, PLIC e depuração
│   └── perips/      # GPIO, UART, VGA, cartão SD e NPU (submódulo)
├── sim/             # Testes Cocotb
├── fpga/
│   ├── constraints/ # XDC das placas Nexys A7 e Nexys 4
│   ├── scripts/     # Síntese, programação e gravação da flash (Vivado)
│   ├── sw/          # Bootloader, BSP/HAL, apps, testes e servidores da NPU
│   └── upload.py    # Envio de programas pela UART
├── tools/           # Clientes da NPU, benchmarks e depurador
├── scripts/         # Seleção de testes da integração contínua
└── makefile         # Testes, compilação, síntese e upload
```
