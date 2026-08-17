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
__attribute__((aligned(4))) int8_t input_image[784];      // Imagem original (28x28) — modo de imagem única (0xFF)
__attribute__((aligned(4))) int8_t patches[172][9];       // 169 patches + 3 de padding = 172 patches (múltiplo de 4)
__attribute__((aligned(4))) int8_t conv_out[172 * 4];     // Saída da Conv (172 patches * 4 filtros)
__attribute__((aligned(4))) int8_t fc_out[10];            // Logits finais

// Buffer auxiliar para "expandir" as ativações int8 (1 byte útil por word, Linha 0)
// em SRAM local antes de mandar por DMA — ver npu_run_fc().
#define MAX_FC_IN_FEAT 676
__attribute__((aligned(4))) uint32_t fc_input_words[MAX_FC_IN_FEAT];

// Double Buffering de imagens (modo batch, comando 0xEE): enquanto o SoC classifica
// a imagem em um destes bancos, o host já pode estar enviando a próxima imagem para
// o outro — mesmo princípio de ping-pong usado dentro da NPU, só que em nível de
// imagem/host em vez de nível de tile/scratchpad.
__attribute__((aligned(4))) int8_t image_buf_a[784];
__attribute__((aligned(4))) int8_t image_buf_b[784];

// Estado da recepção oportunista da PRÓXIMA imagem: consumido a partir dos laços de
// espera do NPU (macro WAIT_NPU, dentro de npu_run_conv/npu_run_fc) enquanto o SoC
// ainda está ocupado com a imagem atual. s_next_target fica em 0 fora do modo batch,
// então uart_rx_pump() não faz nada no caminho de imagem única (0xFF) — custo zero.
static int8_t *s_next_buf    = 0;
static int     s_next_fill   = 0;
static int     s_next_target = 0;

static void uart_rx_pump(void) {
    if (s_next_fill < s_next_target && hal_uart_kbhit()) {
        s_next_buf[s_next_fill++] = (int8_t)hal_uart_getc();
    }
}

// Espera um bit de STATUS da NPU, "vazando" a recepção da próxima imagem (se houver)
// para dentro do laço de espera em vez de ficar parado.
#define WAIT_NPU(FLAG) while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (FLAG))) { uart_rx_pump(); }

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

    // Double Buffering (Ping-Pong): os pesos são os MESMOS para todos os grupos de
    // patches, mas o banco físico de pesos troca junto com o de inputs a cada START
    // com DBUF_EN (seletor de banco único, compartilhado no Datapath). Por isso os
    // pesos são "primados" nos dois bancos físicos (uma vez cada) em vez de
    // reenviados a cada grupo — só os inputs (que mudam a cada grupo) precisam ser
    // escritos de novo, sobrepostos ao BUSY do grupo anterior.
    uint8_t weights_primed[2] = { 0, 0 };
    int wr_bank = 0;

    // Buffer local pro empacotamento dos inputs de um grupo (4 patches x 9 pixels
    // -> 9 words). Empacotar em SRAM local e mandar via DMA, em vez de escrever
    // cada word direto por MMIO num laço de CPU: um store individual pro barramento
    // custa ~milhares de ciclos num core multi_cycle, o que sozinho já dominaria o
    // tempo do grupo inteiro (o cômputo de 9 ciclos de MAC é rápido demais pra
    // esconder isso atrás) e mascararia o ganho do double buffering.
    uint32_t packed_group[9];

    MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_W;
    hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, 9, 1);
    weights_primed[0] = 1;

    // Primeiro grupo de patches (0..3), escrito antes do loop para "encher o cano"
    MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_I;
    for (int k = 0; k < 9; k++) {
        packed_group[k]  = ((uint32_t)in_patches[3][k] & 0xFF) << 24;
        packed_group[k] |= ((uint32_t)in_patches[2][k] & 0xFF) << 16;
        packed_group[k] |= ((uint32_t)in_patches[1][k] & 0xFF) << 8;
        packed_group[k] |= ((uint32_t)in_patches[0][k] & 0xFF) << 0;
    }
    hal_dma_memcpy((uint32_t)packed_group, NPU_BASE_ADDR + 0x14, 9, 1);

    const int num_groups = 172 / 4;

    // Processar os patches de 4 em 4 usando as 4 linhas da NPU
    for (int g = 0; g < num_groups; g++) {
        int p = g * 4;

        MMIO32(NPU_BASE_ADDR + 0x08) = 9;    // 9 pixels por patch
        MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_START | NPU_CMD_ACC_CLEAR | NPU_CMD_RST_W_RD |
                                        NPU_CMD_RST_I_RD | NPU_CMD_RST_WR_W | NPU_CMD_RST_WR_I |
                                        NPU_CMD_DBUF_EN;
        wr_bank ^= 1; // espelha a troca de banco que o hardware acabou de fazer

        WAIT_NPU(NPU_STATUS_BUSY);

        // Sobrepõe a carga do PRÓXIMO grupo com o cômputo do grupo atual
        if (g + 1 < num_groups) {
            if (!weights_primed[wr_bank]) {
                hal_dma_memcpy((uint32_t)weights, NPU_BASE_ADDR + 0x10, 9, 1);
                weights_primed[wr_bank] = 1;
            }

            int p_next = p + 4;
            for (int k = 0; k < 9; k++) {
                packed_group[k]  = ((uint32_t)in_patches[p_next+3][k] & 0xFF) << 24; // Linha 3 = Patch 3
                packed_group[k] |= ((uint32_t)in_patches[p_next+2][k] & 0xFF) << 16; // Linha 2 = Patch 2
                packed_group[k] |= ((uint32_t)in_patches[p_next+1][k] & 0xFF) << 8;  // Linha 1 = Patch 1
                packed_group[k] |= ((uint32_t)in_patches[p_next+0][k] & 0xFF) << 0;  // Linha 0 = Patch 0
            }
            hal_dma_memcpy((uint32_t)packed_group, NPU_BASE_ADDR + 0x14, 9, 1);
        }

        WAIT_NPU(NPU_STATUS_DONE);

        // Ler os resultados das 4 janelas. No arranjo sistólico com shift down,
        // a linha inferior (Linha 3) sai primeiro do acumulador.
        for (int r = 3; r >= 0; r--) {
            WAIT_NPU(NPU_STATUS_OUT_VLD);
            uint32_t valid_res = MMIO32(NPU_BASE_ADDR + 0x18);

            out_acts[(p + r) * 4 + 0] = (int8_t)((valid_res >> 0)  & 0xFF); // Filtro 0
            out_acts[(p + r) * 4 + 1] = (int8_t)((valid_res >> 8)  & 0xFF); // Filtro 1
            out_acts[(p + r) * 4 + 2] = (int8_t)((valid_res >> 16) & 0xFF); // Filtro 2
            out_acts[(p + r) * 4 + 3] = (int8_t)((valid_res >> 24) & 0xFF); // Filtro 3
        }
    }
}

// Expande as ativações int8 (1 byte útil por word, Linha 0) para SRAM local e manda
// via DMA de uma vez. Evita um laço de CPU com um MMIO store por ativação — um store
// individual pro barramento custa ~milhares de ciclos num core multi_cycle, o que
// para in_feat=676 vira dezenas de milhões de ciclos (~centenas de ms) só pra "primar"
// um banco, dominando completamente a latência de inferência.
static void fc_prime_inputs(int8_t* inputs, int in_feat) {
    if (in_feat > MAX_FC_IN_FEAT) in_feat = MAX_FC_IN_FEAT;
    for (int k = 0; k < in_feat; k++) {
        fc_input_words[k] = (uint32_t)inputs[k] & 0xFF;
    }
    hal_dma_memcpy((uint32_t)fc_input_words, NPU_BASE_ADDR + 0x14, in_feat, 1);
}

// =========================================================
// 3. INFERÊNCIA FULLY CONNECTED CLÁSSICA (EFICIÊNCIA DE 25%)
// =========================================================
void npu_run_fc(uint32_t* weights, int32_t* biases, int8_t* inputs, int8_t* outputs, int in_feat, int out_feat) {
    MMIO32(NPU_BASE_ADDR + 0x44) = 1;
    MMIO32(NPU_BASE_ADDR + 0x40) = 8;
    MMIO32(NPU_BASE_ADDR + 0x48) = 0; // Desativar ReLU na saída

    // Double Buffering (Ping-Pong): as ativações são as MESMAS para todos os chunks de
    // saída, mas o banco físico de inputs troca junto com o de pesos a cada START com
    // DBUF_EN (seletor de banco único, compartilhado no Datapath). Por isso as ativações
    // são "primadas" nos dois bancos físicos (uma vez cada) em vez de reenviadas a cada
    // chunk — só os pesos do PRÓXIMO chunk precisam ser carregados via DMA, sobrepostos
    // ao BUSY do chunk atual.
    uint8_t input_primed[2] = { 0, 0 };
    int wr_bank = 0;

    MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_W;
    hal_dma_memcpy((uint32_t)(&weights[0]), NPU_BASE_ADDR + 0x10, in_feat, 1);

    // Enviar todas as ativações (apenas para a Linha 0), uma vez por banco físico
    MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_RST_WR_I;
    fc_prime_inputs(inputs, in_feat);
    input_primed[0] = 1;

    int num_chunks = (out_feat + 3) / 4;
    int chunk_idx = 0;

    for (int chunk_start = 0; chunk_start < out_feat; chunk_start += 4, chunk_idx++) {

        int chunk_size = (out_feat - chunk_start < 4) ? (out_feat - chunk_start) : 4;

        for (int b = 0; b < 4; b++) {
            if (b < chunk_size) MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[chunk_start + b];
            else MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = 0;
        }

        MMIO32(NPU_BASE_ADDR + 0x08) = in_feat;
        MMIO32(NPU_BASE_ADDR + 0x04) = NPU_CMD_START | NPU_CMD_ACC_CLEAR | NPU_CMD_RST_W_RD |
                                        NPU_CMD_RST_I_RD | NPU_CMD_RST_WR_W | NPU_CMD_RST_WR_I |
                                        NPU_CMD_DBUF_EN;
        wr_bank ^= 1; // espelha a troca de banco que o hardware acabou de fazer

        WAIT_NPU(NPU_STATUS_BUSY);

        // Sobrepõe a carga dos pesos do PRÓXIMO chunk com o cômputo do chunk atual
        if (chunk_idx + 1 < num_chunks) {
            uint32_t src_addr = (uint32_t)(&weights[(chunk_idx + 1) * in_feat]);
            hal_dma_memcpy(src_addr, NPU_BASE_ADDR + 0x10, in_feat, 1);

            if (!input_primed[wr_bank]) {
                fc_prime_inputs(inputs, in_feat);
                input_primed[wr_bank] = 1;
            }
        }

        WAIT_NPU(NPU_STATUS_DONE);

        uint32_t trash, valid_res;
        // As 3 linhas de baixo não têm dados úteis neste modo
        WAIT_NPU(NPU_STATUS_OUT_VLD); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        WAIT_NPU(NPU_STATUS_OUT_VLD); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        WAIT_NPU(NPU_STATUS_OUT_VLD); trash = MMIO32(NPU_BASE_ADDR + 0x18);
        (void)trash;

        WAIT_NPU(NPU_STATUS_OUT_VLD); valid_res = MMIO32(NPU_BASE_ADDR + 0x18);

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
        else if (cmd == 0xEE) {
            // ------------------------------------------------------------
            // MODO BATCH (Double Buffering em nível de imagem)
            // ------------------------------------------------------------
            // Protocolo: 0xEE, num_images (u16 BE), depois num_images * 784 bytes
            // de pixel, um lote atrás do outro, sem espera entre eles. Enquanto o
            // SoC classifica a imagem em cur_buf, a próxima imagem já vai
            // enchendo pend_buf via uart_rx_pump() (chamada de dentro dos laços
            // WAIT_NPU em npu_run_conv/npu_run_fc). Ao final de cada imagem, os
            // buffers trocam de papel (ping-pong), igual ao double buffering já
            // usado dentro da NPU para pesos/inputs.
            uint16_t num_images = ((uint16_t)hal_uart_getc() << 8) | (uint16_t)hal_uart_getc();

            int8_t *cur_buf  = image_buf_a;
            int8_t *pend_buf = image_buf_b;

            if (num_images > 0) {
                // Primeira imagem: nada rodando ainda pra sobrepor, recepção simples.
                for (int b = 0; b < 784; b++) cur_buf[b] = (int8_t)hal_uart_getc();
            }

            for (uint16_t i = 0; i < num_images; i++) {
                int has_next = (i + 1 < num_images);

                // Arma a recepção oportunista da PRÓXIMA imagem para acontecer
                // durante o cômputo desta.
                s_next_buf    = pend_buf;
                s_next_fill   = 0;
                s_next_target = has_next ? 784 : 0;

                image_to_columns(cur_buf, patches);
                npu_run_conv(W_conv, B_conv, patches, conv_out);
                npu_run_fc(W_fc, B_fc, conv_out, fc_out, 676, 10);

                // Se a próxima imagem ainda não terminou de chegar durante o
                // cômputo (host mais lento que a NPU), termina de recebê-la
                // agora — ainda correto, só sem sobreposição total.
                while (s_next_fill < s_next_target) {
                    pend_buf[s_next_fill++] = (int8_t)hal_uart_getc();
                }
                s_next_target = 0;

                int8_t max_logit = -128;
                int predicted_digit = 0;
                for (int k = 0; k < 10; k++) {
                    if (fc_out[k] > max_logit) { max_logit = fc_out[k]; predicted_digit = k; }
                    hal_uart_putc((char)fc_out[k]);
                }
                REG_LEDS = (1 << predicted_digit);

                int8_t *tmp = cur_buf;
                cur_buf  = pend_buf;
                pend_buf = tmp;
            }
        }
    }
    return 0;
}