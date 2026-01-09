# 📟 Register Transfer Level (RTL)

Este diretório contém todo o código fonte VHDL sintetizável do projeto. A estrutura é dividida para garantir modularidade, organização e manutenibilidade.

## 1. Core (`rtl/core/`)

Contém o **IP do Processador**.

- Os arquivos aqui NÃO devem saber nada sobre o mundo externo (UART, RAM específica, FPGA).
- A interface é apenas: Clock, Reset, Barramento de Instrução (Addr/Data) e Barramento de Dados (Addr/Data/We).
- Exemplos: `alu.vhd`, `control.vhd`, `processor_top.vhd`.
- Dividido em sub-diretórios para cada CORE (single-cycle, multi-cycle etc.) implementado.

## 2. SoC (`rtl/soc/`)

Implementação de **System on a Chip** (SoC).
- Aqui ficam os componentes que ligam o processador aos periféricos.
- Componentes Chave:
    - `boot_rom.vhd`: Memória de inicialização do SoC (carrega o bootloader).
    - `bus_interconnect.vhd`: Decodifica endereços e roteia dados. Abstrai o espaço de endereçamento para o processador.
    - `dual_port_ram.vhd`: Memória principal compatível com arquitetura Harvard.
    - `soc_top.vhd`: O nível mais alto da hierarquia, que instancia tudo.

## 3. Perips (`rtl/perips/)`

Contém os **periféricos**.

- Módulos escravos que respondem ao barramento.
- Exemplos:
    - `uart/`: Transmissor e Receptor Serial.
    - `gpio/`: Controlador de LEDs e Botões.
    - `vga/`: Controlador de Vídeo (VGA).