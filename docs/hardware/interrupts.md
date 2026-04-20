# Subsistema de Interrupções do SoC RISC-V

O subsistema de interrupções é um dos componentes mais críticos para a operação de um processador RISC-V. Ele permite que eventos assíncronos — originados de periféricos externos ou mecanismos internos — interrompam o fluxo normal de execução do programa, forçando o núcleo a tratar esses eventos de forma determinística. Este documento detalha a arquitetura de interrupções do SoC, desde os conceitos fundamentais até a integração entre hardware e software.

## 1. Fundamentação: Exceções e Interrupções no RISC-V

Na especificação RISC-V, o termo **"trap"** (armadilha) é usado como denominação genérica para representar qualquer evento que altere o fluxo normal de execução. O trap engloba duas categorias principais:

* **Exceção:** Evento síncrono causado pela própria instrução que está sendo executada (ex: divisão por zero, acesso à memória não alinhado, instrução ilegal).
* **Interrupção:** Evento assíncrono causado por fontes externas ao processador (ex: timer, periféricos), que não tem relação direta com a instrução em execução.

### 1.1. Tipos de Interrupções no Machine Mode

O RISC-V define três categorias principais de interrupções no modo de máquina (M-Mode), cada uma com uma finalidade específica:

| Tipo | Código MCAUSE | Descrição | Fonte |
| --- | --- | --- | --- |
| **Software** | 3 (0x3) | Interrupção de software | CLINT (MSIP) |
| **Timer** | 7 (0x7) | Interrupção de temporizador | CLINT (MTIP) |
| **External** | 11 (0xB) | Interrupção externa | PLIC (periféricos) |

Cada tipo de interrupção possui um bit dedicado no registrador **MIP** (*Machine Interrupt Pending*) e um bit correspondente em **MIE** (*Machine Interrupt Enable*) para habilitação individual.

### 1.2. Mecânica de Desvio de Fluxo (Trap Entry)

Quando o hardware aceita uma interrupção, ele executa automaticamente uma sequência de ações determinísticas, sem a intervenção do software:

1.  **Salvamento do PC de retorno:** O endereço da instrução que seria executada a seguir é salvo no registrador **MEPC** (*Machine Exception Program Counter*). Para interrupções, este é o endereço da próxima instrução sequencial.
2.  **Registro da causa:** O registrador **MCAUSE** (*Machine Cause*) é atualizado com um valor codificado que identifica o tipo de evento. O bit mais significativo indica se é uma interrupção (1) ou exceção (0), e os bits inferiores contêm o código específico.
3.  **Desabilitação global:** O bit **MIE** (*Machine Interrupt Enable*) em **MSTATUS** é automaticamente zerado, impedindo que outras interrupções ocorram (aninhamento) durante o tratamento inicial.
4.  **Desvio para o vetor:** O contador de programa (PC) é carregado com o valor de **MTVEC** (*Machine Trap Vector*), que contém o endereço base da rotina de tratamento de interrupções.

Esta sequência é implementada diretamente no hardware pelo módulo `csr_file.vhd`, garantindo que o salvamento de contexto seja atômico e seguro.

### 1.3. Retorno de Interrupção (Trap Return)

A instrução **MRET** (*Machine Return*) é usada para sair da rotina de tratamento e restaurar o fluxo normal de execução. Ao ser decodificada, o hardware executa:

1.  Restaura o valor de **MIE** a partir de **MPIE** (*Machine Previous Interrupt Enable*).
2.  Copia o conteúdo de **MEPC** para o PC, retornando para a instrução seguinte à interrupção.
3.  Restaura o nível de privilégio anterior do processador.

---

## 2. O Controlador Local (CLINT)

O **CLINT** (*Core Local Interruptor*) é um periférico integrado que gerencia interrupções de baixa latência e de altíssimo determinismo: as interrupções de timer e software. Ele é implementado em `rtl/soc/clint.vhd` e possui conexão direta com o núcleo.

### 2.1. Microarquitetura do CLINT

O CLINT é mapeado em memória e expõe quatro registradores principais através de uma interface de barramento (MMIO):

| Endereço | Registrador | Descrição |
| --- | --- | --- |
| 0x00 | **MSIP** | Machine Software Interrupt Pending (1 bit) |
| 0x08 | **MTIMECMP** (LOW) | Parte baixa do comparador de timer |
| 0x0C | **MTIMECMP** (HIGH) | Parte alta do comparador de timer |
| 0x10 | **MTIME** (LOW) | Parte baixa do contador de tempo |
| 0x14 | **MTIME** (HIGH) | Parte alta do contador de tempo |

### 2.2. O Temporizador de Hardware (mtime / mtimecmp)

O CLINT implementa um contador de tempo de 64 bits chamado **MTIME** que incrementa continuamente enquanto o processador está ativo. Este valor é comparado com o registrador **MTIMECMP** (também de 64 bits):

```vhdl
-- Timer Interrupt: dispara quando mtime >= mtimecmp
irq_timer_o <= '1' when (r_mtime >= r_mtimecmp) else '0';
```

Quando `MTIME >= MTIMECMP`, a linha **MTIP** (*Machine Timer Interrupt Pending*) é ativada. O software tipicamente configura o `MTIMECMP` para gerar interrupções periódicas (ex: *ticks* de um sistema operacional).

> **Nota sobre o Determinismo do Timer:** Por ser um contador que incrementa linearmente junto com o clock do sistema, o timer oferece comportamento previsível. O momento exato da interrupção pode ser calculado matematicamente: `(MTIMECMP - MTIME_atual) / freq_clock`.

### 2.3. Interrupção de Software (MSIP)

O registrador **MSIP** é um bit único que pode ser escrito via software para gerar uma interrupção local. O uso típico inclui:

* **Comunicação inter-processos (IPC)** ou sinalização.
* **Delegação de tarefas**, onde uma interrupção de hardware rápida agenda um trabalho de software de menor prioridade.

A escrita no bit 0 do MSIP (endereço 0x00) aciona o sinal, e o próprio software tratador deve limpar este bit ao final do processamento para baixar a linha de interrupção.

---

## 3. O Controlador Global (PLIC)

O **PLIC** (*Platform-Level Interrupt Controller*) é o maestro das interrupções externas, gerenciando sinais de periféricos do SoC (UART, DMA, NPU, etc.). Diferente do CLINT, que lida com eventos íntimos ao núcleo, o PLIC concentra, prioriza e arbitra múltiplas fontes simultâneas.

### 3.1. Arquitetura do PLIC

O PLIC (implementado em `rtl/soc/plic.vhd`) suporta até 32 fontes de interrupção. Sua arquitetura opera em três estágios:

1.  **Gateway:** Detecta e registra de forma assíncrona o pedido do periférico.
2.  **Arbiter:** Avalia as interrupções pendentes e seleciona a de maior prioridade.
3.  **Claim/Complete:** Protocolo de *handshaking* em duas vias com o processador.

### 3.2. Mapa de Memória do PLIC

| Endereço | Registrador | Descrição |
| --- | --- | --- |
| 0x000000 | Prioridade | Define a prioridade de cada fonte (0-7) |
| 0x001000 | Pending | Retorna quais fontes estão aguardando atendimento (Leitura) |
| 0x002000 | Enable | Máscara para habilitar fontes específicas |
| 0x200000 | Threshold | Prioridade mínima exigida para interromper o Core |
| 0x200004 | Claim/Complete | Leitura = Reivindica (Claim), Escrita = Conclui (Complete) |

### 3.3. Protocolo Claim/Complete (O Ciclo de Vida da Interrupção)

Para garantir que nenhuma interrupção seja perdida ou tratada em duplicidade, o PLIC exige um protocolo rigoroso:

* **Fase 1 - Claim (Reivindicação):** O processador lê o endereço `0x200004`. O PLIC retorna o ID da interrupção de maior prioridade no momento e **limpa automaticamente** o bit de *pending* no Gateway, marcando a interrupção como "em tratamento".
* **Fase 2 - Complete (Conclusão):** Após executar a rotina do driver, o software escreve o mesmo ID de volta no endereço `0x200004`. Isso sinaliza ao PLIC que a tarefa acabou, liberando o Gateway para aceitar novos disparos daquele mesmo periférico.

---

## 4. Integração Hardware/Software

A ponte entre os sinais físicos de silício e o código em C é feita pelos registradores CSR do núcleo e pela camada de abstração de hardware (HAL).

### 4.1. Construção Dinâmica do Vetor MIP

Fisicamente, no módulo `csr_file.vhd`, o registrador **MIP** não é uma memória estática, mas sim um reflexo em tempo real das linhas físicas que chegam da topologia do SoC:

```vhdl
s_mip_comb <= (
    11 => Irq_Ext_i,   -- MEIP: Vem do PLIC
    7  => Irq_Timer_i, -- MTIP: Vem do CLINT
    3  => Irq_Soft_i,  -- MSIP: Vem do CLINT
    others => '0'
);
```

### 4.2. O Central Trap Handler (Software)

O fluxo de software começa no arquivo `fpga/sw/platform/bsp/irq/irq_dispatch.c`. A função principal utiliza o atributo de compilador `interrupt("machine")`, que instrui o GCC a gerar código de salvamento de contexto seguro e a instrução `mret` no final.

O despachante lê o `MCAUSE` para rotear o fluxo:

```c
void __attribute__((interrupt("machine"))) irq_dispatch_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    // Interrupção Externa do PLIC (Bit 31 em '1' e código 0xB)
    if (mcause == 0x8000000B) { 
        uint32_t source = hal_plic_claim();  // Lê o ID vencedor
        
        if (source > 0 && source < PLIC_MAX_SOURCES) {
            if (g_isr_table[source] != NULL) {
                g_isr_table[source]();       // Executa o driver do periférico
            }
        }
        
        hal_plic_complete(source);           // Libera o PLIC
    }
}
```