# 🗺️ Roadmap: RISC-V SoC (System on a Chip)

Este documento rastreia o status de desenvolvimento do SoC RISC-V, desde a refatoração do Core até a implementação na FPGA e desenvolvimento da HAL.

---

## 🟡 Fase 0: Core Single-Cycle (Concluído)
*Arquitetura base onde cada instrução termina em 1 ciclo de clock. Serviu para validação inicial da lógica.*

- [x] **Datapath (`datapath.vhd`)**
  - [x] Execução direta: `PC` -> `IMem` -> `Decoder` -> `RegFile` -> `ALU` -> `DMem` -> `WB`.
  - [x] Unidade de Branch combinacional (`branch_unit.vhd`).
- [x] **Controle (`control.vhd`)**
  - [x] Decodificação combinacional de `Opcode` (7 bits) para sinais `ALUSrc`, `MemtoReg`, `RegWrite`.
- [x] **Validação**
  - [x] Testes unitários com instruções R-Type, I-Type, Load/Store e Branch.

---

## 🟢 Fase 1: Refatoração Multi-Cycle (Concluído)
*Introdução de máquina de estados para suportar clocks mais altos (reduzir caminho crítico), reutilização de recursos e permitir o uso de memórias síncronas (como BRAM)*

- [x] **Infraestrutura do Projeto**
  - [x] Limpeza e reestruturação de diretórios (`rtl/core`, `rtl/soc`, `rtl/perips`).
  - [x] Atualização do `makefile` e scripts de simulação.
  - [x] Separação de arquivos de teste (`sim/core`).

- [x] **Datapath Multi-Cycle (RTL)**
  - [x] **Registradores de Barreira (`datapath.vhd`)**
      - [x] `IR` (Instruction Register) com sinal `IRWrite`.
      - [x] `MDR` (Memory Data Register) para capturar dados da memória.
      - [x] `ALUOut` para armazenar endereços calculados ou resultados parciais.
      - [x] `Reg A` e `Reg B` para estabilizar entradas da ALU.
  - [x] **FSM (`main_fsm.vhd`)**
      - [x] Estados definidos: `S_FETCH` -> `S_DECODE` -> (`S_EXEC_R` | `S_MEM_ADDR` | `S_BRANCH`...) -> `S_WB`.
      - [x] Controle de PC: `PCWrite` (incondicional) e `PCWriteCond` (Branches).
  - [x] **Modularização do Controle**
      - [x] Separação em `main_fsm`, `control_decoder` e `alu_decoder`.
  - [x] Implementação de PC com *Write Enable*.

- [x] **Unidade de Controle (FSM)**
  - [x] Modularização em `main_fsm`, `control_decoder` e `alu_decoder`.
  - [x] Definição e implementação dos estados (Fetch, Decode, Exec, Mem, WB).
  - [x] Integração no `control_top.vhd`.

- [x] **Integração do Processador**
  - [x] Conexão `datapath` + `control_top` em `processor_top.vhd`.

---

## 🟡 Fase 2: Infraestrutura do SoC (Concluído)
*Criação do barramento e sistema de memória para suportar o processador. Integração do Core com o mundo exterior.*

- [x] **Barramento e Memória**
  - [x] `bus_interconnect`: Decodificação de endereços (ROM, RAM, Periféricos).
  - [x] `boot_rom`: Memória de programa (Read-Only) para boot.
  - [x] `dual_port_ram`: Memória principal (Instrução/Dados).
  - [x] Linker Script (`link_soc.ld`) apontando para RAM em `0x80000000`.

- [x] **Mapa de Memória (`bus_interconnect.vhd`)**
  - [x] `0x00000000` - `0x00000FFF`: Boot ROM (4KB) [Read-Only].
  - [x] `0x10000000` - `0x10000FFF`: Periféricos (IO Mapped).
  - [x] `0x80000000` - `0x80000FFF`: Main RAM (Dual Port).

- [x] **Periféricos Básicos**
  - [x] `uart_controller`: Tx e Rx funcionais.
  - [x] `gpio_controller`: controle básico dos LEDs e SWs.

- [x] **Top Level do Sistema**
  - [x] `soc_top`: Instanciação de Core, Barramento, Memórias e UART.

---

## 🟢 Fase 3: Deployment FPGA & Toolchain (Concluído)
*Ferramentas de síntese, implementação e carga de software.*

- [x] **Síntese (`build.tcl`)**
  - [x] Target: Artix-7 (`xc7a100tcsg324-1`).
  - [x] Estratégia: `flatten_hierarchy rebuilt` e `retiming` ativado.
  - [x] Constraints: `pins.xdc` mapeando Clock, Reset, UART e LEDs.

- [x] **Bootloader (`boot.c`)**
  - [x] Protocolo: Handshake "Magic Word" (`0xCAFEBABE`) -> Recebe Size -> Grava na RAM.
  - [x] Jump para User App em `0x80000800`.

- [x] **Host Tool (`upload.py`)**
  - [x] Script Python para enviar binários via Serial.

---

## 🟠 Fase 3: Periféricos e IO (Em Progresso)
*Expansão das capacidades de entrada e saída do sistema.*

- [ ] **Controlador de GPIO V2** (`gpio_controller.vhd`)
  - [ ] Implementar registradores de direção (DDR) e dados (PORT/PIN).
  - [ ] Conectar aos LEDs/SWs/BTNs no Top Level.

- [ ] **Controlador de Interrupções (Opcional/Futuro)**
  - [ ] Adicionar suporte básico a interrupções externas (UART/GPIO).
  - [ ] Implementar registrador CSR `mie` e `mip` no Core.

---

## 🔵 Fase 4: Software & HAL (A Fazer)
*Camada de abstração de hardware para facilitar o desenvolvimento de aplicações.*

### 4.1. Definições de Baixo Nível
- [x] **Memory Map Header**
  - [x] Criar/Atualizar `sw/platform/bsp/memory_map.h` com endereços base finais.
  - [x] Definir offsets de registradores (ex: `UART_TX_REG`, `GPIO_DATA_REG`).

### 4.2. Hardware Abstraction Layer (HAL)
- [x] **HAL UART** (`hal_uart.c/h`)
  - [x] `void hal_uart_putc(char c);`
  - [x] `char hal_uart_getc();`
  - [x] `int hal_uart_has_data();`
- [ ] **HAL GPIO** (`hal_gpio.c/h`)
  - [ ] `void hal_gpio_pin_mode(int pin, int mode);`
  - [ ] `void hal_gpio_write(int pin, int value);`
  - [ ] `int hal_gpio_read(int pin);`

### 4.3. Aplicações e Testes
- [x] **Bootloader Assembly** (Salto inicial para RAM).
- [ ] **Portar Aplicações de Teste**
  - [ ] Adaptar `hello.c` para usar a nova HAL.
  - [x] Recompilar `fibonacci.c` para a arquitetura de memória do SoC.

---

## 🔴 Fase 5: FPGA e Síntese (A Fazer)
*Levar o design para o hardware físico.*

- [x] **Constraints**
  - [x] Criar `.xdc` mapeando pinos da placa (Clock 100MHz, Reset, pinos UART USB, LEDs).
- [x] **Fluxo de Build**
  - [x] Criar script Tcl (`build.tcl`) para síntese, implementação e geração de bitstream (Vivado).
  - [x] Integrar comandos de FPGA no `makefile` (`make fpga`).
- [x] **Teste em Hardware**
  - [x] Upload do bitstream.
  - [x] Upload do software via UART (usando script Python ou Bootloader).
