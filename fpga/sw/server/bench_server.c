/**
 * @file bench_server.c
 * @brief Firmware de Benchmark Bare-Metal (GEMM - 16 MACs/ciclo)
 *        CORRIGIDO: Otimizado para alimentar 4 inputs independentes por ciclo.
 *
 *        Comandos: 'B' e 'P' (benchmark original, mantido para reproduzir as figuras antigas)
 *        e 'X' (benchmark v2: experimento parametrizado e autovalidado, ver MEMORIAL_BENCH_V2.md).
 */

#include <stdint.h>
#include <stdbool.h>

#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_timer.h"
#include "hal/hal_dma.h"

#define MAX_K_DIM 8192

static uint32_t buffer_weights[MAX_K_DIM];
static uint32_t buffer_inputs[MAX_K_DIM];

// Destino dos acumuladores do laço de referência da CPU: sem consumir o resultado, o
// compilador (-O2) elimina o laço inteiro e a medição da CPU vira só o custo do timer
static volatile int32_t g_cpu_sink[4];

uint8_t uart_read_byte() { return hal_uart_getc(); }

// ------------------------------------------------------------
// Gera os dados sintéticos do tile `idx` (determinístico a partir de idx, para
// poder ser regenerado tile a tile sem manter todos os tiles em memória ao
// mesmo tempo, tanto na passada serial quanto na pipelined).
// ------------------------------------------------------------
static void gen_tile_data(uint32_t idx, uint32_t k_dim, uint8_t sparsity) {
    uint32_t lfsr = 0xACE1u ^ (idx * 0x9E3779B9u);
    for (uint32_t i = 0; i < k_dim; i++) {
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);

        if ((lfsr % 100) < sparsity) {
            buffer_inputs[i] = 0;
        } else {
            buffer_inputs[i] = lfsr;
        }
        buffer_weights[i] = lfsr * 13;
    }
}

uint32_t uart_read_u32() {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() << 24);
    val |= ((uint32_t)hal_uart_getc() << 16);
    val |= ((uint32_t)hal_uart_getc() << 8);
    val |= ((uint32_t)hal_uart_getc());
    return val;
}

void uart_write_u64(uint64_t val) {
    hal_uart_putc((uint8_t)(val >> 56));
    hal_uart_putc((uint8_t)(val >> 48));
    hal_uart_putc((uint8_t)(val >> 40));
    hal_uart_putc((uint8_t)(val >> 32));
    hal_uart_putc((uint8_t)(val >> 24));
    hal_uart_putc((uint8_t)(val >> 16));
    hal_uart_putc((uint8_t)(val >> 8));
    hal_uart_putc((uint8_t)(val & 0xFF));
}

// =============================================================================================
// BENCHMARK V2 (comando 'X'): experimento parametrizado por camada e por mecanismo da NPU
// =============================================================================================
// Cada experimento descreve UMA camada (densa ou convolução) e QUAIS mecanismos da NPU usar. A
// janela de medição vai do início da movimentação de dados até todas as saídas estarem na RAM
// (entradas sempre incluídas; pesos incluídos se não forem residentes). O mesmo resultado é
// calculado pela CPU (referência, -O2) e comparado byte a byte: o benchmark se autovalida.
// Ver docs em MEMORIAL_BENCH_V2.md.

#define V2_KIND_DENSE   0
#define V2_KIND_CONV    1
#define V2_KIND_CNN     2           // Conv (im2col) + densa (GEMV) encadeadas, como na CNN do MNIST

#define V2_F_RESIDENT   (1u << 0)   // pesos carregados antes da janela (reuso entre inferências)
#define V2_F_SEQ        (1u << 1)   // um START para todos os tiles (sequenciador de tiles)
#define V2_F_OUT_DMA    (1u << 2)   // saída esvaziada por DMA em paralelo (exige V2_F_SEQ)
#define V2_F_GEMV       (1u << 3)   // densa com lote 1 no modo GEMV (4 linhas úteis)
#define V2_F_IM2COL     (1u << 4)   // convolução com im2col em hardware (senão, na CPU)
#define V2_F_BATCH4     (1u << 5)   // densa com lote 4 no modo normal (uma amostra por linha)
#define V2_F_CPU_REF    (1u << 6)   // mede também o tempo da referência na CPU
#define V2_F_STREAM     (1u << 7)   // START antes da carga: DMA em paralelo com o cômputo (exige V2_F_SEQ)
#define V2_F_OVERLAP    (1u << 8)   // tiles encadeados (acumuladores sombra)
#define V2_F_FUSE       (1u << 9)   // CNN: saída da Conv direto na RAM de Inputs da NPU
#define V2_F_RBIAS      (1u << 10)  // CNN: biases residentes (gravados fora da janela, um banco por camada)
#define V2_F_DESC       (1u << 11)  // CNN: configuração por descritores de camada (exige V2_F_FUSE)

static uint32_t v2_prog[256];                                    // Programa de descritores (CNN)
static uint32_t v2_prog_len;
static int      v2_desc;                                         // 1 = v2_cfg grava no programa

// Escrita de configuração: direto (MMIO) ou acrescentada ao programa de descritores
static void v2_cfg(uint32_t reg, uint32_t val) {
    if (v2_desc) { v2_prog[v2_prog_len++] = 0x10000000u | reg; v2_prog[v2_prog_len++] = val; }
    else         MMIO32(NPU_BASE_ADDR + reg) = val;
}

#define V2_ERR_OK       0
#define V2_ERR_PARAM    1

#define V2_MAX_WORDS    2048        // capacidade das RAMs de Pesos/Inputs da NPU (palavras)
#define V2_MAX_IMG      1024        // capacidade da imagem do im2col (bytes)
#define V2_MAX_OUT      4096

#define NPU(off)        MMIO32(NPU_BASE_ADDR + (off))
#define V2_NOW()        (CLINT_MTIME_LO)

__attribute__((aligned(4))) static int8_t   v2_raw_in[4 * V2_MAX_WORDS];  // entradas cruas: A[m][k] ou imagem
__attribute__((aligned(4))) static uint32_t v2_in_words[V2_MAX_WORDS];    // entradas no formato da NPU
static int32_t  v2_bias[32];
__attribute__((aligned(4))) static uint32_t v2_out_words[V2_MAX_OUT];    // saída da NPU (palavras da FIFO)
static int8_t   v2_ref[V2_MAX_OUT];                              // saída da referência na CPU

// MAC da referência na CPU. Sem a extensão M, a multiplicação é a __mulsi3 do BSP, que soma e desloca
// percorrendo os bits do SEGUNDO fator e para quando ele zera: o tempo depende dos dados (um fator
// nulo sai na hora; um int8 negativo, estendido para 32 bits, leva as 32 voltas). A ativação vai
// sempre como segundo fator, para o tempo da CPU refletir a esparsidade das ativações em todas as
// camadas; com "x * w", a ordem ficava a critério do compilador (na densa, os zeros não contavam).
int32_t __mulsi3(int32_t a, int32_t b);
static inline int32_t cpu_mul(int32_t w, int32_t x) { return __mulsi3(w, x); }

typedef struct {
    uint8_t  kind, sparsity, seed;
    uint16_t flags;
    uint16_t k, n;                                               // densa: K entradas, N saídas
    uint8_t  in_w, in_h, ksz, stride;                            // conv: imagem, kernel, passo
} v2_req_t;

typedef struct {
    uint32_t status, cyc_w, cyc_in, cyc_exec, cyc_total, cyc_cpu, mismatches;
    uint32_t macs_useful, macs_pe, words_w, words_in, words_out, timer_ovh;
} v2_res_t;

static uint32_t v2_lfsr;
static uint32_t v2_rand(void) {
    v2_lfsr ^= v2_lfsr << 13; v2_lfsr ^= v2_lfsr >> 17; v2_lfsr ^= v2_lfsr << 5;
    return v2_lfsr;
}
static int8_t v2_rand_act(uint8_t sparsity) {
    uint32_t r = v2_rand();
    return ((r >> 8) % 100 < sparsity) ? 0 : (int8_t)r;
}

static int8_t v2_ppu(int32_t acc, int32_t bias, int shift) {
    int32_t v = acc + bias;
    v = (v + (1 << (shift - 1))) >> shift;
    if (v > 127) v = 127;
    if (v < -128) v = -128;
    return (int8_t)v;
}

static void uart_write_u32(uint32_t v) {
    hal_uart_putc((uint8_t)(v >> 24)); hal_uart_putc((uint8_t)(v >> 16));
    hal_uart_putc((uint8_t)(v >> 8));  hal_uart_putc((uint8_t)v);
}

static int v2_log2_ceil(uint32_t x) { int l = 0; while ((1u << l) < x) l++; return l; }

// Lê `words` palavras da FIFO de saída pela CPU (consulta OUT_VALID antes de cada leitura)
static void v2_cpu_read_out(uint32_t* dst, uint32_t words) {
    for (uint32_t i = 0; i < words; i++) {
        while (!(NPU(0x00) & NPU_STATUS_OUT_VLD));
        dst[i] = NPU(0x18);
    }
}

// Carrega as entradas na NPU: densa (RAM de Inputs), conv com im2col em hardware (imagem crua na
// porta IMG) ou conv com im2col na CPU (janelas montadas aqui, só com somas: a CPU não tem
// extensão M e cada multiplicação de índice viraria uma chamada a __mulsi3). Devolve as palavras
// transferidas.
static uint32_t v2_load_inputs(const v2_req_t* q, int dense, int hwi2c, uint32_t T, uint32_t nwin,
                               uint32_t ow, uint32_t oh, uint32_t in_bytes, uint32_t in_words) {
    (void)oh;
    if (dense) {
        hal_dma_memcpy((uint32_t)v2_in_words, NPU_BASE_ADDR + 0x14, in_words, 1);
        return in_words;
    }
    if (hwi2c) {
        in_words = (in_bytes + 3) / 4;
        hal_dma_memcpy((uint32_t)v2_raw_in, NPU_BASE_ADDR + 0x1C, in_words, 1);
        return in_words;
    }
    // Palavra (g, tap) com o pixel do tap nas janelas 4g..4g+3; janelas além da última leem zero
    static const int8_t v2_zeros[V2_MAX_IMG] = {0};               // cobre qualquer deslocamento de tap
    uint32_t v = 0, row_base = 0, idx = 0, wins = 0;
    const uint32_t col_step = q->stride, row_step = (uint32_t)q->stride * q->in_w;
    const uint32_t tap_row_jump = q->in_w - q->ksz;
    for (uint32_t g = 0; g < T; g++) {
        const int8_t* qp[4];
        for (int rr = 0; rr < 4; rr++) {
            if (wins < nwin) {
                qp[rr] = &v2_raw_in[row_base + v];
                wins++;
                v += col_step;
                if (v == ow * col_step) { v = 0; row_base += row_step; }
            } else qp[rr] = v2_zeros;
        }
        uint32_t off = 0;
        for (uint32_t i = 0; i < q->ksz; i++) {
            for (uint32_t j = 0; j < q->ksz; j++) {
                v2_in_words[idx++] = (uint32_t)(uint8_t)qp[0][off]
                                   | (uint32_t)(uint8_t)qp[1][off] << 8
                                   | (uint32_t)(uint8_t)qp[2][off] << 16
                                   | (uint32_t)(uint8_t)qp[3][off] << 24;
                off++;
            }
            off += tap_row_jump;
        }
    }
    hal_dma_memcpy((uint32_t)v2_in_words, NPU_BASE_ADDR + 0x14, idx, 1);
    return idx;
}

// Referência na CPU de uma camada (fora da função medida e sem inlining: o código da referência não
// pode mudar a alocação de registradores do trecho medido da NPU)
static __attribute__((noinline)) void v2_ref_layer(const v2_req_t* q, int dense, int m, uint32_t K,
                                                   uint32_t ow, uint32_t oh, int shift) {
    const int8_t* W = (const int8_t*)buffer_weights;               // W[n][k] = W[((n/4)*K + k)*4 + n%4]
    if (dense) {
        for (int mm = 0; mm < m; mm++)
            for (uint32_t n = 0; n < q->n; n++) {
                int32_t acc = 0;
                const int8_t* wp = &W[(n / 4) * K * 4 + (n % 4)];
                const int8_t* xp = &v2_raw_in[mm * K];
                for (uint32_t k = 0; k < K; k++) acc += cpu_mul(wp[4 * k], xp[k]);
                v2_ref[mm * q->n + n] = v2_ppu(acc, v2_bias[n], shift);
            }
    } else {
        // Convolução direta, com índices incrementais (só a MAC usa multiplicação)
        uint32_t p = 0, row_base = 0;
        for (uint32_t u = 0; u < oh; u++, row_base += (uint32_t)q->stride * q->in_w) {
            for (uint32_t vv = 0, base = row_base; vv < ow; vv++, base += q->stride, p++) {
                int32_t acc[4] = {0, 0, 0, 0};
                const int8_t* wp = W;
                const int8_t* ip = &v2_raw_in[base];
                for (uint32_t i = 0; i < q->ksz; i++, ip += q->in_w) {
                    for (uint32_t j = 0; j < q->ksz; j++, wp += 4) {
                        int32_t px = ip[j];
                        acc[0] += cpu_mul(wp[0], px); acc[1] += cpu_mul(wp[1], px);
                        acc[2] += cpu_mul(wp[2], px); acc[3] += cpu_mul(wp[3], px);
                    }
                }
                for (int c = 0; c < 4; c++) v2_ref[p * 4 + c] = v2_ppu(acc[c], v2_bias[c], shift);
            }
        }
    }
}

static __attribute__((noinline)) void v2_run(const v2_req_t* q, v2_res_t* r) {
    const int dense = (q->kind == V2_KIND_DENSE);
    const int gemv  = dense && (q->flags & V2_F_GEMV);
    const int m     = dense ? ((q->flags & V2_F_BATCH4) ? 4 : 1) : 4;
    const int seq   = (q->flags & V2_F_SEQ) != 0;
    const int odma  = seq && (q->flags & V2_F_OUT_DMA);
    const int hwi2c = !dense && (q->flags & V2_F_IM2COL);

    uint32_t K, T, nwin = 0, ow = 0, oh = 0, cyc_tile, wpt;
    if (dense) {
        K = q->k; T = q->n / 4;
        if (q->n == 0 || q->n % 4 || q->n > 32 || K == 0 || T * K > V2_MAX_WORDS) { r->status = V2_ERR_PARAM; return; }
        if (gemv && ((K % 4) || (q->flags & V2_F_BATCH4))) { r->status = V2_ERR_PARAM; return; }
        cyc_tile = gemv ? K / 4 : K;
        wpt      = gemv ? 1 : 4;
    } else {
        if (q->ksz == 0 || q->stride == 0 || q->in_w < q->ksz || q->in_h < q->ksz ||
            (uint32_t)q->in_w * q->in_h > V2_MAX_IMG) { r->status = V2_ERR_PARAM; return; }
        K  = (uint32_t)q->ksz * q->ksz;
        ow = (q->in_w - q->ksz) / q->stride + 1;
        oh = (q->in_h - q->ksz) / q->stride + 1;
        nwin = ow * oh; T = (nwin + 3) / 4;
        if (ow < 4 || q->ksz > 15 || (!hwi2c && T * K > V2_MAX_WORDS) || T * 4 > V2_MAX_OUT) { r->status = V2_ERR_PARAM; return; }
        cyc_tile = K; wpt = 4;
    }
    const uint32_t n_out = dense ? q->n : 4;
    const int shift = 6 + v2_log2_ceil(K) / 2;

    // ---------------------------------------------------------------- Dados (fora da janela)
    v2_lfsr = 0x9E3779B9u ^ ((uint32_t)q->seed << 16) ^ (q->k << 4) ^ q->n;
    uint32_t w_words = dense ? T * K : K;
    for (uint32_t i = 0; i < w_words; i++) buffer_weights[i] = v2_rand();
    for (uint32_t i = 0; i < n_out; i++) v2_bias[i] = (int32_t)(v2_rand() % 4001) - 2000;
    uint32_t in_bytes = dense ? (uint32_t)m * K : (uint32_t)q->in_w * q->in_h;
    for (uint32_t i = 0; i < in_bytes; i++) v2_raw_in[i] = v2_rand_act(q->sparsity);

    // Formato das entradas que a NPU espera (o produtor da camada anterior já entregaria assim)
    uint32_t in_words = 0;
    if (dense) {
        if (gemv) {                                               // 4 features por palavra
            in_words = K / 4;
            for (uint32_t t = 0; t < in_words; t++) v2_in_words[t] = ((uint32_t*)v2_raw_in)[t];
        } else {                                                  // palavra k: byte m = A[m][k]
            in_words = K;
            for (uint32_t k = 0; k < K; k++) {
                uint32_t w = 0;
                for (int mm = 0; mm < m; mm++) w |= (uint32_t)(uint8_t)v2_raw_in[mm * K + k] << (8 * mm);
                v2_in_words[k] = w;
            }
        }
    }

    // Configuração estática da PPU e da NPU (fora da janela)
    NPU(0x44) = 1; NPU(0x40) = (uint32_t)shift; NPU(0x48) = 0;
    NPU(0x20) = 0; NPU(0x24) = 0;
    if (seq && dense) { for (uint32_t i = 0; i < n_out; i++) NPU(0x80 + 4 * i) = (uint32_t)v2_bias[i]; }
    else              { for (int c = 0; c < 4; c++) NPU(0x80 + 4 * c) = (uint32_t)v2_bias[c]; }

    if (q->flags & V2_F_RESIDENT) {
        NPU(0x04) = 0x40;
        hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, w_words, 1);
    }

    // ---------------------------------------------------------------- Janela de medição
    const int stream = seq && (q->flags & V2_F_STREAM);
    const uint32_t mode = (gemv ? 1u : 0u) | ((q->flags & V2_F_OVERLAP) ? 8u : 0u) |
                          (stream ? (2u | ((q->flags & V2_F_RESIDENT) ? 0u : 4u)) : 0u);
    const uint32_t out_words = T * wpt;
    uint32_t t0 = V2_NOW(), t1, t2;

    if (stream) {
        // Streaming: a NPU parte antes dos dados; cada leitura espera o seu dado chegar, e a
        // carga (entradas, depois os pesos) corre em paralelo com o cômputo
        NPU(0x04) = (q->flags & V2_F_RESIDENT) ? 0x80 : 0xC0;      // ponteiros de escrita
        if (hwi2c) {
            NPU(0x2C) = ((uint32_t)q->ksz << 20) | ((uint32_t)q->stride << 16) | (ow << 8) | q->in_w;
            NPU(0x30) = nwin;
            NPU(0x28) = 1;
        }
        NPU(0x3C) = mode; NPU(0x38) = 1; NPU(0x08) = cyc_tile;
        NPU(0x34) = T | (dense ? ((1u << 17) | (T > 1 ? (1u << 18) : 0)) : (1u << 16));
        NPU(0x04) = 0x36;
        t1 = V2_NOW();
        in_words = v2_load_inputs(q, dense, hwi2c, T, nwin, ow, oh, in_bytes, in_words);
        if (!(q->flags & V2_F_RESIDENT))
            hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, w_words, 1);
        t2 = V2_NOW();
        if (odma) hal_dma_drain(NPU_BASE_ADDR + 0x18, (uint32_t)v2_out_words, out_words);
        else      v2_cpu_read_out(v2_out_words, out_words);
        while (!(NPU(0x00) & NPU_STATUS_DONE));
    } else {
        if (!(q->flags & V2_F_RESIDENT)) {
            NPU(0x04) = 0x40;
            hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, w_words, 1);
        }
        t1 = V2_NOW();
        NPU(0x04) = 0x80;                                         // ponteiros de Inputs e da imagem
        in_words = v2_load_inputs(q, dense, hwi2c, T, nwin, ow, oh, in_bytes, in_words);
        if (hwi2c) {
            NPU(0x2C) = ((uint32_t)q->ksz << 20) | ((uint32_t)q->stride << 16) | (ow << 8) | q->in_w;
            NPU(0x30) = nwin;
            NPU(0x28) = 1;
        }
        t2 = V2_NOW();

        NPU(0x3C) = mode;
        NPU(0x38) = 1;                                            // OUT_CFG = ORDER
        NPU(0x08) = cyc_tile;

        if (seq) {
            uint32_t tiles = T;
            if (dense) tiles |= (1u << 17) | (T > 1 ? (1u << 18) : 0); // RW_I (+ bias por tile)
            else       tiles |= (1u << 16);                              // RW_W
            NPU(0x34) = tiles;
            NPU(0x04) = 0x36;
            if (odma) hal_dma_drain(NPU_BASE_ADDR + 0x18, (uint32_t)v2_out_words, out_words);
            else      v2_cpu_read_out(v2_out_words, out_words);
            while (!(NPU(0x00) & NPU_STATUS_DONE));
        } else {
            NPU(0x34) = 0;
            for (uint32_t j = 0; j < T; j++) {
                if (dense) for (int c = 0; c < 4; c++) NPU(0x80 + 4 * c) = (uint32_t)v2_bias[4 * j + c];
                uint32_t cmd = (j == 0) ? 0x36 : (dense ? 0x26 : 0x16);
                NPU(0x04) = cmd;
                while (!(NPU(0x00) & NPU_STATUS_DONE));
                v2_cpu_read_out(&v2_out_words[j * wpt], wpt);
            }
        }
    }
    uint32_t t3 = V2_NOW();

    NPU(0x28) = 0; NPU(0x34) = 0; NPU(0x38) = 0; NPU(0x3C) = 0;

    // ---------------------------------------------------------------- Referência na CPU
    uint32_t c0 = V2_NOW();
    v2_ref_layer(q, dense, m, K, ow, oh, shift);
    uint32_t c1 = V2_NOW();

    // ---------------------------------------------------------------- Validação
    uint32_t bad = 0;
    if (dense) {
        for (uint32_t n = 0; n < q->n; n++) {
            uint32_t j = n / 4, c = n % 4;
            for (int mm = 0; mm < m; mm++) {
                uint32_t word = gemv ? v2_out_words[j] : v2_out_words[j * 4 + mm];
                if ((int8_t)(word >> (8 * c)) != v2_ref[mm * q->n + n]) bad++;
            }
        }
    } else {
        for (uint32_t p = 0; p < nwin; p++)
            for (int c = 0; c < 4; c++)
                if ((int8_t)(v2_out_words[p] >> (8 * c)) != v2_ref[p * 4 + c]) bad++;
    }

    uint32_t o0 = V2_NOW(), o1 = V2_NOW();

    r->status      = V2_ERR_OK;
    r->cyc_w       = t1 - t0;
    r->cyc_in      = t2 - t1;
    r->cyc_exec    = t3 - t2;
    r->cyc_total   = t3 - t0;
    r->cyc_cpu     = (q->flags & V2_F_CPU_REF) ? (c1 - c0) : 0;
    r->mismatches  = bad;
    r->macs_useful = dense ? (uint32_t)m * q->n * K : nwin * 4 * K;
    r->macs_pe     = T * cyc_tile * 16;
    r->words_w     = (q->flags & V2_F_RESIDENT) ? 0 : w_words;
    r->words_in    = in_words;
    r->words_out   = out_words;
    r->timer_ovh   = o1 - o0;
}

// CNN de duas camadas (Conv com im2col em hardware + densa em GEMV, pesos residentes), como no
// cnn_server. Fatores: STREAM, OVERLAP, FUSE (saída da Conv direto na RAM de Inputs da NPU) e
// OUT_DMA (sem fusão, a saída da Conv vai para a RAM por DMA em vez da CPU). Na resposta,
// cyc_in = fase da Conv e cyc_exec = fase da densa.
// Referência na CPU da CNN (convolução + ReLU + densa), isolada como a v2_ref_layer
static __attribute__((noinline)) void v2_ref_cnn(const v2_req_t* q, uint32_t ow, uint32_t oh, uint32_t Kd,
                                                 uint32_t wd_base, int sh_c, int sh_d) {
    const int8_t* W = (const int8_t*)buffer_weights;
    int8_t* feat = (int8_t*)v2_in_words;                          // features da densa (4p + c)
    uint32_t p = 0, row_base = 0;
    for (uint32_t u = 0; u < oh; u++, row_base += (uint32_t)q->stride * q->in_w) {
        for (uint32_t vv = 0, base = row_base; vv < ow; vv++, base += q->stride, p++) {
            int32_t acc[4] = {0, 0, 0, 0};
            const int8_t* wp = W;
            const int8_t* ip = &v2_raw_in[base];
            for (uint32_t i = 0; i < q->ksz; i++, ip += q->in_w)
                for (uint32_t j = 0; j < q->ksz; j++, wp += 4) {
                    int32_t px = ip[j];
                    acc[0] += cpu_mul(wp[0], px); acc[1] += cpu_mul(wp[1], px);
                    acc[2] += cpu_mul(wp[2], px); acc[3] += cpu_mul(wp[3], px);
                }
            for (int c = 0; c < 4; c++) {
                int8_t y = v2_ppu(acc[c], v2_bias[c], sh_c);
                feat[p * 4 + c] = y < 0 ? 0 : y;                      // ReLU
            }
        }
    }
    const int8_t* Wd = &W[wd_base * 4];
    for (uint32_t n = 0; n < q->n; n++) {
        int32_t acc = 0;
        const int8_t* wp = &Wd[(n / 4) * Kd * 4 + (n % 4)];
        for (uint32_t k = 0; k < Kd; k++) acc += cpu_mul(wp[4 * k], feat[k]);
        v2_ref[n] = v2_ppu(acc, v2_bias[4 + n], sh_d);
    }
}

static __attribute__((noinline)) void v2_run_cnn(const v2_req_t* q, v2_res_t* r) {
    if (q->ksz == 0 || q->stride == 0 || q->in_w < q->ksz || q->in_h < q->ksz ||
        (uint32_t)q->in_w * q->in_h > V2_MAX_IMG || q->ksz > 15 || q->n == 0 || q->n > 32) { r->status = V2_ERR_PARAM; return; }
    const uint32_t Kc = (uint32_t)q->ksz * q->ksz;
    const uint32_t ow = (q->in_w - q->ksz) / q->stride + 1, oh = (q->in_h - q->ksz) / q->stride + 1;
    const uint32_t nwin = ow * oh, Tc = (nwin + 3) / 4;
    const uint32_t Kd = nwin * 4, Td = (q->n + 3) / 4, wd_base = (Kc + 3) & ~3u;
    if (ow < 4 || wd_base + Td * Kd > V2_MAX_WORDS || Tc * 4 > V2_MAX_OUT) { r->status = V2_ERR_PARAM; return; }
    const int seq_ovl = (q->flags & V2_F_OVERLAP) != 0, stream = (q->flags & V2_F_STREAM) != 0;
    const int fuse = (q->flags & V2_F_FUSE) != 0, odma = (q->flags & V2_F_OUT_DMA) != 0;
    const int sh_c = 6 + v2_log2_ceil(Kc) / 2, sh_d = 6 + v2_log2_ceil(Kd) / 2;

    // ---------------------------------------------------------------- Dados e pesos (fora da janela)
    v2_lfsr = 0x9E3779B9u ^ ((uint32_t)q->seed << 16) ^ (Kc << 4) ^ q->n;
    for (uint32_t i = 0; i < wd_base + Td * Kd; i++) buffer_weights[i] = v2_rand();
    for (uint32_t i = 0; i < 4; i++) v2_bias[i] = (int32_t)(v2_rand() % 4001) - 2000;
    for (uint32_t i = 0; i < q->n; i++) v2_bias[4 + i] = (int32_t)(v2_rand() % 40001) - 20000;
    const uint32_t img_bytes = (uint32_t)q->in_w * q->in_h, img_words = (img_bytes + 3) / 4;
    for (uint32_t i = 0; i < img_bytes; i++) v2_raw_in[i] = v2_rand_act(q->sparsity);
    NPU(0x20) = 0; NPU(0x04) = 0x40;
    hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, wd_base + Td * Kd, 1);

    const int rbias = (q->flags & V2_F_RBIAS) != 0, desc = (q->flags & V2_F_DESC) != 0;
    if ((desc && !fuse) || (rbias && Td > 3)) { r->status = V2_ERR_PARAM; return; }
    const uint32_t conv_bank = rbias ? 3 : 0;                     // densa nos bancos 0..Td-1

    if (rbias) {                                                  // biases residentes: fora da janela
        for (int c = 0; c < 4; c++) NPU(0x80 + 16 * conv_bank + 4 * c) = (uint32_t)v2_bias[c];
        for (uint32_t i = 0; i < Td * 4; i++) NPU(0x80 + 4 * i) = (i < q->n) ? (uint32_t)v2_bias[4 + i] : 0;
    }
    NPU(0x04) = 0x80;                                             // ponteiro da imagem em zero

    // Configuração das duas camadas: com descritores, monta o programa (fora da janela, como
    // na carga do modelo); sem eles, as mesmas escritas acontecem por MMIO dentro da janela
    v2_desc = desc; v2_prog_len = 0;
    #define CONV_CFG() do { \
        v2_cfg(0x44, 1); v2_cfg(0x40, (uint32_t)sh_c); v2_cfg(0x48, 1); \
        if (!rbias) for (int c = 0; c < 4; c++) v2_cfg(0x80 + 4 * c, (uint32_t)v2_bias[c]); \
        v2_cfg(0x20, 0); v2_cfg(0x24, 0); \
        v2_cfg(0x2C, ((uint32_t)q->ksz << 20) | ((uint32_t)q->stride << 16) | (ow << 8) | q->in_w); \
        v2_cfg(0x30, nwin); v2_cfg(0x28, 1); v2_cfg(0x08, Kc); \
        v2_cfg(0x34, Tc | (1u << 16) | (conv_bank << 19)); \
        v2_cfg(0x38, 1 | (fuse ? 4u : 0u)); \
        v2_cfg(0x3C, (stream ? 2u : 0u) | (seq_ovl ? 8u : 0u)); } while (0)
    #define DENSE_CFG(extra_mode) do { \
        v2_cfg(0x40, (uint32_t)sh_d); v2_cfg(0x48, 0); v2_cfg(0x28, 0); v2_cfg(0x38, 0); \
        if (!rbias) for (uint32_t i = 0; i < Td * 4; i++) v2_cfg(0x80 + 4 * i, (i < q->n) ? (uint32_t)v2_bias[4 + i] : 0); \
        v2_cfg(0x20, wd_base); v2_cfg(0x08, Kd / 4); \
        v2_cfg(0x34, Td | (1u << 17) | (Td > 1 ? (1u << 18) : 0)); \
        v2_cfg(0x3C, 1 | (seq_ovl ? 8u : 0u) | (extra_mode)); } while (0)

    uint32_t y_words[8];
    uint32_t t0, t1, t3;
    if (desc) {
        CONV_CFG();  v2_cfg(0x04, 0x36); v2_prog[v2_prog_len++] = 0x20000000u;      // START, WAIT
        DENSE_CFG(0); v2_cfg(0x04, 0x36); v2_prog[v2_prog_len++] = 0x20000000u;
        v2_cfg(0x3C, 0); v2_cfg(0x34, 0); v2_cfg(0x04, 0x80); v2_prog[v2_prog_len++] = 0x30000000u;
        v2_desc = 0;

        // ------------------------------------------------------------ Janela: programa + imagem
        t0 = V2_NOW();
        if (!stream) hal_dma_memcpy((uint32_t)v2_raw_in, NPU_BASE_ADDR + 0x1C, img_words, 1);
        hal_dma_memcpy((uint32_t)v2_prog, NPU_BASE_ADDR + 0x0C, v2_prog_len, 1);
        if (stream)  hal_dma_memcpy((uint32_t)v2_raw_in, NPU_BASE_ADDR + 0x1C, img_words, 1);
        for (uint32_t j = 0; j < Td; j++) y_words[j] = NPU(0x18);   // a O_DATA espera o resultado
        while (!(NPU(0x00) & (1u << 4)));
        t1 = t3 = V2_NOW();
    } else {
        // ------------------------------------------------------------ Janela: Conv
        t0 = V2_NOW();
        CONV_CFG();
        if (stream) {
            NPU(0x04) = 0x36;
            hal_dma_memcpy((uint32_t)v2_raw_in, NPU_BASE_ADDR + 0x1C, img_words, 1);
        } else {
            hal_dma_memcpy((uint32_t)v2_raw_in, NPU_BASE_ADDR + 0x1C, img_words, 1);
            NPU(0x04) = 0x36;
        }
        if (!fuse) {
            if (odma) hal_dma_drain(NPU_BASE_ADDR + 0x18, (uint32_t)v2_out_words, Tc * 4);
            else      v2_cpu_read_out(v2_out_words, Tc * 4);
        }
        while (!(NPU(0x00) & NPU_STATUS_DONE));
        NPU(0x28) = 0; NPU(0x34) = 0; NPU(0x38) = 0; NPU(0x3C) = 0;
        t1 = V2_NOW();

        // ------------------------------------------------------------ Janela: densa (GEMV)
        if (fuse) {
            DENSE_CFG(0);
            NPU(0x04) = 0x36;
        } else {
            NPU(0x04) = 0x80;
            DENSE_CFG(stream ? 2u : 0u);
            if (stream) {
                NPU(0x04) = 0x36;
                hal_dma_memcpy((uint32_t)v2_out_words, NPU_BASE_ADDR + 0x14, nwin, 1);
            } else {
                hal_dma_memcpy((uint32_t)v2_out_words, NPU_BASE_ADDR + 0x14, nwin, 1);
                NPU(0x04) = 0x36;
            }
        }
        v2_cpu_read_out(y_words, Td);
        while (!(NPU(0x00) & NPU_STATUS_DONE));
        NPU(0x34) = 0; NPU(0x3C) = 0; NPU(0x20) = 0;
        t3 = V2_NOW();
    }
    #undef CONV_CFG
    #undef DENSE_CFG

    // ---------------------------------------------------------------- Referência na CPU
    uint32_t c0 = V2_NOW();
    v2_ref_cnn(q, ow, oh, Kd, wd_base, sh_c, sh_d);
    uint32_t c1 = V2_NOW();

    uint32_t bad = 0;
    for (uint32_t n = 0; n < q->n; n++)
        if ((int8_t)(y_words[n / 4] >> (8 * (n % 4))) != v2_ref[n]) bad++;

    uint32_t o0 = V2_NOW(), o1 = V2_NOW();
    r->status      = V2_ERR_OK;
    r->cyc_w       = 0;
    r->cyc_in      = t1 - t0;
    r->cyc_exec    = t3 - t1;
    r->cyc_total   = t3 - t0;
    r->cyc_cpu     = (q->flags & V2_F_CPU_REF) ? (c1 - c0) : 0;
    r->mismatches  = bad;
    r->macs_useful = nwin * Kc * 4 + q->n * Kd;
    r->macs_pe     = Tc * Kc * 16 + Td * (Kd / 4) * 16;
    r->words_w     = 0;
    r->words_in    = img_words + (fuse ? 0 : nwin) + (desc ? v2_prog_len : 0);   // programa também trafega
    r->words_out   = (fuse ? 0 : Tc * 4) + Td;
    r->timer_ovh   = o1 - o0;
}

static void bench_v2_experiment(void) {
    v2_req_t q;
    q.kind = uart_read_byte();
    q.flags = (uint16_t)((uart_read_byte() << 8) | uart_read_byte());
    q.sparsity = uart_read_byte(); q.seed = uart_read_byte();
    uint32_t kn = uart_read_u32();
    q.k = (uint16_t)(kn >> 16); q.n = (uint16_t)kn;
    q.in_w = uart_read_byte(); q.in_h = uart_read_byte();
    q.ksz = uart_read_byte(); q.stride = uart_read_byte();

    v2_res_t r = {0};
    if (q.kind == V2_KIND_CNN) v2_run_cnn(&q, &r);
    else                       v2_run(&q, &r);

    const uint32_t* f = (const uint32_t*)&r;
    for (unsigned i = 0; i < sizeof(r) / 4; i++) uart_write_u32(f[i]);
}

int main() {
    hal_uart_init(); 

    while(1) {
        uint8_t cmd = uart_read_byte();

        if (cmd == 'B') {
            uint32_t k_dim = uart_read_u32();       
            uint8_t sparsity = uart_read_byte();    

            if (k_dim > MAX_K_DIM) k_dim = MAX_K_DIM;

            // ------------------------------------------------------------
            // ETAPA 1: Geração de Dados Sintéticos (AGORA 4 VALORES DE 8 BITS POR INDEX)
            // ------------------------------------------------------------
            uint32_t lfsr = 0xACE1u; 
            for(uint32_t i = 0; i < k_dim; i++) {
                lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u); 
                
                if ((lfsr % 100) < sparsity) {
                    buffer_inputs[i] = 0; // Palavra inteira com 4 Zeros
                } else {
                    buffer_inputs[i] = lfsr; // 4 bytes aleatórios empacotados
                }
                buffer_weights[i] = lfsr * 13; // 4 pesos aleatórios
            }

            // ------------------------------------------------------------
            // ETAPA 2: BENCHMARK CPU OTIMIZADO (Unrolled & Register-Focused)
            // ------------------------------------------------------------
            uint64_t t_cpu_start = hal_timer_get_cycles();
            int32_t out0 = 0, out1 = 0, out2 = 0, out3 = 0;

            for (uint32_t k = 0; k < k_dim; k++) {
                uint32_t i_pack = buffer_inputs[k];
                if (i_pack == 0) continue; 
                
                uint32_t w_pack = buffer_weights[k];
                
                // Extraímos os inputs uma única vez para registradores locais
                int8_t i0 = (int8_t)(i_pack & 0xFF);
                int8_t i1 = (int8_t)((i_pack >> 8) & 0xFF);
                int8_t i2 = (int8_t)((i_pack >> 16) & 0xFF);
                int8_t i3 = (int8_t)((i_pack >> 24) & 0xFF);

                // Extraímos os pesos e acumulamos (Simulando o esforço dos 16 MACs)
                // Fizemos o unroll manual para evitar o custo de loops internos (i e w)
                int8_t w0 = (int8_t)(w_pack & 0xFF);
                int8_t w1 = (int8_t)((w_pack >> 8) & 0xFF);
                int8_t w2 = (int8_t)((w_pack >> 16) & 0xFF);
                int8_t w3 = (int8_t)((w_pack >> 24) & 0xFF);

                out0 += (i0 * w0) + (i1 * w0) + (i2 * w0) + (i3 * w0);
                out1 += (i0 * w1) + (i1 * w1) + (i2 * w1) + (i3 * w1);
                out2 += (i0 * w2) + (i1 * w2) + (i2 * w2) + (i3 * w2);
                out3 += (i0 * w3) + (i1 * w3) + (i2 * w3) + (i3 * w3);
            }
            g_cpu_sink[0] = out0; g_cpu_sink[1] = out1; g_cpu_sink[2] = out2; g_cpu_sink[3] = out3;
            uint64_t total_cpu_cycles = hal_timer_get_cycles() - t_cpu_start;

            // ------------------------------------------------------------
            // ETAPA 3: BENCHMARK NPU (100% Capacidade - 16 MACs)
            // ------------------------------------------------------------
            MMIO32(NPU_BASE_ADDR + 0x44) = 1;   
            MMIO32(NPU_BASE_ADDR + 0x40) = 8;   
            MMIO32(NPU_BASE_ADDR + 0x48) = 0;   
            MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

            // ALIMENTAÇÃO GEMM: Manda a palavra de 32-bits intacta! 
            // 4 inputs independentes entram na matriz a cada ciclo de escrita.
            for (uint32_t k = 0; k < k_dim; k++) {
                MMIO32(NPU_BASE_ADDR + 0x14) = buffer_inputs[k]; 
            }

            // MEDIÇÃO
            uint64_t t_npu_start = hal_timer_get_cycles();
            
            MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
            hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, k_dim, 1);
            
            MMIO32(NPU_BASE_ADDR + 0x08) = k_dim; 
            MMIO32(NPU_BASE_ADDR + 0x04) = 0x36; 

            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); 
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); 
            
            uint64_t total_npu_cycles = hal_timer_get_cycles() - t_npu_start;
            
            uint32_t trash;
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            (void)trash;

            // ------------------------------------------------------------
            // ETAPA 4: Resultados
            // ------------------------------------------------------------
            uart_write_u64(total_cpu_cycles);
            uart_write_u64(total_npu_cycles);
        }

        // ------------------------------------------------------------
        // BENCHMARK ENCADEADO (Double Buffering / Ping-Pong)
        // Roda `num_tiles` tiles de GEMM em sequência, uma vez no modo serial
        // (carga -> compute -> drenagem, tudo em série, como hoje) e outra vez
        // no modo pipelined (o próximo tile é carregado nos bancos físicos
        // livres enquanto a NPU ainda está BUSY computando o tile atual).
        // Reporta os dois totais de ciclos via UART para comparação de ganho.
        // ------------------------------------------------------------
        else if (cmd == 'X') {
            bench_v2_experiment();
        }
        else if (cmd == 'P') {
            uint32_t k_dim     = uart_read_u32();
            uint8_t  num_tiles = uart_read_byte();
            uint8_t  sparsity  = uart_read_byte();

            if (k_dim > MAX_K_DIM) k_dim = MAX_K_DIM;

            MMIO32(NPU_BASE_ADDR + 0x44) = 1;
            MMIO32(NPU_BASE_ADDR + 0x40) = 8;
            MMIO32(NPU_BASE_ADDR + 0x48) = 0;

            // --------------------------------------------------------
            // PASSADA 1: SERIAL (baseline) — carga e compute em série, tile a tile.
            // --------------------------------------------------------
            uint64_t t_serial_start = hal_timer_get_cycles();

            for (uint32_t t = 0; t < num_tiles; t++) {
                gen_tile_data(t, k_dim, sparsity);

                MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_W | NPU_CMD_RST_WR_I;

                // Pesos E inputs via DMA: um laço de escrita por CPU (~milhares de
                // ciclos por word num core multi_cycle) dominaria completamente o
                // tempo de cada tile e mascararia qualquer ganho do double buffering
                // — a carga precisa ser rápida o bastante pra ser da mesma ordem de
                // grandeza do cômputo, senão não há o que sobrepor.
                hal_dma_memcpy((uint32_t)buffer_inputs, NPU_BASE_ADDR + 0x14, k_dim, 1);
                hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, k_dim, 1);

                MMIO32(NPU_BASE_ADDR + 0x08) = k_dim;
                MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_START | NPU_CMD_ACC_CLEAR |
                                                NPU_CMD_RST_W_RD | NPU_CMD_RST_I_RD;

                while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_BUSY));
                while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_DONE));

                uint32_t trash;
                for (int r = 0; r < 4; r++) {
                    while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_OUT_VLD));
                    trash = MMIO32(NPU_BASE_ADDR + 0x18);
                }
                (void)trash;
            }

            uint64_t total_serial_cycles = hal_timer_get_cycles() - t_serial_start;

            // --------------------------------------------------------
            // PASSADA 2: PIPELINED (Double Buffering) — o tile N+1 é carregado
            // nos bancos ping-pong enquanto a NPU ainda está BUSY com o tile N.
            // --------------------------------------------------------
            uint64_t t_pipe_start = hal_timer_get_cycles();

            int wr_bank = 0;
            gen_tile_data(0, k_dim, sparsity);
            MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_W | NPU_CMD_RST_WR_I;
            hal_dma_memcpy((uint32_t)buffer_inputs, NPU_BASE_ADDR + 0x14, k_dim, 1);
            hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, k_dim, 1);

            for (uint32_t t = 0; t < num_tiles; t++) {
                MMIO32(NPU_BASE_ADDR + 0x08) = k_dim;
                MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_START | NPU_CMD_ACC_CLEAR |
                                                NPU_CMD_RST_W_RD | NPU_CMD_RST_I_RD |
                                                NPU_CMD_RST_WR_W | NPU_CMD_RST_WR_I |
                                                NPU_CMD_DBUF_EN;
                wr_bank ^= 1; // espelha a troca de banco que o hardware acabou de fazer

                while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_BUSY));

                // Sobrepõe a carga do PRÓXIMO tile com o cômputo do tile atual.
                // Pesos e inputs mudam em TODO tile neste benchmark (GEMM puro),
                // então, ao contrário do cnn_server, não há lado estático pra
                // "primar" uma única vez — os dois bancos recebem dado novo
                // sempre. wr_bank só é usado aqui pra documentar a simetria com
                // o padrão usado em cnn_server.c.
                if (t + 1 < num_tiles) {
                    gen_tile_data(t + 1, k_dim, sparsity);
                    hal_dma_memcpy((uint32_t)buffer_inputs, NPU_BASE_ADDR + 0x14, k_dim, 1);
                    hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, k_dim, 1);
                }

                while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_DONE));

                uint32_t trash;
                for (int r = 0; r < 4; r++) {
                    while (!(MMIO32(NPU_BASE_ADDR + 0x00) & NPU_STATUS_OUT_VLD));
                    trash = MMIO32(NPU_BASE_ADDR + 0x18);
                }
                (void)trash;
            }

            uint64_t total_pipe_cycles = hal_timer_get_cycles() - t_pipe_start;
            (void)wr_bank;

            uart_write_u64(total_serial_cycles);
            uart_write_u64(total_pipe_cycles);
        }
    }
    return 0;
}