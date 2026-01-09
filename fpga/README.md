# 💻 FPGA Implementation

Arquivos específicos para síntese em hardware físico (usando a FPGA Digilent **Nexys 4**).

## Conteúdo do diretório

- `constraints/`: Arquivos de pinagem.
    - `pins.xdc` (Nexys 4 - Xilinx Vivado): são mapeados os sinais CLK, RESET, UART_TX, UART_RX e LEDs para os pinos físicos da placa.
- `scripts/`: Scripts TCL para automatizar a síntese e upload na FPGA.
- `sw/`: Softwares específicos para a implementação em FPGA do SoC.
    - `apps/`: Aplicativos para testes e demos.
    - `platform/`: Softwares específicos para o ecossistema do SoC.
        - `bootloader/`: Código gravado na Boot ROM (para carregamento de softwares via UART).
        - `bsp/` (**Board Support Package**): Mapeamento de memória e camadas de abstração de hardware.
        - `linker/`: Linker scripts para especificação do layout de memória.
        - `startup/`: Pontos de entrada para o bootloader e apps (inicialização).
- `upload.py`: Script para upload de softwares para a placa.
