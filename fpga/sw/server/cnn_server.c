/**
 * @file cnn_server.c
 * @brief Servidor NPU com Im2Col otimizado (DMA ativado para Conv2D)
 */

#include <stdint.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_dma.h"
#include "hal/hal_gpio.h"

// =========================================================
// ALOCAÇÃO DE MEMÓRIA (PESOS, BIASES E BUFFERS)
// =========================================================
__attribute__((aligned(4))) uint32_t W_conv[9];
__attribute__((aligned(4))) int32_t  B_conv[4];
__attribute__((aligned(4))) uint32_t W_fc[2028];  
__attribute__((aligned(4))) int32_t  B_fc[12];

__attribute__((aligned(4))) int8_t input_image[784];
__attribute__((aligned(4))) int8_t fc_out[10];

// Pesos residentes: cada camada ocupa a sua região na RAM de pesos da NPU (2048 palavras)
// e é gravada uma única vez, quando o modelo chega pela UART. Na inferência, só as entradas
// trafegam pelo barramento; a camada é escolhida pela base (W_BASE, 0x20).
#define W_CONV_BASE 0
#define W_FC_BASE   12                                       // após os 9 pesos da Conv, alinhado a 4 (GEMV lê 4 palavras por vez)

uint32_t uart_read_uint32_be(void) {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 24;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 16;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 8;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 0;
    return val;
}

// =========================================================
// 1. IM2COL EM HARDWARE
// =========================================================
// A NPU recebe a imagem crua (784 pixels = 196 palavras) pela porta IMG (0x1C) e monta
// sozinha as janelas 3x3 com passo 2: em cada START, a linha r do arranjo lê o tap
// corrente da janela 4g+r. As janelas 169..171 (preenchimento do último grupo) leem zero.
#define IM2COL_GEOM ((3u << 20) | (2u << 16) | (13u << 8) | 28u)   // KW | STRIDE | OUT_W | IN_W
#define IM2COL_NWIN 169

// =========================================================
// CARGA DOS PESOS RESIDENTES
// =========================================================
// Grava `words` palavras na RAM de pesos da NPU a partir de `base`: o RST_WR_W (0x40)
// leva o ponteiro de escrita para a base, e o DMA segue dali.
void npu_load_weights(uint32_t base, uint32_t* weights, uint32_t words) {
    MMIO32(NPU_BASE_ADDR + 0x20) = base;
    MMIO32(NPU_BASE_ADDR + 0x04) = 0x40;
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, words, 1);
}

// =========================================================
// 2. BIASES RESIDENTES
// =========================================================
// Cada camada tem o seu banco de bias na NPU, gravado uma única vez na carga do modelo:
// a Conv usa o banco 3 e a densa os bancos 0..2 (um por bloco de 4 neurônios).
#define BIAS_BANK_CONV 3

void npu_load_bias(int bank, const int32_t* bias, int n) {
    for (int i = 0; i < n; i++) {
        MMIO32(NPU_BASE_ADDR + 0x80 + 16 * bank + 4 * i) = (uint32_t)bias[i];
    }
}

// =========================================================
// 3. PROGRAMA DA REDE (DESCRITORES DE CAMADA)
// =========================================================
// A configuração das duas camadas é um programa fixo, executado pelo processador de comandos
// da NPU (porta DESC, 0x0C): a cada imagem, a CPU só envia o programa e a imagem por DMA.
//
// Conv: imagem crua pela porta IMG durante o cômputo (STREAM_I), im2col em hardware, 43 grupos de
//   4 janelas num único START com tiles encadeados (OVERLAP), saída direto na RAM de Inputs (LOOP).
// Densa: GEMV (4 linhas do array), 3 blocos de 4 neurônios encadeados, cada um com o seu banco
//   de bias; lê a saída da Conv já na NPU.
// Epílogo: zera o ponteiro de escrita da imagem para a próxima inferência.
#define D_WR(reg, val) (0x10000000u | (reg)), (uint32_t)(val)
#define D_WAIT         0x20000000u
#define D_END          0x30000000u

static const uint32_t cnn_prog[] __attribute__((aligned(4))) = {
    // ---- Conv2D 3x3, passo 2, 4 filtros, ReLU
    D_WR(0x44, 1), D_WR(0x40, 8), D_WR(0x48, 1),
    D_WR(0x20, W_CONV_BASE), D_WR(0x24, 0),
    D_WR(0x2C, IM2COL_GEOM), D_WR(0x30, IM2COL_NWIN), D_WR(0x28, 1),
    D_WR(0x08, 9),
    D_WR(0x34, 43u | (1u << 16) | ((uint32_t)BIAS_BANK_CONV << 19)),   // TILES, RW_W, banco de bias
    D_WR(0x38, 0x1 | 0x4),                                              // OUT_CFG = ORDER | LOOP
    D_WR(0x3C, 0x2 | 0x8),                                              // MODE = STREAM_I | OVERLAP
    D_WR(0x04, 0x36), D_WAIT,                                           // START, espera
    // ---- Densa 676 -> 10 (GEMV)
    D_WR(0x40, 8), D_WR(0x48, 0), D_WR(0x28, 0),
    D_WR(0x20, W_FC_BASE), D_WR(0x38, 0),
    D_WR(0x3C, 0x1 | 0x8),                                              // MODE = GEMV | OVERLAP
    D_WR(0x08, 676 / 4),
    D_WR(0x34, 3u | (1u << 17) | (1u << 18)),                           // TILES, RW_I, BIAS_PER_TILE
    D_WR(0x04, 0x36), D_WAIT,
    // ---- Epílogo
    D_WR(0x3C, 0), D_WR(0x34, 0), D_WR(0x04, 0x80), D_END,
};

// Uma inferência: programa e imagem por DMA; a leitura da O_DATA espera o resultado (a NPU segura
// o barramento enquanto o programa executa), então não há consulta de status no caminho
void npu_infer(const int8_t* img, int8_t* outputs) {
    hal_dma_memcpy((uint32_t)cnn_prog, NPU_BASE_ADDR + 0x0C, sizeof(cnn_prog) / 4, 1);
    hal_dma_memcpy((uint32_t)img, NPU_BASE_ADDR + 0x1C, 784 / 4, 1);

    for (int chunk = 0; chunk < 3; chunk++) {
        uint32_t res = MMIO32(NPU_BASE_ADDR + 0x18);                    // byte c = neurônio 4j + c
        for (int c = 0; c < 4 && chunk * 4 + c < 10; c++) {
            outputs[chunk * 4 + c] = (int8_t)((res >> (8 * c)) & 0xFF);
        }
    }
    while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 4)));                 // programa terminado
}

// =========================================================
// ROTINA PRINCIPAL (FSM)
// =========================================================
int main(void) {
    hal_uart_init();
    
    hal_leds_write(0xFFFF);
    for (volatile int i = 0; i < 200000; i++); 
    hal_leds_write(0x0000);

    while(1) {
        uint8_t cmd = hal_uart_getc();
        
        if (cmd == 0xAA) {
            for(int i = 0; i < 9; i++) W_conv[i] = uart_read_uint32_be();
            npu_load_weights(W_CONV_BASE, W_conv, 9);
            hal_uart_putc('A'); 
        }
        else if (cmd == 0xBB) {
            for(int i = 0; i < 4; i++) B_conv[i] = (int32_t)uart_read_uint32_be();
            npu_load_bias(BIAS_BANK_CONV, B_conv, 4);
            hal_uart_putc('B');
        }
        else if (cmd == 0xCC) {
            for(int i = 0; i < 2028; i++) W_fc[i] = uart_read_uint32_be();
            npu_load_weights(W_FC_BASE, W_fc, 2028);
            hal_uart_putc('C');
        }
        else if (cmd == 0xDD) {
            for(int i = 0; i < 12; i++) B_fc[i] = (int32_t)uart_read_uint32_be();
            npu_load_bias(0, B_fc, 12);                                     // bancos 0..2
            hal_uart_putc('D');
        }
        else if (cmd == 0xFF) {
            for(int i = 0; i < 784; i++) input_image[i] = (int8_t)hal_uart_getc();

            hal_leds_write(0x0000);

            // 1. Conv2D + densa: um programa de descritores e a imagem, por DMA
            npu_infer(input_image, fc_out);

            // 2. Argmax e devolução dos resultados
            int8_t max_logit = -128;
            int predicted_digit = 0;
            
            for(int i = 0; i < 10; i++) {
                if (fc_out[i] > max_logit) { max_logit = fc_out[i]; predicted_digit = i; }
                hal_uart_putc((char)fc_out[i]);
            }
            hal_leds_write(1 << predicted_digit);                       // LED do dígito previsto
            hal_seg7_write_dec(predicted_digit);                        // e o dígito no display
        }
    }
    return 0;
}