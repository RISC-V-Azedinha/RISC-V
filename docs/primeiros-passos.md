# Primeiros passos

Este capítulo descreve as ferramentas necessárias e os comandos para simular o SoC, compilar programas e executá-los na FPGA. Todos os comandos são executados na raiz do repositório; sem argumentos, `make` mostra a lista de alvos.

## Ferramentas

!!! warning "Dependências do sistema"
    Instale as ferramentas abaixo e verifique se estão no `PATH`:

    * **GHDL:** simulador VHDL de código aberto;
    * **GTKWave:** visualizador de formas de onda;
    * **RISC-V GCC** (`riscv64-unknown-elf-gcc`, com a `picolibc`): compila os programas em C e Assembly para o núcleo;
    * **Python 3** com **Cocotb** e **pyserial:** testes e ferramentas do hospedeiro;
    * **Xilinx Vivado:** apenas para síntese e gravação na FPGA.

A NPU é um submódulo Git. Ao clonar o repositório, traga-o junto:

```bash
git clone --recursive https://github.com/RISC-V-Azedinha/RISC-V.git
# ou, num clone já existente:
git submodule update --init --recursive
```

## Simulação

Os testes usam Cocotb com o GHDL e se dividem em três níveis, cada um com o seu alvo:

```bash
make list-tests                 # lista os testes disponíveis
make test-unit-alu              # unitário: um bloco isolado (aqui, a ULA)
make test-int-datapath          # integração: vários blocos do núcleo juntos
make test-e2e-processor_top     # end-to-end: o processador executando um programa em C
make test-e2e-soc_top           # end-to-end: o SoC completo, com o bootloader
make test-compliance            # suíte oficial de conformidade RV32I
```

Por padrão, os testes usam o núcleo multiciclo; para o monociclo, acrescente `CORE_ARCH=single_cycle`. Nos testes *end-to-end* do processador, `APP=<programa>` escolhe o programa de `sim/core/<núcleo>/e2e/sw/apps/` (o padrão é `hello`). Cada teste grava as formas de onda em `build/<núcleo>/<teste>/wave.vcd`, que podem ser abertas no GTKWave:

```bash
gtkwave build/multi_cycle/alu/wave.vcd
```

Os detalhes estão em [Verificação](desenvolvimento/verificacao.md).

## Execução na FPGA

### Gerar o *bitstream* e programar a placa

```bash
make fpga-build BOARD=nexys_a7    # síntese, implementação, bitstream (.bit) e imagem da flash (.mcs)
make fpga-prog  BOARD=nexys_a7    # programa a FPGA pelo JTAG (volátil)
make fpga-flash BOARD=nexys_a7    # grava a flash: a placa passa a iniciar com o SoC sozinha
```

`BOARD` aceita `nexys4` (padrão) e `nexys_a7`. O bootloader é compilado e embutido na Boot ROM durante a síntese. O fluxo está descrito em [Síntese em FPGA](desenvolvimento/sintese.md).

### Enviar um programa

Com a placa programada, o bootloader espera um programa pela UART. Para compilar e enviar um programa de `fpga/sw/apps/`, `fpga/sw/tests/` ou `fpga/sw/server/`:

```bash
make list-apps                              # lista os programas disponíveis
make upload SW=fibonacci COM=/dev/ttyUSB1   # compila e envia pela UART
make upload SW=demo SAVE=1                  # envia e grava também no cartão microSD
make sd-erase                               # apaga o programa do cartão
```

Com o programa gravado no cartão microSD e o SoC gravado na flash, a placa passa a executá-lo sozinha ao ser ligada, sem o computador ([Cartão microSD](perifericos/sd.md)). O protocolo de envio está em [Boot](software/boot.md).

!!! tip "Próximos passos"
    Para entender o processador, comece pela [microarquitetura multiciclo](processador/multiciclo.md); para escrever programas, veja [Compilação e build](software/build.md) e os [programas de exemplo](aplicacoes/programas.md).

Para remover os artefatos gerados, use `make clean`.
