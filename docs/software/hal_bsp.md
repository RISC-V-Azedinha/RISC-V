# Documentação Técnica: HAL e BSP

> **Resumo:** Este documento descreve a arquitetura da Camada de Abstração de Hardware (HAL) e do Pacote de Suporte à Placa (BSP) para a plataforma RISC-V baseada em FPGA. O foco está na ponte entre o software em linguagem C e os registradores físicos do hardware, demonstrando como as abstrações da linguagem mapeiam o comportamento do barramento.

---

## 1. O Mapa de Memória no Software (`memory_map.h`)

### 1.1 Memória e Dispositivos: Uma Visão Unificada

Em sistemas embarcados baseados em processadores com Memory-Mapped I/O (MMIO), não existe distinção fundamental entre acessar a memória RAM e interagir com periféricos de hardware. Ambos utilizam o mesmo barramento de endereços — o processador emite um endereço e o sistema de interconexão (bus interconnect) decide se a transação deve ser roteada para a memória RAM ou para um dos dispositivos periféricos.

Do ponto de vista do compilador C, isso significa que um acesso a um registrador de hardware é, sintaticamente, idêntico a um acesso a uma variável na memória. A diferença reside no **endereço físico** que está sendo utilizado.

O arquivo `memory_map.h` (localizado em `fpga/sw/platform/bsp/memory_map.h`) define as macros que tornam essa abstração possível:

```c
#define MMIO32(addr)            (*(volatile uint32_t *)(addr))
#define MMIO8(addr)             (*(volatile uint8_t *)(addr))
```

Para compreender o que ocorre nestas linhas, vamos decompor a expressão `MMIO32(0x10000000)`:

1. `(0x10000000)` — O compilador trata este valor como um número inteiro de 32 bits representando um endereço.
2. `(uint32_t *)(addr)` — Este inteiro é convertido em um **ponteiro** para um `uint32_t`. O compilador agora sabe que, ao desreferenciar este ponteiro, deve gerar uma instrução de leitura ou escrita de 32 bits na memória.
3. `*(...)` — O operador de desreferência acessa o conteúdo no endereço especificado.
4. `volatile` — O qualificador que previne otimizações indesejadas (explicado na Seção 1.3).

### 1.2 Do RTL para o Código C: Mapeamento de Endereços

No nível de descrição de hardware (RTL/VHDL), o projetista define os **endereços base** (base addresses) de cada periférico ao instanciar os módulos no nível superior do sistema (`soc_top.vhd`). Esses endereços são então codificados no hardware da FPGA através do decodificador de endereços do barramento.

No software, esses mesmos endereços são definidos como macros numéricas:

```c
#define UART_BASE_ADDR      0x10000000
#define CLINT_BASE_ADDR     0x50000000
#define PLIC_BASE_ADDR      0x60000000
```

A cada registrador dentro de um periférico é atribuído um **offset** relativo à base. Por exemplo, no controlador UART:

```c
#define UART_REG_DATA_OFFSET    0x00
#define UART_REG_CTRL_OFFSET    0x04
#define UART_DATA_REG_ADDR      (UART_BASE_ADDR + UART_REG_DATA_OFFSET)
#define UART_CTRL_REG_ADDR      (UART_BASE_ADDR + UART_REG_CTRL_OFFSET)
```

Esta organização segue o mapa de registradores definido no bloco VHDL do hardware. O registrador de dados está no offset `0x00` (ou seja, no endereço base) e o registrador de controle está no offset `0x04` (4 bytes adiante, em um barramento de 32 bits).

**Por que isso importa?** Quando o software executa:

```c
MMIO32(UART_DATA_REG_ADDR) = c;
```

O compilador gera uma instrução de escrita de 32 bits no barramento com o endereço `0x10000000`. O hardware da FPGA, ao ver este endereço no barramento, ativa o módulo UART e reconhece que a escrita deve ser armazenada no registrador de dados do transmissor. Internamente, o hardware gera os sinais necessários para transformar esse dado em pulsos na linha serial (TX).

### 1.3 A Obrigatoriedade do `volatile`

Considere o seguinte trecho da HAL UART (`hal_uart.c`):

```c
void hal_uart_putc(char c) {
    while (MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_TX_BUSY);
    MMIO32(UART_DATA_REG_ADDR) = c;
}
```

O programador espera que o loop `while` monitore continuamente o registrador de status do hardware, esperando que o bit `TX_BUSY` vá para 0 (indicando que o transmissor está livre para receber um novo caractere).

**O problema sem `volatile`:** O compilador C, durante sua fase de otimização, pode analisar que o registrador de status é uma variável local que nunca é modificada pelo código dentro da função (do ponto de vista do compilador). Ele pode decidir:

1. Ler o registrador de status **uma única vez** antes do loop.
2. Armazenar esse valor em um registrador da CPU.
3. Executar o loop de forma infinita usando o valor cacheado, pois ele "sabe" que o valor não muda.

Este comportamento é perfeitamente válido para variáveis normais em memória que não são modificadas por agentes externos. Porém, para registradores de hardware, **o valor muda independentemente da execução do software** — o hardware altera o bit de status conforme o estado do transmissor UART.

**A solução com `volatile`:**

```c
#define MMIO32(addr)            (*(volatile uint32_t *)(addr))
```

O qualificador `volatile` instrui o compilador a:
- Não remover na otimização as leituras subsequentes.
- Sempre gerar uma instrução de leitura no barramento para cada acesso.
- Não manter o valor em um registrador CPU entre acessos.

Dessa forma, cada iteração do `while` gera uma transação real no barramento, permitindo que o software "veja" as mudanças de estado do hardware.

---

## 2. Camada de Abstração de Hardware (HAL)

### 2.1 Filosofia de Design: API Uniforme

A HAL desta plataforma adota um padrão de projeto consistente para todos os drivers, facilitando o aprendizado e a portabilidade. Cada periférico expõe uma interface com funções de **inicialização**, **configuração** e **operação**.

Analisando os drivers fornecidos, observamos uma estrutura homogênea:

| Módulo | Inicialização | Operação Principal | Característica |
|--------|---------------|---------------------|----------------|
| UART   | `hal_uart_init()` | `hal_uart_putc()`, `hal_uart_getc()` | Polling-based |
| Timer  | Configuração inline via `hal_timer_reset()` | `hal_timer_get_cycles()` | Acesso direto a registradores |
| DMA    | `hal_dma_is_busy()` | `hal_dma_memcpy()` | Transferência autônoma |
| VGA    | `hal_vga_init()` | `hal_vga_plot()`, `hal_vga_rect()` | Memória de video mapeada |

A UART utiliza **polling** (espera ativa): o software verifica repetidamente o bit de status até que o hardware esteja pronto. O DMA, por outro lado, opera de forma **assíncrona**: o software configura os parâmetros da transferência e o hardware a executa autonomamente, permitindo que a CPU realize outras tarefas.

### 2.2 Structs que Espelham Registradores VHDL

Uma das técnicas mais poderosas em programação de sistemas embarcados é utilizar estruturas C (`structs`) para representar o layout de registradores de hardware. Considere a definição do controlador DMA (`hal_dma.h`):

```c
typedef struct {
    volatile uint32_t SRC;  // 0x00: Endereço de Origem
    volatile uint32_t DST;  // 0x04: Endereço de Destino
    volatile uint32_t CNT;  // 0x08: Quantidade de palavras
    volatile uint32_t CTRL; // 0x0C: Controle e Status
} dma_reg_t;
```

Esta `struct` replica exatamente o layout definido no módulo VHDL `dma_controller`. Cada campo corresponde a um registrador de 32 bits, mapeado em endereços consecutivos (0x00, 0x04, 0x08, 0x0C).

**Por que `volatile` em cada campo?** Cada campo da estrutura deve ser volatile porque:
- O hardware pode modificar campos de status (leitura) independentemente do software.
- O hardware pode depender da temporização exata das escritas (escrita).

**Acesso via struct:** Quando o software executa:

```c
DMA->SRC = src;
DMA->DST = dst;
DMA->CNT = size_words;
DMA->CTRL = cmd;
```

O compilador gera:
1. Escrita de 32 bits no endereço `DMA_BASE_ADDR + 0x00` (SRC).
2. Escrita de 32 bits no endereço `DMA_BASE_ADDR + 0x04` (DST).
3. Escrita de 32 bits no endereço `DMA_BASE_ADDR + 0x08` (CNT).
4. Escrita de 32 bits no endereço `DMA_BASE_ADDR + 0x0C` (CTRL).

Essa correspondência direta entre a abstração de software e o hardware físico é o coração da programação de sistemas embarcados.

### 2.3 Operações Bit a Bit: Acessando Flags sem Corromper Registradores

Em registradores de controle, frequentemente diversos flags e campos coexistem no mesmo registrador de 32 bits. Para modificar apenas um bit específico sem afetar os demais, utiliza-se **máscaras de bits** (bitmasking) e **deslocamento de bits** (bit shifting).

**Exemplo 1: Verificar flags de status (UART)**

```c
#define UART_STATUS_TX_BUSY     (1 << 0)  // Bit 0
#define UART_STATUS_RX_VALID    (1 << 1)  // Bit 1
```

No registrador de status da UART, o bit 0 indica transmissor ocupado e o bit 1 indica receptor com dado válido. Para verificar se há dados para ler:

```c
if (MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) {
    // Há dados disponíveis
}
```

A operação `&` (AND bit a bit) com a máscara `0x02` (em binário: `00000000000000000000000000000010`) retorna 0 se o bit 1 for 0, ou um valor não-zero se o bit 1 for 1.

**Exemplo 2: Modificar bits individuais (PLIC)**

Para habilitar uma fonte de interrupção específica sem afetar as demais, o driver PLIC utiliza a técnica de Read-Modify-Write (`hal_plic.c`). A implementação a seguir suporta `source_id` superior a 31 através de indexação em array de registradores de enable:

```c
void hal_plic_enable(uint32_t source_id) {
    if (source_id >= PLIC_MAX_SOURCES) return;
    uint32_t reg_index = source_id / 32;       // Índice do registrador (0, 1, ...)
    uint32_t bit_index = source_id % 32;     // Bit dentro do registrador
    uint32_t current_enables = PLIC_ENABLE[reg_index];  // Lê registrador atual
    current_enables |= (1 << bit_index);           // Modifica apenas o bit específico
    PLIC_ENABLE[reg_index] = current_enables;      // Escreve de volta
}
```

O operador `|=` (OR composto)liga o bit correspondente à fonte de interrupção, preservando todos os outros bits do registrador de enable.

**Exemplo 3: Campos de múltiplos bits (Timer RISC-V)**

O timer do RISC-V (CLINT) utiliza registradores de 64 bits compostos por partes alta e baixa. O acesso a valores de 64 bits em sistemas de 32 bits requer atenção especial:

```c
static inline uint64_t hal_timer_get_cycles(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = CLINT_MTIME_HI;   // Lê parte alta
        lo  = CLINT_MTIME_LO;   // Lê parte baixa
        hi2 = CLINT_MTIME_HI;   // Lê parte alta novamente
    } while (hi != hi2);        // Verifica se mudou durante a leitura
    
    return ((uint64_t)hi << 32) | lo;  // Combina partes
}
```

Este código implementa uma leitura atômica de 64 bits através do método de "leitura dupla com verificação" (double-read with verification). Se a parte alta mudar entre a primeira leitura da parte alta e a leitura da parte baixa, significa que houve overflow da parte baixa para a alta, invalidando a leitura — o código repete até obter uma leitura consistente.

---

## 3. Despacho de Interrupções e Operações Base

### 3.1 O Fluxo de Interrupções: Do Hardware ao Software

O sistema de interrupções da plataforma RISC-V segue uma arquitetura em camadas. Para que uma rotina de tratamento escrita em C seja executada quando um periférico dispara uma interrupção, é necessário um mecanismo que conecte o evento de hardware ao código de software.

**Camada 1: O Periférico (UART, DMA, NPU)**
O periférico gera um sinal de interrupção quando uma condição ocorre (ex: dado recebido na UART).

**Camada 2: O Controlador de Interrupções (PLIC)**
O PLIC (Platform-Level Interrupt Controller) recebe sinais de múltiplas fontes, prioriza-as e notifica o processador RISC-V sobre a interrupção externa de maior prioridade pendente.

**Camada 3: O Processador RISC-V**
A CPU, ao receber a interrupção externa, consulta o registrador `mcause` para determinar a causa e o registrador `mtvec` para localizar o handler.

### 3.2 O Dispatcher de Interrupções em C

O arquivo `irq/irq_dispatch.c` implementa o **tratador central de interrupções** (central trap handler). A função `irq_dispatch_handler` é registrada no vetor de interrupções da CPU (via registrador `mtvec`):

```c
void __attribute__((interrupt("machine"))) irq_dispatch_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    if (mcause == 0x8000000B) {  // Interrupção Externa (Código 11)
        uint32_t source = hal_plic_claim();  // Pergunta ao PLIC quem chamou
        
        if (source > 0 && source < PLIC_MAX_SOURCES) {
            if (g_isr_table[source] != NULL) {
                g_isr_table[source]();  // Executa callback registrado
            }
        }
        
        hal_plic_complete(source);  // Finaliza tratamento
    }
}
```

O atributo `interrupt("machine")` informa ao compilador que esta função deve:
- Salvar todos os registradores que podem ser modificados.
- Configurar o ambiente para retornar via `mret` ao final.
- Ser chamada diretamente pelo hardware quando uma interrupção ocorre.

**O fluxo completo:**

1. **Registro:** A aplicação registra um handler via `hal_irq_register(source_id, my_handler)`, que armazena o ponteiro de função na tabela `g_isr_table`.

2. **Ocorrência:** O hardware (ex: UART) gera uma interrupção.

3. **Escalação:** O PLIC recebe o sinal, verifica prioridades e, se apropriado, interrompe a CPU.

4. **Despacho:** A CPU executa `irq_dispatch_handler` (endereço definido em `mtvec`).

5. **Identificação:** O handler lê o `mcause` (identificando como interrupção externa), então pergunta ao PLIC qual fonte específica solicitou a interrupção (`hal_plic_claim`).

6. **Execução:** O dispatcher indexa a tabela de handlers e executa a função registrada.

7. **Finalização:** O handler avisa ao PLIC que o tratamento foi concluído (`hal_plic_complete`).

### 3.3 Suporte Nativo: Biblioteca math_ops

O RISC-V padrão (RV32I) não inclui instruções de hardware para multiplicação ou divisão de inteiros — essas operações são implementadas por **software** quando o compilador as encontra no código-fonte.

O arquivo `math_ops.c` fornece implementações de bibliotecas que são **vinculadas automaticamente** pelo compilador quando este encontra os operadores `*`, `/` ou `%`:

| Função | Operador C | Propósito |
|--------|------------|-----------|
| `__mulsi3` | `*` (32-bit signed) | Multiplicação via software |
| `__udivsi3` | `/` (unsigned) | Divisão unsigned via software |
| `__umodsi3` | `%` (unsigned) | Resto unsigned |
| `__divsi3` | `/` (signed) | Divisão signed |
| `__modsi3` | `%` (signed) | Resto signed |
| `__muldi3` | `*` (64-bit) | Multiplicação 64-bit |

O algoritmo de multiplicação utilizado é o método de **soma e deslocamento** (shift-and-add), que simula a multiplicação manual:

```c
int32_t __mulsi3(int32_t a, int32_t b) {
    uint32_t ua = (uint32_t)a;  // Converte para unsigned antes de shifts
    uint32_t ub = (uint32_t)b;
    uint32_t res = 0;
    while (ub != 0) {
        if (ub & 1) res += ua;   // Se bit atual de b é 1, soma
        ua <<= 1;               // Dobra o multiplicando
        ub >>= 1;                // Desloca divisor
    }
    return (int32_t)res;
}
```

Esta biblioteca é fundamental para o BSP porque permite que código C padrão (que utiliza operadores aritméticos) funcione no hardware sem precisar de unidade de multiplicação/divisão hardware.

---

## Referência Rápida de API

### Acesso a Hardware

```c
// Leitura de 32 bits
uint32_t valor = MMIO32(ENDEREÇO);

// Escrita de 32 bits
MMIO32(ENDEREÇO) = valor;

// Leitura de 8 bits
uint8_t byte = MMIO8(ENDEREÇO);
```

### UART

```c
hal_uart_init();
hal_uart_putc('A');
hal_uart_puts("Hello FPGA");
if (hal_uart_kbhit()) { char c = hal_uart_getc(); }
```

### Timer

```c
hal_timer_reset();
uint64_t ciclos = hal_timer_get_cycles();
hal_timer_set_irq_delta(1000000);  // Interrupção em 1 segundo (a 100MHz)
```

### Interrupções

```c
hal_irq_init();
hal_irq_register(PLIC_SOURCE_UART, meu_handler_uart);
hal_irq_global_enable();
```

---
