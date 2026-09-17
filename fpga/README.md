# 💻 FPGA Implementation

Arquivos específicos para síntese em hardware físico. Placas suportadas (selecionadas com `BOARD=` no makefile):

| Placa | `BOARD` | FPGA |
|---|---|---|
| Digilent **Nexys 4** | `nexys4` (padrão) | XC7A100T-1CSG324 |
| Digilent **Nexys A7-100T** | `nexys_a7` | XC7A100T-1CSG324 |

```bash
make fpga-build BOARD=nexys_a7   # bitstream/MCS em build/fpga/nexys_a7/bitstream/
make fpga-prog  BOARD=nexys_a7   # programa via JTAG
make fpga-flash BOARD=nexys_a7   # grava na Flash (FLASH_PART=... sobrescreve a memória)
```

> A Nexys A7-50T não é suportada: o SoC usa ~105 blocos de BRAM e o XC7A50T tem apenas 75.

## Conteúdo do diretório

- `constraints/`: Arquivos de constraints (Xilinx Vivado).
    - `common.xdc`: clock, tensão de configuração, Quad-SPI e exceções de timing (comuns a todas as placas).
    - `nexys4.xdc` / `nexys_a7.xdc`: pinagem de cada placa (CLK, RESET, UART, switches, LEDs e VGA).
- `scripts/`: Scripts TCL para automatizar a síntese e upload na FPGA.
    - `board.tcl`: tabela de placas (part da FPGA, constraints, memória Flash), usada pelos demais scripts.
- `sw/`: Softwares específicos para a implementação em FPGA do SoC.
    - `apps/`: Aplicativos para testes e demos.
    - `platform/`: Softwares específicos para o ecossistema do SoC.
        - `bootloader/`: Código gravado na Boot ROM (para carregamento de softwares via UART).
        - `bsp/` (**Board Support Package**): Mapeamento de memória e camadas de abstração de hardware.
        - `linker/`: Linker scripts para especificação do layout de memória.
        - `startup/`: Pontos de entrada para o bootloader e apps (inicialização).
- `upload.py`: Script para upload de softwares para a placa.
