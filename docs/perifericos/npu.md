# NPU

A **Unidade de Processamento Neural** (NPU) é o acelerador de inferência de redes neurais do SoC: um arranjo sistólico $4\times4$ de precisão INT8, com fluxo de dados *Output Stationary*, modo GEMV para camadas densas e mecanismos de movimentação de dados que tiram a CPU do caminho crítico. O RTL fica em `rtl/perips/npu/`, um submódulo Git do repositório [NPU](https://github.com/RISC-V-Azedinha/NPU).

!!! info "Documentação própria"
    A arquitetura, o mapeamento das camadas no arranjo, a programação de cada mecanismo e os resultados medidos na placa estão na [documentação da NPU](https://risc-v-azedinha.github.io/NPU/). Esta página trata só da integração ao SoC.

## Integração ao SoC

A NPU é um escravo da [interconexão](../soc/interconexao.md) na região `0x9000_0000`. A CPU a configura por escritas nos registradores, e o [DMA](../soc/memoria-dma.md) move os dados entre a RAM e as portas da NPU: pesos, imagens, programas de descritores e resultados. Quando uma porta ainda não pode atender (a fila de saída vazia durante um cálculo, ou a fila de descritores cheia), a NPU **segura o barramento** até poder responder, o que permite ao DMA e à CPU ler e escrever sem consultar o registrador de estado. Ao fim de um cálculo, a NPU pode interromper a CPU pela fonte 3 do [PLIC](../processador/interrupcoes.md).

## Registradores

| Offset | Nome | Acesso | Descrição |
|---|---|---|---|
| `0x00` | `STATUS` | RO | `BUSY` (bit 0), `DONE` (bit 1), `OUT_VLD` (bit 3) e fim do programa de descritores (bit 4) |
| `0x04` | `CMD` | WO | `START`, limpeza dos acumuladores, *tiling* sem drenagem e reinício dos ponteiros |
| `0x08` | `CONFIG` | RW | Número de passos $K$ por *tile* |
| `0x0C` | `DESC` | WO | Porta do programa de descritores |
| `0x10` | `WRITE_W` | WO | Porta de pesos |
| `0x14` | `WRITE_A` | WO | Porta de ativações |
| `0x18` | `READ_OUT` | RO | Porta de resultados (FIFO de saída) |
| `0x1C` | `WRITE_IMG` | WO | Porta da imagem crua do *im2col* |
| `0x20`, `0x24` | `W_BASE`, `I_BASE` | RW | Bases das regiões de pesos e de ativações (pesos residentes) |
| `0x28`–`0x30` | `IM2COL_*` | RW | Habilitação, geometria e número de janelas do *im2col* |
| `0x34` | `TILES` | RW | *Tiles* por `START`, retorno dos ponteiros e seleção dos vieses |
| `0x38` | `OUT_CFG` | RW | Formato da saída e fusão de camadas (`LOOP`) |
| `0x3C` | `MODE` | RW | `GEMV`, `STREAM_I`, `STREAM_W` e `OVERLAP` |
| `0x40`–`0x48` | `QUANT_CFG`, `QUANT_MULT`, `FLAGS` | RW | Quantização da PPU e ReLU |
| `0x80`–`0xFC` | `BIAS` | RW | Banco de vieses: 8 *tiles* × 4 colunas |

O detalhamento de cada campo está na [API de programação](https://risc-v-azedinha.github.io/NPU/software/#api-de-programacao) da documentação da NPU.

## HAL

A HAL (`fpga/sw/platform/bsp/hal/hal_npu.h`) cobre o uso básico, com a CPU ou o DMA movendo os operandos:

| Função | Uso |
|---|---|
| `hal_npu_init`, `hal_npu_configure` | Inicializa e configura $K$ e a quantização |
| `hal_npu_load_weights`, `hal_npu_load_inputs`, `hal_npu_load_bias` | Carrega os operandos (por DMA, se habilitado com `hal_npu_set_dma_enabled`) |
| `hal_npu_start`, `hal_npu_start_accumulate` | Dispara um cálculo, zerando ou mantendo os acumuladores |
| `hal_npu_is_busy`, `hal_npu_wait_done` | Consulta ou espera o fim |
| `hal_npu_read_output` | Lê os resultados |

Os mecanismos avançados (pesos residentes, *im2col*, GEMV, *streaming* e descritores) são programados diretamente pelos registradores; o [servidor da CNN](../aplicacoes/servidores-npu.md#servidor-da-cnn-cnn_serverc) é o exemplo completo.
