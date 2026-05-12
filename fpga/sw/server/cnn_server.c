/**
 * @file conv2d_server.c
 * @brief Servidor NPU com Im2Col para acelerar Conv2D usando 100% da matriz 4x4
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

// Camada 1: Conv2D (1 Canal In, 4 Canais Out, Kernel 3x3)
// in_features = 9 pixels por patch. out_features = 4 filtros.
__attribute__((aligned(4))) uint32_t W_conv[9];   // 9 palavras empacotadas (cada uma tem os 4 filtros)
__attribute__((aligned(4))) int32_t  B_conv[4];   // 4 biases para os 4 filtros

// Camada 2: Fully Connected (Flatten -> 10 Classes)
// Flattened: 13 * 13 patches * 4 canais = 676 neurónios de entrada. Saída = 10 classes.
// Empacotamento: ceil(10/4) = 3 chunks. 3 chunks * 676 in_features = 2028 words.
__attribute__((aligned(4))) uint32_t W_fc[2028];  
__attribute__((aligned(4))) int32_t  B_fc[12];    // 10 classes, com padding para 12 (múltiplo de 4)

// Buffers de Dados (Entradas, Intermédios e Saídas)
__attribute__((aligned(4))) int8_t input_image[784];      // Imagem original (28x28)
__attribute__((aligned(4))) int8_t patches[172][9];       // 169 patches + 3 de padding = 172 patches (múltiplo de 4)
__attribute__((aligned(4))) int8_t conv_out[172 * 4];     // Saída da Conv (172 patches * 4 filtros)
__attribute__((aligned(4))) int8_t fc_out[10];            // Logits finais

// Função auxiliar para ler palavras de 32-bits via UART
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
    // Imagem 28x28. Janela de 3x3. Stride de 2.
    // Resulta numa grelha de saída de 13x13 (169 patches)
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
    // Preenchimento (Padding) com zeros para que o número de patches seja múltiplo de 4
    for(; p < 172; p++) {
        for(int i = 0; i < 9; i++) patch_matrix[p][i] = 0;
    }
}

// =========================================================
// 2. INFERÊNCIA DA CONV2D (EFICIÊNCIA DE 100%)
// =========================================================
void npu_run_conv(uint32_t* weights, int32_t* biases, int8_t in_patches[][9], int8_t* out_acts) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;   // Multiplicador da quantização
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;   // Shift da quantização
    MMIO32(NPU_BASE_ADDR + 0x48) = 1;   // Ativar ReLU para a Conv2D

    // Configurar biases dos 4 filtros
    for (int b = 0; b < 4; b++) {
        MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[b];
    }

    // Carregar os 9 pesos via DMA (uma vez para toda a convolução)
    MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, 9, 1);

    // Processar os patches de 4 em 4 usando as 4 linhas da NPU
    for (int p = 0; p < 172; p += 4) {
        
        MMIO32(NPU_BASE_ADDR + 0x08) = 9;    // 9 pixels por patch
        MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; // Reset & Clear ACC

        // Alimentar as 4 linhas da NPU simultaneamente
        for (int k = 0; k < 9; k++) {
            uint32_t packed_in = 0;
            packed_in |= ((uint32_t)in_patches[p+3][k] & 0xFF) << 24; // Linha 3 = Patch 3
            packed_in |= ((uint32_t)in_patches[p+2][k] & 0xFF) << 16; // Linha 2 = Patch 2
            packed_in |= ((uint32_t)in_patches[p+1][k] & 0xFF) << 8;  // Linha 1 = Patch 1
            packed_in |= ((uint32_t)in_patches[p+0][k] & 0xFF) << 0;  // Linha 0 = Patch 0
            MMIO32(NPU_BASE_ADDR + 0x14) = packed_in; 
        }

        MMIO32(NPU_BASE_ADDR + 0x04) = 0x36; // START MAC

        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); // Wait BUSY
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); // Wait DONE
        
        // Ler os resultados das 4 janelas. No arranjo sistólico com shift down, 
        // a linha inferior (Linha 3) sai primeiro do acumulador.
        for (int r = 3; r >= 0; r--) {
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); 
            uint32_t valid_res = MMIO32(NPU_BASE_ADDR + 0x18);
            
            out_acts[(p + r) * 4 + 0] = (int8_t)((valid_res >> 0)  & 0xFF); // Filtro 0
            out_acts[(p + r) * 4 + 1] = (int8_t)((valid_res >> 8)  & 0xFF); // Filtro 1
            out_acts[(p + r) * 4 + 2] = (int8_t)((valid_res >> 16) & 0xFF); // Filtro 2
            out_acts[(p + r) * 4 + 3] = (int8_t)((valid_res >> 24) & 0xFF); // Filtro 3
        }
    }
}

// =========================================================
// 3. INFERÊNCIA FULLY CONNECTED CLÁSSICA (EFICIÊNCIA DE 25%)
// =========================================================
void npu_run_fc(uint32_t* weights, int32_t* biases, int8_t* inputs, int8_t* outputs, int in_feat, int out_feat) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;   
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;  
    MMIO32(NPU_BASE_ADDR + 0x48) = 0; // Desativar ReLU na saída

    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

    // Enviar todas as ativações (apenas para a Linha 0)
    for (int k = 0; k < in_feat; k++) {
        MMIO32(NPU_BASE_ADDR + 0x14) = inputs[k] & 0xFF; 
    }

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
        // As 3 linhas de baixo não têm dados úteis neste modo
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
            // Recebe 1 única imagem de 28x28 (latência otimizada)
            for(int i = 0; i < 784; i++) input_image[i] = (int8_t)hal_uart_getc();

            REG_LEDS = 0x0000;

            // 1. Recortar a imagem em 169 patches + padding
            image_to_columns(input_image, patches);
            
            // 2. Executar a Conv2D em 4x4 (Vazão altíssima)
            npu_run_conv(W_conv, B_conv, patches, conv_out);
            
            // 3. Executar a Camada FC final
            // Passamos apenas os 676 neurónios úteis (169 patches * 4 canais)
            npu_run_fc(W_fc, B_fc, conv_out, fc_out, 676, 10);

            // 4. Argmax e devolução dos resultados
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