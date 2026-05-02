# Software Development

Este diretório contém o código fonte para rodar no SoC RISC-V.

## Estrutura

### `bootloader/`

Contém o Zero Stage Bootloader (ZSBL).
- Este código é compilado para começar no endereço 0x0000_0000.
- Ele é gravado permanentemente na boot_rom do SoC.
- Função: Inicializar a pilha e (futuramente) carregar programas via UART para a RAM.

### `apps/`

Contém os Programas de Usuário.
- Exemplos: `hello.c`, `fibonacci.c`, `test_all.s`.
- Este código é compilado para rodar a partir de `0x80000000` (RAM).
- Ele assume que o bootloader já configurou o sistema básico.

### `common/`

Arquivos compartilhados.
- `link.ld`: O script do linker que define onde fica a RAM (`0x80000000`).
- `memory_map.h`: Definições #define para registradores de MMIO (UART, LEDs).

## Compilação

O **makefile** na raiz do projeto gerencia a compilação cruzada. Ele gera arquivos `.hex` (para simulação) e binários (para upload).