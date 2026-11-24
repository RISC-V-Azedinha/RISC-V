# Resultados da síntese

Esta página resume os relatórios gerados pelo `make fpga-build` para a **Nexys A7-100T** (dispositivo `xc7a100tcsg324-1`), com o SoC completo: núcleo multiciclo, interconexão, memórias, DMA, controladores de interrupção, periféricos, UART2 e NPU. Os relatórios ficam em `build/fpga/<placa>/reports/` e são refeitos a cada síntese; os números abaixo são da síntese de 26/10/2026, com o Vivado 2025.2, depois do roteamento e da otimização física.

| Relatório | Conteúdo |
|---|---|
| `utilization_synth.rpt` | Recursos estimados após a síntese |
| `utilization_route.rpt` | Recursos após o roteamento (os números desta página) |
| `timing_summary.rpt` | Folgas de *setup* e *hold* e os caminhos mais lentos |
| `power.rpt` | Estimativa de consumo |

## Utilização de recursos

| Recurso | Usado | Disponível | Utilização |
|---|---:|---:|---:|
| LUTs | 12.048 | 63.400 | 19,0% |
| — como lógica | 11.683 | 63.400 | 18,4% |
| — como memória (RAM distribuída e registradores de deslocamento) | 365 | 19.000 | 1,9% |
| Registradores (*flip-flops*) | 7.539 | 126.800 | 5,9% |
| Blocos de RAM (BRAM36 equivalentes) | 107,5 | 135 | **79,6%** |
| DSPs (DSP48E1) | 16 | 240 | 6,7% |
| Pinos de E/S | 117 | 210 | 55,7% |
| *Buffers* globais de relógio | 2 | 32 | 6,3% |

A lógica ocupa menos de um quinto da FPGA; o recurso que limita o projeto é a **memória em bloco**, com quase 80% ocupados. Uma estimativa a partir dos tamanhos explica a conta: a RAM principal de 256 KB ocupa 64 blocos de 4 KB; a memória de vídeo é declarada com $2^{17}$ posições de 1 byte (128 KB), o que pode levar a até 32 blocos, embora a imagem use só 76.800 bytes; a Boot ROM ocupa 1; e o restante fica com as memórias locais e as filas da NPU e dos periféricos. Os 16 DSPs são os multiplicadores dos 16 PEs do arranjo sistólico da NPU.

!!! note "O que isso significa para o projeto"
    Aumentar a RAM principal ou as memórias da NPU esbarraria primeiro na BRAM, e não na lógica; dimensionar a memória de vídeo pelas 76.800 posições realmente usadas é a forma mais simples de liberar blocos. Por outro lado, há espaço de sobra em LUTs e DSPs para acrescentar lógica, como uma extensão M no núcleo ou um arranjo sistólico maior, desde que as memórias acompanhem.

## Temporização

O relógio do sistema é o oscilador de 100 MHz da placa (`sys_clk_pin`, período de 10 ns), e o projeto **fecha a temporização** sem nenhuma violação:

| Verificação | Pior folga | Caminhos verificados | Violações |
|---|---:|---:|---:|
| *Setup* (WNS) | 0,034 ns | 28.314 | 0 |
| *Hold* (WHS) | 0,032 ns | 28.314 | 0 |
| Largura de pulso (WPWS) | 3,750 ns | 8.166 | 0 |

A folga de *setup* é a margem entre o instante em que o dado chega a um registrador e o instante em que ele precisa estar estável antes da borda do relógio. Uma folga positiva, mesmo pequena, significa que todos os caminhos cabem no período de 10 ns; a folga de 34 ps mostra que o projeto está no limite da frequência de 100 MHz.

### Caminho crítico

O caminho mais lento vai do registrador de instrução (`r_IR`) ao registrador de resultado da ULA (`r_ALUResult`), no núcleo multiciclo:

| Item | Valor |
|---|---|
| Origem | `U_CORE/U_DATAPATH/r_IR_reg[1]` |
| Destino | `U_CORE/U_DATAPATH/r_ALUResult_reg[29]` |
| Atraso total | 9,859 ns |
| Lógica | 1,698 ns (17%), em 8 níveis de LUT |
| Roteamento | 8,161 ns (83%) |

É o estágio EX: a instrução decodificada escolhe os operandos e a operação, e a ULA de 32 bits calcula o resultado num único ciclo. O atraso é dominado pelo **roteamento**, e não pela lógica, o que é típico de FPGAs: os fios entre as LUTs custam mais que as LUTs. Para chegar a esse resultado, o fluxo usa `phys_opt_design` antes e depois do roteamento, e alguns sinais de controle foram registrados um ciclo antes do uso (como a decisão de desvio, em EX_BR, e as escritas de configuração da NPU), quebrando caminhos combinacionais longos.

## Potência

| Componente | Potência (W) |
|---|---:|
| Blocos de RAM | 0,178 |
| Sinais (roteamento) | 0,036 |
| Relógios | 0,028 |
| Lógica | 0,021 |
| E/S | 0,019 |
| DSPs | 0,002 |
| **Dinâmica** | **0,283** |
| Estática do dispositivo | 0,103 |
| **Total** | **0,387** |

O SoC consome menos de 0,4 W, com a junção a 26,8 °C. A maior parte da potência dinâmica vem das **memórias em bloco**, coerente com a utilização. A estimativa tem confiança baixa, porque foi feita sem dados de atividade dos sinais (o Vivado supõe taxas de chaveamento padrão); para um número mais preciso, seria preciso alimentar o estimador com a atividade obtida em simulação.

## Como reproduzir

```bash
make fpga-build BOARD=nexys_a7
```

Os relatórios saem em `build/fpga/nexys_a7/reports/`, e o registro completo do Vivado, em `build/fpga/nexys_a7/logs/build.log`. Para a Nexys 4, use `BOARD=nexys4`; o dispositivo é o mesmo, e os números são praticamente iguais (na última síntese, 11.912 LUTs e os mesmos 107,5 blocos de RAM). O fluxo está descrito em [Síntese em FPGA](sintese.md).
