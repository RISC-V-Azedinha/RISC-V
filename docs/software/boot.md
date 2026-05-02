# Processo de Boot do RISC-V

Este documento descreve o processo de inicialização do processador RISC-V, desde o sinal de reset elétrico até a execução da aplicação do usuário. O fluxo segue uma hierarquia de níveis: primeiro o código em Assembly (`crt0.s`/`start.s`) prepara o ambiente mínimo para execução em C, e em seguida o bootloader em C (`boot.c`) assume o controle para carregar e executar a aplicação final.

---

## 1. O Processo de Inicialização de Baixo Nível (Startup em Assembly)

### 1.1 O Fluxo de Execução Imediatamente Após o Reset

Quando o processador RISC-V sai do estado de reset, o contador de programa (PC - Program Counter) é forçado ao endereço de boot definido pelo hardware. Este endereço é tipicamente `0x00000000` em sistemas que executam código a partir de memória ROM/Flashon-chip, ou pode ser configurado via sinais externos em FPGAs.

A partir deste ponto, o processador começa a executar instruções sequencialmente, sem qualquer contexto de software previamente estabelecido. Não existe pilha, não existem variáveis globais inicializadas, e os registradores possuem valores indeterminados (ou zero, dependendo da implementação). O código executado nesta fase é denominado **startup code** ou **bootloader primário**, e sua única função é preparar o ambiente para que código C possa ser executado de forma confiável.

O ponto de entrada é simbolizado pelo rótulo `_start`, que deve ser declarado como símbolo global para que o linker possa resolvê-lo. No RISC-V, a convenção de nomes com underscore prefixado (`_start`) é utilizada para distinguir o símbolo de entrada do padrão C que espera `main`.

### 1.2 Análise do Código de Inicialização

#### Arquivo start.s

```asm
.section .text
.global _start

_start:
    # Inicializa o Stack Pointer (SP) definido no linker script
    la sp, _stack_start

    # Salta para a função main em C
    call main

    # Loop infinito caso o main retorne
_exit:
    j _exit
```

Este arquivo representa a forma mais minimalista de startup. A diretiva `.global _start` exporta o símbolo para que o linker possa localizá-lo como ponto de entrada do programa. A diretiva `.section .text` coloca o código na seção de texto (memória de programa).

#### Arquivo crt0.s

```asm
.section .globl _start

.equ HALT_MMIO, 0x10000008

_start:
    # Inicializa o Stack Pointer (sp) para o final da RAM
    lui sp, %hi(_stack_start)
    addi sp, sp, %lo(_stack_start)

    call main

    # Escreve no registrador de controle parahaltar a simulação
    li a0, 1
    li t0, HALT_MMIO
    sw a0, 0(t0)
```

Este arquivo implementa a mesma função básica, porém com duas diferenças importantes:

1. **Forma de carregar o endereço da pilha**: Em vez de usar `la` (pseudoinstrução que pode ser transformada em duas instruções), utiliza explicitamente `lui` (Load Upper Immediate) seguido de `addi` para carregar os 20 bits superiores e inferiores do endereço. Esta forma é mais robusta e portátil.

2. **Halt da simulação**: Após o retorno de `main`, escreve o valor `1` no endereço MMIO `0x10000008`, que é conectado ao hardware de simulação para encerrar a execução controlada.

### 1.3 Inicialização do Stack Pointer (sp) e Global Pointer (gp)

A inicialização do registrador `sp` (Stack Pointer) é **obrigatória** antes de executar qualquer código em C. O motivo é profundamente enraizado na ABI (Application Binary Interface) do RISC-V e no funcionamento do modelo de chamadas de função.

#### Por que o Stack Pointer é Essencial

Quando o compilador gera código para uma função em C, ele assume que existe uma área de memória acessível para as seguintes operações:

1. **Armazenamento de variáveis locais**: Funções C podem declarar variáveis locais como `int x;` que são alocadas na pilha. O compilador gera instruções para decrementar o `sp` e armazenar valores nestas localizações.

2. **Preservação de registradores**: A ABI RISC-V define que os registradores `s0-s11` (saved registers) devem ter seus valores preservados entre chamadas de função. Quando uma função chama outra, ela deve salvar esses valores na pilha antes de modificá-los.

3. **Passagem de argumentos**: A ABI RISC-V passa os primeiros 8 argumentos de função nos registradores `a0-a7`. Se uma função precisa salvar esses valores (por exemplo, porque chamará outra função que também usa `a0`), ela devepushá-los na pilha.

4. **Endereço de retorno**: A instrução `call` em RISC-V armazena o endereço de retorno no registrador `ra` (Return Address). Se uma função chama outra, ela deve salvar o valor anterior de `ra` na pilha para restaurar após o retorno.

Sem um `sp` válido apontando para uma região de memória RW (leitura-escrita), qualquer uma dessas operações causará uma falha de página (page fault) ou comportamento indefinido. O processador não inicializa automaticamente a pilha porque a localização da RAM física é desconhecida em tempo de projeto — ela depende do dispositivo (FPGA) e da configuração de memória definida no linker script.

No código, a inicialização é feita carregando o símbolo `_stack_start`, que é definido pelo linker script e aponta para o topo da região de RAM alocada para a pilha:

```asm
lui sp, %hi(_stack_start)
addi sp, sp, %lo(_stack_start)
```

A pilha grows para baixo (endereços decrescentes), então inicializá-la no maior endereço disponível garante espaço máximo para crescimento sem colidir com o código ou dados.

#### O Global Pointer (gp)

Embora não seja explicitamente inicializado nos arquivos analisados (o compilador frequentemente gera código que usa `gp` implicitamente via `gp` relocations), o registrador `gp` é utilizado pelo compilador para acessos eficientes a variáveis globais. Ele aponta para o meio da seção `.bss` ou `.data`, permitindo que acessos a dados globais usem o offset negativo a partir de `gp` em vez de cálculos de endereço absolutos com `pc`.

Para projetos maiores ou quando se usa `-fPIC` (Position Independent Code), o linker script tipicamente define `_global_pointer$` e o código de startup deve inicializar `gp` com:

```asm
la gp, _global_pointer$
```

### 1.4 Limpeza da Seção .bss

Em programas C, variáveis globais declaradas sem inicialização explícita (como `int count;`) devem ser automaticamente inicializadas com zero pelo runtime. O compilador coloca essas variáveis na seção `.bss` (Block Started by Symbol), que é uma região de memória não inicializada.

Antes de executar qualquer código que possa acessar essas variáveis, o startup deve zerar toda a região `.bss`. Isso é feito através de um loop que escreve zero em toda a faixa de memória entre `__bss_start` e `__bss_end`:

```asm
la a0, __bss_start
la a1, __bss_end
bge a0, a1, .Lend
.Lloop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, .Lloop
.Lend:
```

Nos arquivos analisados (`start.s` e `crt0.s`), esta etapa está ausente porque são exemplos minimalistas. Em um ambiente de produção completo, o crt0.s deveria incluir esta limpeza.

### 1.5Transição para main()

Após inicializar `sp` (e opcionalmente `gp` e limpar `.bss`), o startup executa `call main`. A instrução `call` é uma pseudoinstrução que expande para:

```asm
auipc ra, 0      # ra = PC + 0 (endereço da próxima instrução)
addi ra, ra, offset  # ajusta para o endereço de main
j main           # jump para main
```

O registrador `ra` (Return Address) é automaticamente configurado para apontar para a instrução após o `call`. Quando `main` retornar (via `ret`, que expande para `jr ra`), a execução continuará no código subsequente — o loop infinito em `start.s` ou o halt em `crt0.s`.

---

## 2. O Bootloader em C

### 2.1 Contexto e Propósito

Uma vez que o código C pode executar corretamente (ambiente preparado pelo startup), o bootloader assume o controle. No contexto deste projeto, o bootloader é um programa em C que reside em memória ROM/Flashon-chip (endereço `0x00000000` após o startup) e possui duas funções principais:

1. Estabelecer comunicação com um host externo via UART
2. Receber um binário da aplicação do usuário, gravá-lo na RAM, e saltar para sua execução

Este modelo permite que o hardware (FPGA) seja reprogramado com novas aplicações sem modificar o hardware bistream.

### 2.2 Análise do Código do Bootloader

#### Configuração de Periféricos UART

O bootloader utiliza registradores mapeados em memória (MMIO - Memory-Mapped I/O) para comunicar com o hardware UART:

```c
#define UART_BASE       0x10000000
#define UART_DATA_REG   (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_CTRL_REG   (*(volatile uint32_t *)(UART_BASE + 0x04))
```

O endereço `0x10000000` é uma região de MMIO típica em sistemas embarcados RISC-V, onde os periféricos são acessados através de leituras/escritas a endereços específicos.

- `UART_DATA_REG` (offset `0x00`): Registrador de dados - leitura retorna o próximo byte do FIFO de recebimento; escrita envia um byte para transmissão.
- `UART_CTRL_REG` (offset `0x04`): Registrador de controle/status - o bit 1 indica se há dados disponíveis no FIFO de recebimento (`STATUS_RX_AVAIL`), e o bit 0 é usado para pop do FIFO (`CMD_POP_FIFO`).

A declaração `volatile` é essencial para periféricos MMIO porque impede o compilador de otimizar away as leituras/escritas ou reordenar operações.

#### Reception da Magic Word "CAFEBABE"

Antes de aceitar qualquer dado, o bootloader exige uma sequência mágica de 4 bytes: `0xCA`, `0xFE`, `0xBA`, `0xBE`. Esta funciona como um handshake de protocolo:

```c
while (1) {
    if (uart_get_byte() == 0xCA) {
        if (uart_get_byte() == 0xFE) {
            if (uart_get_byte() == 0xBA) {
                if (uart_get_byte() == 0xBE) {
                    break; // Magic word recebida
                }
            }
        }
    }
}
```

O motivo desta verificação é duplo:

1. **Sincronização**: Garante que o host e o bootloader estão sincronizados no início da transmissão.
2. **Validação básica**: Minimiza a chance de executar código espúrio que possa estar presente no buffer da UART.

Após receber a magic word, o bootloader envia o caractere `!` como ACK (acknowledge) para confirmar ao host que está pronto para receber dados.

#### Receiving do Tamanho do Programa

O bootloader espera 4 bytes que representam o tamanho do programa em bytes, transmitidos em little-endian (menor byte primeiro):

```c
uint32_t program_size = uart_get_uint32();
```

Esta função lê 4 bytes e os combina em um `uint32_t` através de shifts e OR:

```c
val |= ((uint32_t)uart_get_byte()) << 0;   // byte 0 (LSB)
val |= ((uint32_t)uart_get_byte()) << 8;   // byte 1
val |= ((uint32_t)uart_get_byte()) << 16;  // byte 2
val |= ((uint32_t)uart_get_byte()) << 24;  // byte 3 (MSB)
```

#### Gravação do Binário na RAM

Com o tamanho conhecido, o bootloader simplesmente lê cada byte da UART e o escreve na memória RAM a partir do endereço `USER_APP_BASE` (`0x80000800`):

```c
volatile uint8_t *ram_ptr = (volatile uint8_t *)USER_APP_BASE;
for (uint32_t i = 0; i < program_size; i++) {
    *ram_ptr = uart_get_byte();
    ram_ptr++;
}
```

A palavra-chave `volatile` é usada para garantir que cada escrita seja realmente executada — sem isso, o compilador poderia otimizar o loop e fazer uma única escrita de 32 bits ou mesmo remover o loop completamente.

O offset de 2KB (`0x800`) foi chosen para alinhar a aplicação do usuário a uma fronteira de setor/região de memória, separando-a claramente da área do bootloader.

#### Salto para a Aplicação do Usuário

Apósgravar todos os bytes, o bootloader transfere o controle para a aplicação usando um ponteiro de função:

```c
void (*user_app)() = (void (*)())USER_APP_BASE;
user_app();
```

Esta técnica funciona porque:

1. O binário da aplicação foi compilado/linkado para executar a partir do endereço `0x80000800`, então seus endereços absolutos são válidos.
2. A aplicação tem sua própria função `main()`, que será chamada implicitamente quando o ponteiro for invocado.
3. A pilha não precisa ser reconfigurada — a aplicação pode usar a mesma pilha existente (假定 que não há conflito de uso).

Se a aplicação retornar (situação anormal), o bootloader entra em loop infinito.

---

## 3. Resumo do Fluxo de Boot

O processo completo pode ser visualizado como uma cascata de estágios:

1. **Reset Hardware**: O processador inicia no endereço de boot (tipicamente `0x00000000`).

2. **Startup Assembly** (crt0.s/start.s):
   - Inicializa `sp` para o topo da RAM
   - Opcionalmente inicializa `gp` e limpa `.bss`
   - Chama `main()`

3. **Bootloader C** (boot.c):
   - Espera magic word via UART
   - Recebe tamanho do programa
   - Grava binário na RAM a partir de `0x80000800`
   - Salta para o endereço da aplicação

4. **Aplicação do Usuário**:
   - Executa a partir de `main()`
   - Pode usar a pilha pré-configurada e acessar periféricos normalmente

Esta arquitetura de boot em dois estágios — startup mínimo em Assembly seguido de bootloader completo em C — é um padrão widely adotado em sistemas embarcados porque equilibra a necessidade de código de inicialização robusto com a flexibilidade de um ambiente de programação de alto nível para a lógica de boot.