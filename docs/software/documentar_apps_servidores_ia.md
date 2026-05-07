# Aplicações e Servidores no SoC RISC-V (Bare-Metal)

## Visão Geral

Esta seção documenta a arquitetura das aplicações de software executadas sobre o SoC RISC-V em ambiente *bare-metal*. O foco está na interação entre software e hardware, evidenciando como os programas em C utilizam a HAL (*Hardware Abstraction Layer*) para validar o funcionamento do sistema e como servidores de Inteligência Artificial implementam um protocolo de comunicação para processamento de inferências.

Diferentemente de sistemas com sistema operacional, todas as aplicações executam diretamente sobre o hardware, sendo responsáveis pelo controle explícito de periféricos, memória e fluxo de execução.

---

# 1. Aplicações de Demonstração e Validação (Apps)

## 1.1 Estrutura de um Programa Bare-Metal

As aplicações seguem um padrão estrutural comum:

```c
#include "hal.h"

int main() {
    hal_init();

    while (1) {
        // loop principal
    }
}
```

### Características Arquiteturais

- Inclusão de cabeçalhos da HAL para acesso aos periféricos;
- Inicialização explícita do hardware na `main`;
- Execução contínua em laço infinito (*superloop*);
- Ausência de sistema operacional e gerenciamento automático de recursos.

A HAL atua como camada intermediária, abstraindo detalhes de registradores e permitindo que o software interaja com:

- GPIO (entrada de botões);
- UART (comunicação serial);
- Video RAM (VGA);
- periféricos especializados.

---

## 1.2 benchmark.c — Estresse da ULA

### Objetivo

Validar o desempenho computacional do processador RISC-V.

### Arquitetura

O `benchmark.c` executa operações aritméticas intensivas, com foco em:

- multiplicações;
- somas acumulativas;
- loops de alta repetição.

### Interação Hardware-Software

- Execução direta na ULA (CPU-bound);
- Nenhuma dependência significativa de periféricos;
- Mede a capacidade de throughput do pipeline da CPU.

---

## 1.3 fractal.c — Carga Computacional Sustentada

### Objetivo

Gerar carga computacional contínua para validar estabilidade e desempenho.

### Arquitetura

- Cálculo iterativo (ex: fractais tipo Mandelbrot);
- Uso intensivo de operações de ponto fixo ou inteiro;
- Execução contínua no loop principal.

### Interação Hardware-Software

- Uso intensivo da CPU;
- Escrita potencial em memória de vídeo (framebuffer);
- Teste combinado de processamento e memória.

---

## 1.4 pong.c — Integração de Periféricos

### Objetivo

Validar o funcionamento simultâneo de múltiplos periféricos.

### Arquitetura

O `pong.c` implementa um sistema interativo em tempo real:

- leitura de entradas via GPIO (botões);
- lógica de jogo executada na CPU;
- renderização gráfica via escrita direta na Video RAM (VGA).

### Interação Hardware-Software

- GPIO → entrada de controle;
- CPU → lógica de atualização do jogo;
- VGA → saída gráfica via memória mapeada.

---

## 1.5 uart_echo.c — Comunicação Serial

### Objetivo

Validar o canal de comunicação UART.

### Arquitetura

- leitura de dados via UART;
- retransmissão imediata (echo);
- loop contínuo.

### Interação Hardware-Software

- CPU atua como intermediária;
- UART como canal de entrada e saída;
- valida integridade e sincronização da comunicação.

---

# 2. Arquitetura do Servidor MLP (Software)

## 2.1 Visão Geral

O `mlp_server.c` implementa um servidor de inferência totalmente em software, utilizando exclusivamente a CPU (ULA).

### Fluxo Arquitetural

```text
UART → RAM → CPU (ULA) → RAM → UART
```

---

## 2.2 Protocolo de Comunicação

O servidor recebe via UART:

- pesos da rede neural;
- vieses;
- vetor de entrada.

Esses dados são serializados no Host e reconstruídos na RAM do SoC.

---

## 2.3 Execução da Inferência

Após o recebimento:

1. Os dados são armazenados na RAM principal;
2. O processador executa multiplicações de matrizes;
3. Aplica funções de ativação (quando necessário);
4. Gera a classificação final.

### Características

- execução sequencial;
- processamento totalmente CPU-bound;
- uso intensivo da ULA;
- latência proporcional ao tamanho da rede.

---

## 2.4 Interação Hardware-Software

- UART → entrada de dados;
- RAM → armazenamento intermediário;
- CPU → processamento matemático;
- UART → envio do resultado.

---

# 3. Arquitetura do Servidor NPU (Hardware-Accelerated)

## 3.1 Visão Geral

O `npu_server.c` implementa um modelo acelerado por hardware, utilizando uma NPU (*Neural Processing Unit*).

### Fluxo

```text
UART → CPU → NPU → CPU → UART
```

---

## 3.2 Papel do Processador (Orquestrador)

Diferente do MLP:

- a CPU não realiza as operações matemáticas;
- atua como controlador do fluxo de execução.

### Etapas

1. Recebe dados via UART;
2. Armazena na RAM;
3. Configura registradores da NPU via HAL;
4. Dispara execução do acelerador.

---

## 3.3 Configuração da NPU

A CPU escreve em registradores mapeados em memória:

- endereço dos dados de entrada;
- endereço dos pesos;
- comando de execução.

Isso é feito através da HAL, que encapsula acessos a registradores.

---

## 3.4 Protocolo Temporal de Execução

Após iniciar a NPU, o sistema precisa aguardar a conclusão.

### Estratégia utilizada: Polling

- leitura contínua de registradores de status;
- verificação de flag de término.

Exemplo conceitual:

```c
while (!npu_done()) {
    // espera ativa
}
```

Alternativamente, poderia ser implementado via interrupções.

---

## 3.5 Coleta e Retorno do Resultado

Após conclusão:

1. CPU lê resultado da NPU;
2. formata dados;
3. envia classificação via UART ao Host.

---

## 3.6 Interação Hardware-Software

- CPU → controle da NPU;
- NPU → execução paralela de operações matriciais;
- RAM → armazenamento compartilhado;
- UART → interface com o Host.

---

# 4. Comparação Arquitetural: MLP vs NPU

| Característica | MLP (Software) | NPU (Hardware) |
|--------|--------|--------|
| Execução | CPU (ULA) | Acelerador dedicado |
| Paralelismo | Limitado | Alto |
| Latência | Alta | Baixa |
| Flexibilidade | Alta | Média |
| Complexidade HW | Baixa | Alta |

---

## Insight Central

O sistema evidencia dois paradigmas distintos:

- **Software-bound:** processamento ciclo a ciclo na CPU;
- **Hardware-accelerated:** delegação para periférico especializado.

---

# 5. Conclusão

As aplicações de demonstração validam o funcionamento do SoC RISC-V em diferentes dimensões:

- capacidade computacional (benchmark, fractal);
- integração de periféricos (pong);
- comunicação (UART).

Os servidores de IA expandem essa validação para cenários reais de processamento, demonstrando de forma clara o impacto arquitetural da escolha entre:

- execução em software (MLP);
- aceleração por hardware (NPU).

Esse contraste evidencia o conceito fundamental de **co-design hardware-software**, no qual decisões de arquitetura impactam diretamente desempenho, eficiência e complexidade do sistema.
