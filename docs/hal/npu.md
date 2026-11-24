# NPU

A HAL da NPU cobre o **uso básico** do acelerador: um produto de matrizes $4\times K$ por $K\times4$ por vez, com os operandos enviados pela CPU ou pelo DMA. Os mecanismos avançados (pesos residentes, *im2col*, modo GEMV, *streaming* e descritores) são programados diretamente pelos registradores, como faz o [servidor da CNN](../aplicacoes/servidores-npu.md); eles estão descritos na [documentação da NPU](https://risc-v-azedinha.github.io/NPU/).

## Referência

| Função | Uso |
|---|---|
| `hal_npu_init()` | Reinicia os ponteiros e o estado da NPU |
| `hal_npu_set_dma_enabled(sim)` | Envia os operandos por DMA (`true`) ou por escritas da CPU (`false`) |
| `hal_npu_configure(K, &quant)` | Número de passos $K$ e a quantização da PPU (`mult`, `shift`, `zero_point`, `relu`) |
| `hal_npu_load_bias(vieses)` | Os 4 vieses de 32 bits, um por coluna |
| `hal_npu_load_weights(palavras, n)`, `hal_npu_load_inputs(palavras, n)` | Pesos e entradas empacotados, 4 valores INT8 por palavra |
| `hal_npu_start()` | Dispara o cálculo, zerando os acumuladores |
| `hal_npu_is_busy()`, `hal_npu_wait_done()` | Consulta ou espera o fim |
| `hal_npu_read_output(palavras, n)` | Lê os resultados: uma palavra por linha do arranjo, um byte por coluna |

## Formato dos dados

A palavra $k$ das entradas traz o elemento $k$ dos 4 vetores de entrada (byte $i$ = linha $i$), e a palavra $k$ dos pesos, o elemento $k$ dos 4 vetores de pesos (byte $j$ = coluna $j$). O resultado sai em 4 palavras, uma por linha, começando pela linha 3; cada byte é o resultado de uma coluna, depois da PPU:

$$
q_{ij}=\mathrm{clamp}_{[-128,127]}\left(\left\lfloor\frac{\left(\sum_k a_i[k]\,w_j[k]+b_j\right)\cdot M}{2^S}\right\rceil+Z\right),
$$

com ReLU opcional. O exemplo usa $M=1$, $S=0$ e $Z=0$: o resultado é a própria soma, saturada em 8 bits.

## Exemplo: produto de matrizes conferido pela CPU

```c
#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"

// Produto de matrizes 4 x K por K x 4 na NPU, conferido contra a CPU.
#define K 8

static int8_t a[4][K], w[4][K];                     // 4 vetores de entrada e 4 de pesos

static uint32_t pack(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return (uint8_t)b0 | (uint32_t)(uint8_t)b1 << 8 | (uint32_t)(uint8_t)b2 << 16 | (uint32_t)(uint8_t)b3 << 24;
}

int main(void) {
    hal_uart_init();
    for (int i = 0; i < 4; i++)
        for (int k = 0; k < K; k++) { a[i][k] = (int8_t)(i + k); w[i][k] = (int8_t)(k - i); }

    // Palavra k de entradas: o elemento k das 4 linhas; palavra k de pesos: o elemento k das 4 colunas
    uint32_t in_words[K], w_words[K];
    for (int k = 0; k < K; k++) {
        in_words[k] = pack(a[0][k], a[1][k], a[2][k], a[3][k]);
        w_words[k]  = pack(w[0][k], w[1][k], w[2][k], w[3][k]);
    }

    npu_quant_params_t q = { .mult = 1, .shift = 0, .zero_point = 0, .relu = false };
    uint32_t bias[4] = { 0, 0, 0, 0 };
    hal_npu_init();
    hal_npu_set_dma_enabled(true);                  // os buffers vão à NPU por DMA
    hal_npu_configure(K, &q);
    hal_npu_load_bias(bias);
    hal_npu_load_weights(w_words, K);
    hal_npu_load_inputs(in_words, K);
    hal_npu_start();
    hal_npu_wait_done();

    uint32_t out[4];                                // uma palavra por linha, um byte por coluna
    hal_npu_read_output(out, 4);

    int erros = 0;
    for (int i = 0; i < 4; i++) {
        int8_t *row = (int8_t *)&out[3 - i];        // a drenagem entrega a linha 3 primeiro
        for (int j = 0; j < 4; j++) {
            int32_t ref = 0;
            for (int k = 0; k < K; k++) ref += a[i][k] * w[j][k];
            if (ref > 127) ref = 127;
            if (ref < -128) ref = -128;
            erros += (row[j] != (int8_t)ref);
        }
    }
    hal_uart_puts(erros ? "\r\nNPU: divergencia\r\n" : "\r\nNPU: resultados conferem com a CPU\r\n");
    while (1);
}
```

Para executar, salve o programa em `fpga/sw/apps/demo_npu.c` e envie-o com `make upload SW=demo_npu`.
