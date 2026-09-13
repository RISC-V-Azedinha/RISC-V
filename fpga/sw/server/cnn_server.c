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
__attribute__((aligned(4))) int8_t patches[172][9];
__attribute__((aligned(4))) uint32_t patches_packed[43][9]; 
__attribute__((aligned(4))) int8_t conv_out[172 * 4];
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
// 1. EXTRAÇÃO DE PATCHES (IM2COL)
// =========================================================
void image_to_columns(int8_t* img, int8_t patch_matrix[][9]) {
    int p = 0;
    for (int y = 0; y <= 28 - 3; y += 2) {
        for (int x = 0; x <= 28 - 3; x += 2) {
            patch_matrix[p][0] = img[(y+0)*28 + x+0];
            patch_matrix[p][1] = img[(y+0)*28 + x+1];
            patch_matrix[p][2] = img[(y+0)*28 + x+2];
            patch_matrix[p][3] = img[(y+1)*28 + x+0];
            patch_matrix[p][4] = img[(y+1)*28 + x+1];
            patch_matrix[p][5] = img[(y+1)*28 + x+2];
            patch_matrix[p][6] = img[(y+2)*28 + x+0];
            patch_matrix[p][7] = img[(y+2)*28 + x+1];
            patch_matrix[p][8] = img[(y+2)*28 + x+2];
            p++;
        }
    }
    for(; p < 172; p++) {
        for(int i = 0; i < 9; i++) patch_matrix[p][i] = 0;
    }
}

// =========================================================
// NOVO: EMPACOTAMENTE PARA O DMA (32-bits alinhado)
// =========================================================
void pack_patches_for_dma(int8_t patch_matrix[][9], uint32_t packed_matrix[][9]) {
    for (int p = 0; p < 172; p += 4) {
        int block = p / 4;
        for (int k = 0; k < 9; k++) {
            uint32_t packed = 0;
            // Empacota as 4 linhas em uma palavra de 32 bits (Little Endian)
            packed |= ((uint32_t)patch_matrix[p+3][k] & 0xFF) << 24; 
            packed |= ((uint32_t)patch_matrix[p+2][k] & 0xFF) << 16; 
            packed |= ((uint32_t)patch_matrix[p+1][k] & 0xFF) << 8;  
            packed |= ((uint32_t)patch_matrix[p+0][k] & 0xFF) << 0;  
            packed_matrix[block][k] = packed;
        }
    }
}

// =========================================================
// 2. INFERÊNCIA DA CONV2D (Otimizada via DMA)
// =========================================================
void npu_run_conv(uint32_t* weights, int32_t* biases, uint32_t in_packed[][9], int8_t* out_acts) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;   
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;   
    MMIO32(NPU_BASE_ADDR + 0x48) = 1;   

    // Configurar biases
    for (int b = 0; b < 4; b++) {
        MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[b];
    }

    // Carregar pesos via DMA
    MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, 9, 1);

    // Processar os 43 blocos de patches (172 patches / 4)
    for (int block = 0; block < 43; block++) {
        
        MMIO32(NPU_BASE_ADDR + 0x08) = 9;    
        MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

        // NOVO: CPU repassa a transferência de ativações ao DMA (Destino Fixo = 1)
        hal_dma_memcpy((uint32_t)in_packed[block], NPU_BASE_ADDR + 0x14, 9, 1);

        MMIO32(NPU_BASE_ADDR + 0x04) = 0x36; 

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); 
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); 
        
        int p = block * 4;
        for (int r = 3; r >= 0; r--) {
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); 
            uint32_t valid_res = MMIO32(NPU_BASE_ADDR + 0x18);
            
            out_acts[(p + r) * 4 + 0] = (int8_t)((valid_res >> 0)  & 0xFF);
            out_acts[(p + r) * 4 + 1] = (int8_t)((valid_res >> 8)  & 0xFF);
            out_acts[(p + r) * 4 + 2] = (int8_t)((valid_res >> 16) & 0xFF);
            out_acts[(p + r) * 4 + 3] = (int8_t)((valid_res >> 24) & 0xFF);
        }
    }
}

// =========================================================
// 3. INFERÊNCIA FULLY CONNECTED CLÁSSICA (entradas via DMA)
// =========================================================
// Uma ativação por palavra (byte 0 = linha 0 do arranjo), montadas na RAM e
// enviadas à porta de entradas em uma única transferência de DMA.
__attribute__((aligned(4))) uint32_t fc_in_words[676];

void npu_run_fc(uint32_t* weights, int32_t* biases, int8_t* inputs, int8_t* outputs, int in_feat, int out_feat) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;
    MMIO32(NPU_BASE_ADDR + 0x48) = 0;

    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1;

    for (int k = 0; k < in_feat; k++) {
        fc_in_words[k] = (uint32_t)inputs[k] & 0xFF;
    }
    hal_dma_memcpy((uint32_t)fc_in_words, NPU_BASE_ADDR + 0x14, in_feat, 1);

    int chunk_idx = 0;
    for (int chunk_start = 0; chunk_start < out_feat; chunk_start += 4) {
        
        int chunk_size = (out_feat - chunk_start < 4) ? (out_feat - chunk_start) : 4;

        for (int b = 0; b < 4; b++) {
            if (b < chunk_size) MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[chunk_start + b];
            else MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = 0; 
        }

        MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
        uint32_t src_addr = (uint32_t)(&weights[chunk_idx * in_feat]);
        hal_dma_memcpy(src_addr, NPU_BASE_ADDR + 0x10, in_feat, 1);

        MMIO32(NPU_BASE_ADDR + 0x08) = in_feat; 
        MMIO32(NPU_BASE_ADDR + 0x04) = 0x36;        

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); 
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); 

        uint32_t trash, valid_res;
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); valid_res = MMIO32(NPU_BASE_ADDR + 0x18);

        if (chunk_size > 0) outputs[chunk_start + 0] = (int8_t)((valid_res >> 0)  & 0xFF);
        if (chunk_size > 1) outputs[chunk_start + 1] = (int8_t)((valid_res >> 8)  & 0xFF);
        if (chunk_size > 2) outputs[chunk_start + 2] = (int8_t)((valid_res >> 16) & 0xFF);
        if (chunk_size > 3) outputs[chunk_start + 3] = (int8_t)((valid_res >> 24) & 0xFF);

        chunk_idx++;
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
            image_to_columns(input_image, patches);
            
            // 2. Pré-empacotar os patches na RAM no formato da NPU
            pack_patches_for_dma(patches, patches_packed);
            
            // 3. Executar a Conv2D em 4x4 (Alimentada por DMA!)
            npu_run_conv(W_conv, B_conv, patches_packed, conv_out);
            
            // 4. Executar a Camada FC final
            npu_run_fc(W_fc, B_fc, conv_out, fc_out, 676, 10);

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