/**
 * @file cnn_server.c
 * @brief Servidor NPU com Im2Col otimizado (DMA ativado para Conv2D)
 */

#include <stdint.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_dma.h"

// =========================================================
// DEFINIÇÕES DE HARDWARE E PERIFÉRICOS
// =========================================================
#define GPIO_BASE  0x20000000
#define REG_LEDS   (*(volatile uint32_t *)(GPIO_BASE + 0x00))

// =========================================================
// ALOCAÇÃO DE MEMÓRIA (PESOS, BIASES E BUFFERS)
// =========================================================
__attribute__((aligned(4))) uint32_t W_conv[9];
__attribute__((aligned(4))) int32_t  B_conv[4];
__attribute__((aligned(4))) uint32_t W_fc[2028];  
__attribute__((aligned(4))) int32_t  B_fc[12];

__attribute__((aligned(4))) int8_t input_image[784];
__attribute__((aligned(4))) uint32_t patches_packed[43][9];  // entradas da Conv no formato da NPU (43 grupos x 9 palavras)
__attribute__((aligned(4))) uint32_t fc_in_words[172 * 4];   // saídas da Conv = entradas da densa (1 ativação por palavra)
__attribute__((aligned(4))) int8_t fc_out[10];

uint32_t uart_read_uint32_be(void) {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 24;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 16;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 8;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 0;
    return val;
}

// =========================================================
// 1. IM2COL + EMPACOTAMENTO NUMA ÚNICA PASSADA
// =========================================================
// Monta, direto da imagem, as palavras que a NPU consome na Conv2D: a palavra k do
// grupo g traz o pixel k das janelas 4g..4g+3 (byte r = janela 4g+r = linha r do arranjo).
// Janelas 3x3 com passo 2: a janela p = 13u + v começa no pixel (2u, 2v) da imagem 28x28.
// As janelas 169..171 (preenchimento) apontam para um bloco de zeros.
static const int8_t zeros[64];
static const uint8_t k_off[9] = { 0, 1, 2, 28, 29, 30, 56, 57, 58 };

void image_to_packed(const int8_t* img, uint32_t packed[][9]) {
    int u = 0, v = 0;
    for (int g = 0; g < 43; g++) {
        const int8_t* q[4];
        for (int r = 0; r < 4; r++) {
            if (u < 13) {
                q[r] = img + 56 * u + 2 * v;
                if (++v == 13) { v = 0; u++; }
            } else {
                q[r] = zeros;
            }
        }
        for (int k = 0; k < 9; k++) {
            int o = k_off[k];
            packed[g][k] = ((uint32_t)(uint8_t)q[0][o])
                         | ((uint32_t)(uint8_t)q[1][o] << 8)
                         | ((uint32_t)(uint8_t)q[2][o] << 16)
                         | ((uint32_t)(uint8_t)q[3][o] << 24);
        }
    }
}

// =========================================================
// 2. INFERÊNCIA DA CONV2D (Otimizada via DMA)
// =========================================================
void npu_run_conv(uint32_t* weights, int32_t* biases, uint32_t in_packed[][9], uint32_t* out_words) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;
    MMIO32(NPU_BASE_ADDR + 0x48) = 1;

    // Configurar biases
    for (int b = 0; b < 4; b++) {
        MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[b];
    }

    // Pesos (9 palavras) e entradas dos 43 blocos (43 x 9 = 387 palavras) vão para
    // as memórias locais da NPU em apenas duas transferências de DMA.
    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1;   // zera os ponteiros de escrita
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, 9, 1);
    hal_dma_memcpy((uint32_t)in_packed, NPU_BASE_ADDR + 0x14, 43 * 9, 1);

    MMIO32(NPU_BASE_ADDR + 0x08) = 9;      // K = 9 palavras por passagem

    // Processar os 43 blocos de patches (172 patches / 4)
    for (int block = 0; block < 43; block++) {
        // START + ACC_CLEAR + reinício da leitura dos pesos: os mesmos 9 pesos são
        // relidos a cada bloco, e o ponteiro de leitura das entradas segue para as
        // 9 palavras do bloco seguinte. No primeiro bloco, as duas leituras começam do zero.
        MMIO32(NPU_BASE_ADDR + 0x04) = (block == 0) ? 0x36 : 0x16;

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0)));
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1)));

        int p = block * 4;
        for (int r = 3; r >= 0; r--) {
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3)));
            uint32_t valid_res = MMIO32(NPU_BASE_ADDR + 0x18);
            // Canal j da janela p+r, já como palavra: é o formato que a densa envia por DMA.

            out_words[(p + r) * 4 + 0] = (valid_res >> 0) & 0xFF;
            out_words[(p + r) * 4 + 1] = (valid_res >> 8) & 0xFF;
            out_words[(p + r) * 4 + 2] = (valid_res >> 16) & 0xFF;
            out_words[(p + r) * 4 + 3] = (valid_res >> 24) & 0xFF;
        }
    }
}

// =========================================================
// 3. INFERÊNCIA FULLY CONNECTED CLÁSSICA (entradas via DMA)
// =========================================================
void npu_run_fc(uint32_t* weights, int32_t* biases, uint32_t* in_words, int8_t* outputs, int in_feat, int out_feat) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;
    MMIO32(NPU_BASE_ADDR + 0x48) = 0;

    int num_chunks = (out_feat + 3) / 4;

    // Entradas (uma ativação por palavra, gravadas pela Conv) e pesos dos blocos de 4 neurônios
    // (num_chunks x in_feat palavras) vão para a NPU em apenas duas transferências de DMA.
    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1;   // zera os ponteiros de escrita
    hal_dma_memcpy((uint32_t)in_words, NPU_BASE_ADDR + 0x14, in_feat, 1);
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, num_chunks * in_feat, 1);

    MMIO32(NPU_BASE_ADDR + 0x08) = in_feat;

    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start = chunk * 4;
        int chunk_size = (out_feat - chunk_start < 4) ? (out_feat - chunk_start) : 4;

        for (int b = 0; b < 4; b++) {
            if (b < chunk_size) MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[chunk_start + b];
            else MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = 0;
        }

        // START + ACC_CLEAR + reinício da leitura das entradas: as mesmas ativações são
        // relidas a cada bloco, e o ponteiro de leitura dos pesos segue para o bloco de
        // neurônios seguinte. No primeiro bloco, as duas leituras começam do zero.
        MMIO32(NPU_BASE_ADDR + 0x04) = (chunk == 0) ? 0x36 : 0x26;

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0)));
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1)));

        uint32_t trash, valid_res;
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        (void)trash;

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); valid_res = MMIO32(NPU_BASE_ADDR + 0x18);

        if (chunk_size > 0) outputs[chunk_start + 0] = (int8_t)((valid_res >> 0)  & 0xFF);
        if (chunk_size > 1) outputs[chunk_start + 1] = (int8_t)((valid_res >> 8)  & 0xFF);
        if (chunk_size > 2) outputs[chunk_start + 2] = (int8_t)((valid_res >> 16) & 0xFF);
        if (chunk_size > 3) outputs[chunk_start + 3] = (int8_t)((valid_res >> 24) & 0xFF);
    }
}

// =========================================================
// ROTINA PRINCIPAL (FSM)
// =========================================================
int main(void) {
    hal_uart_init();
    
    REG_LEDS = 0xFFFF;
    for (volatile int i = 0; i < 200000; i++); 
    REG_LEDS = 0x0000;

    while(1) {
        uint8_t cmd = hal_uart_getc();
        
        if (cmd == 0xAA) {
            for(int i = 0; i < 9; i++) W_conv[i] = uart_read_uint32_be();
            hal_uart_putc('A'); 
        }
        else if (cmd == 0xBB) {
            for(int i = 0; i < 4; i++) B_conv[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('B');
        }
        else if (cmd == 0xCC) {
            for(int i = 0; i < 2028; i++) W_fc[i] = uart_read_uint32_be();
            hal_uart_putc('C');
        }
        else if (cmd == 0xDD) {
            for(int i = 0; i < 12; i++) B_fc[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('D');
        }
        else if (cmd == 0xFF) {
            for(int i = 0; i < 784; i++) input_image[i] = (int8_t)hal_uart_getc();

            REG_LEDS = 0x0000;

            // 1. Recortar a imagem em 169 patches + padding
            image_to_packed(input_image, patches_packed);
            
            
            // 3. Executar a Conv2D em 4x4 (Alimentada por DMA!)
            npu_run_conv(W_conv, B_conv, patches_packed, fc_in_words);
            
            // 4. Executar a Camada FC final
            npu_run_fc(W_fc, B_fc, fc_in_words, fc_out, 676, 10);

            // 5. Argmax e devolução dos resultados
            int8_t max_logit = -128;
            int predicted_digit = 0;
            
            for(int i = 0; i < 10; i++) {
                if (fc_out[i] > max_logit) { max_logit = fc_out[i]; predicted_digit = i; }
                hal_uart_putc((char)fc_out[i]);
            }
            REG_LEDS = (1 << predicted_digit);
        }
    }
    return 0;
}