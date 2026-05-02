# Organização da Memória Executável: Scripts do Linker

Este documento explica o papel do Linker no fluxo de compilação de software embarcado e como os scripts de linkagem distribuem o código compilado nos endereços físicos de memória do SoC RISC-V. A compreensão deste processo é fundamental para entender como o hardware e o software interagem durante a execução.

---

## 1. O Papel do Linker no Fluxo de Compilação

### 1.1 Visão Geral da Cadeia de Compilação

Em sistemas embarcados, a transformação do código-fonte em um binário executável passa por múltiplas etapas sequenciais:

1. **Pré-processamento**: Expansão de macros e includes (`.c` → `.i`)
2. **Compilação**: Tradução do código C para linguagem Assembly (`.i` → `.s`)
3. **Assembler**: Montagem do Assembly em código de máquina objeto (`.s` → `.o`)
4. **Linkedição**: Junção de múltiplos arquivos objeto em um único executável (`.o` → ELF)
5. **Flashing/Gravação**: Transferência do binário para a memória do dispositivo

O **Linker** é o programa responsável por resolver referências simbólicas entre arquivos objeto, alocar símbolos em endereços de memória específicos e gerar o formato final executável. É ele quem "costura" todas as peças do programa em um todo coerente.

### 1.2 Seções Lógicas do Programa

Durante a compilação, o compilador organiza o conteúdo do programa em **seções lógicas** (sections), cada uma com uma finalidade específica:

| Seção | Conteúdo | Propriedades |
|-------|----------|---------------|
| `.text` | Código máquina das funções | Somente leitura, executável |
| `.rodata` | Constantes (strings, tabelas de lookup) | Somente leitura |
| `.data` | Variáveis globais inicializadas | Leitura e escrita |
| `.bss` | Variáveis globais não inicializadas | Leitura e escrita |
| `.stack` | Área da pilha (definida pelo linker script) | Leitura e escrita |

A razão para separar o programa em seções reside na natureza diferente de cada tipo de dado. O linker usa essas informações para mapear cada seção para a região apropriada de memória: código e constantes vão tipicamente para áreas de somente leitura, enquanto variáveis e pilha precisam de áreas de leitura-escrita. Vale notar que, na prática, o programa completo pode ser carregado em RAM pelo bootloader — a divisão em seções serve para o allocator do linker saber como distribuir cada parte.

---

## 2. Organização e Mapeamento de Memória

### 2.1 O Linker Script

O **Linker Script** é um arquivo de configuração (extensão `.ld`) que instrui o linker sobre como distribuir as seções lógicas nos endereços físicos de memória do hardware. Ele define:

- A topologia de memória disponível (regiões ROM, RAM, MMIO)
- A posição de cada seção em cada região
- Símbolos especiais que serão usados pelo código de startup

O formato é uma linguagem específica do linker GNU (ld), contendo diretivas como `MEMORY` para descrever a memória física e `SECTIONS` para mapear as seções lógicas.

### 2.2 Análise do boot.ld (Bootloader)

O arquivo `boot.ld` é usado para compilar o bootloader — o programa que reside permanentemente em memória ROM e executa após o reset:

```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  rom (rx) : ORIGIN = 0x00000000, LENGTH = 4K
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 256K 
}

SECTIONS {
    .text : { 
        *(.text*)      
        *(.rodata*)   
    } > rom

    .data : { *(.data*) } > ram
    .bss  : { *(.bss*)  } > ram
    
    _stack_start = ORIGIN(ram) + LENGTH(ram);
}
```

#### Definição de Memória

| Região | Endereço Base | Tamanho | Propriedades |
|--------|---------------|---------|---------------|
| `rom` | `0x00000000` | 4 KB | Somente leitura e executável (rx) |
| `ram` | `0x80000000` | 256 KB | Leitura, escrita e executável (rwx) |

A escolha de `0x00000000` para a ROM segue o padrão RISC-V, onde o processador começa a executar a partir deste endereço após o reset. O endereço `0x80000000` para a RAM é a região designada pela especificação RISC-V para memória acessível via instruções regulares (endereços abaixo de `0x80000000` têm comportamento especial para internamente mapeado e CSR).

#### Mapeamento de Seções

O bootloader coloca `.text` e `.rodata` em ROM porque:

1. O código do bootloader não precisa ser modificado após a fabricação
2. Há apenas 4KB de ROM disponível, suficiente para o bootloader
3. O bootloader deve executar imediatamente após reset, sem precisar copiar código da RAM

As seções `.data` e `.bss` vão para RAM porque variáveis precisam de memória de leitura-escrita:

#### Símbolo _stack_start

O linker define `_stack_start` como o endereço final da RAM:

```ld
_stack_start = ORIGIN(ram) + LENGTH(ram);  // 0x80000000 + 256K = 0x80040000
```

Este símbolo é consumido pelo código de startup (crt0.s/start.s) para inicializar o registrador `sp` (Stack Pointer). A pilha cresce para baixo, então começar no topo da RAM maximiza o espaço disponível.

### 2.3 Análise do link.ld (Aplicação do Usuário)

O arquivo `link.ld` é usado para compilar a aplicação que será carregada dinamicamente pelo bootloader:

```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  /* Deixa os primeiros 2KB livres para dados do Bootloader */
  ram (rwx) : ORIGIN = 0x80000800, LENGTH = 256K
}

SECTIONS
{
    .text : { *(.text*) } > ram

    .rodata : { *(.rodata*) } > ram

    .data : { *(.data*) } > ram

    .bss : {
        *(.bss*)
        *(COMMON)
    } > ram

    _stack_start = ORIGIN(ram) + LENGTH(ram);  // 0x80000800 + 256K = 0x80040800
}
```

#### Definição de Memória

| Parâmetro | Valor |
|-----------|-------|
| Endereço Base | `0x80000800` |
| Tamanho | 256 KB |

A diferença crucial em relação ao bootloader é que a aplicação não tem acesso a ROM própria. Ela é carregada na RAM pelo bootloader e executada a partir dali.

#### O Offset de 2KB (0x800)

O comentário no script explica: "Deixa os primeiros 2KB livres para dados do Bootloader". O bootloader, ao receber um novo binário pela UART, precisa de um buffer temporário para armazenar os bytes recebidos antes de gravá-los permanentemente no endereço final. Este buffer é tipicamente alocado no início da RAM do usuário (região `0x80000000` a `0x80000800`), permitindo que o bootloader use esta memória durante o processo de transferência.

#### Mapeamento de Seções

Todas as seções (.text, .rodata, .data, .bss) são colocadas em RAM porque:

1. Não há ROM separada para a aplicação
2. O bootloader pode livremente gravá-las na memória volátil
3. Todas as seções necessitam de acesso de escrita em tempo de execução

#### Símbolo _stack_start

Aqui o topo da pilha está em `0x80040800` (256KB após `0x80000800`), diferente do bootloader (`0x80040000`). Isso ocorre porque a aplicação começa 2KB acima na memória.

### 2.4 Símbolos Definidos e Consumidos pelo Startup

O linker script gera símbolos que o código assembly utiliza como referências fixas. O caso mais evidente é `_stack_start`:

```asm
# Em crt0.s / start.s
lui sp, %hi(_stack_start)
addi sp, sp, %lo(_stack_start)
```

O linker substitui `_stack_start` pelo endereço calculado (`0x80040000` para bootloader, `0x80040800` para aplicação), e o código de startup usa esse valor para inicializar o Stack Pointer.

### 2.5 Justificativa das Escolhas de Endereçamento

#### Por que ROM em 0x00000000?

A especificação RISC-V define que, após um reset, o processador começa a executar a partir do endereço `0x00000000`. Este é um requisito arquitetural, não uma convenção. Portanto, qualquer código que deva executar no boot (como o bootloader) precisa estar mapeado nesta região de memória.

#### Por que RAM em 0x80000000?

O espaço de endereço RISC-V tem uma separação clara:

- Endereços `0x00000000` a `0x7FFFFFFF` são tratados como memória não alinhada (misaligned memory access) e podem causar traps em implementações que não suportam acessos misaligned
- Endereços `0x80000000` e acima são a região "canônica" para memória RAM

A escolha de `0x80000000` para a RAM evita problemas com acessos misaligned e segue a convenção estabelecida em implementações RISC-V como o Rocket Chip e o BOOM.

#### Por que o salto da aplicação em 0x80000800?

O bootloader termina sua execução gravando a aplicação em `0x80000800` e saltando para este endereço. Este offset de 2KB serve para:

1. Deixar espaço para buffer de recepção no bootloader (conforme explicitado no comentário)
2. Garantir alinhamento razoável (2KB = 2048 bytes é uma fronteira de setor comum)
3. Evitar sobreposição acidental com dados do bootloader

---

## 3. Resumo Comparativo

| Aspecto | boot.ld (Bootloader) | link.ld (Aplicação) |
|---------|----------------------|---------------------|
| Regiões de memória | ROM (4KB) + RAM (256KB) | Apenas RAM (256KB) |
| Endereço de execução | ROM: 0x00000000 | RAM: 0x80000800 |
| .text + .rodata | ROM | RAM |
| .data + .bss | RAM | RAM |
| Topo da pilha (_stack_start) | 0x80040000 | 0x80040800 |

Esta arquitetura em dois estágios — bootloader em ROM com aplicação carregável em RAM — é uma prática comum em sistemas embarcados que precisam de atualização de software sem modificação de hardware.