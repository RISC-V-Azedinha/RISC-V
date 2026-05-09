#include <stdint.h>
#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_dma.h"

__attribute__((aligned(4))) uint32_t W1_packed[25088]; 
__attribute__((aligned(4))) int32_t  B1[128];
__attribute__((aligned(4))) uint32_t W2_packed[384]; 
__attribute__((aligned(4))) int32_t  B2[12]; 

__attribute__((aligned(4))) int8_t input_image[784];
__attribute__((aligned(4))) int8_t hidden_acts[128];
__attribute__((aligned(4))) int8_t output_logits[10];

uint32_t uart_read_uint32_be(void) {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 24;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 16;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 8;
    val |= ((uint32_t)hal_uart_getc() & 0xFF) << 0;
    return val;
}

void npu_run_layer(uint32_t* weights_packed, int32_t* biases, int8_t* inputs, int8_t* outputs,
                   int in_features, int out_features, uint32_t mult, uint32_t shift, int apply_relu) {

    MMIO32(NPU_BASE_ADDR + 0x44) = mult;   
    MMIO32(NPU_BASE_ADDR + 0x40) = shift;  
    MMIO32(NPU_BASE_ADDR + 0x48) = apply_relu ? 1 : 0; 

    MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

    for (int k = 0; k < in_features; k++) {
        MMIO32(NPU_BASE_ADDR + 0x14) = inputs[k] & 0xFF; 
    }

    int chunk_idx = 0;
    for (int chunk_start = 0; chunk_start < out_features; chunk_start += 4) {
        int chunk_size = (out_features - chunk_start < 4) ? (out_features - chunk_start) : 4;

        for (int b = 0; b < 4; b++) {
            if (b < chunk_size) MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = biases[chunk_start + b];
            else MMIO32(NPU_BASE_ADDR + 0x80 + (b * 4)) = 0; 
        }

        MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
        uint32_t src_addr = (uint32_t)(&weights_packed[chunk_idx * in_features]);
        hal_dma_memcpy(src_addr, NPU_BASE_ADDR + 0x10, in_features, 1);

        MMIO32(NPU_BASE_ADDR + 0x08) = in_features; 
        MMIO32(NPU_BASE_ADDR + 0x04) = 0x36;        

        // FIX 1: Impede a "Race Condition" aguardando o FSM ir para COMPUTE
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); // Aguarda STATUS_BUSY == 1
        
        // Agora sim podemos esperar terminar com segurança
        while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); // Aguarda STATUS_DONE == 1

        // FIX 2: A Linha 0 (Onde estão os inputs) é a 4ª a sair no Output DRAIN do Array.
        // Precisamos descartar os primeiros 3 lixos e salvar o 4º pop da FIFO.
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

int main(void) {
    hal_uart_init();
    while(1) {
        uint8_t cmd = hal_uart_getc();
        if (cmd == 0xAA) {
            for(int i = 0; i < 25088; i++) W1_packed[i] = uart_read_uint32_be();
            hal_uart_putc('A'); 
        }
        else if (cmd == 0xBB) {
            for(int i = 0; i < 128; i++) B1[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('B');
        }
        else if (cmd == 0xCC) {
            for(int i = 0; i < 384; i++) W2_packed[i] = uart_read_uint32_be();
            hal_uart_putc('C');
        }
        else if (cmd == 0xDD) {
            for(int i = 0; i < 12; i++) B2[i] = (int32_t)uart_read_uint32_be();
            hal_uart_putc('D');
        }
        else if (cmd == 0xFF) {
            for(int i = 0; i < 784; i++) input_image[i] = (int8_t)hal_uart_getc();

            npu_run_layer(W1_packed, B1, input_image, hidden_acts, 784, 128, 1, 9, 1);
            npu_run_layer(W2_packed, B2, hidden_acts, output_logits, 128, 10, 1, 9, 0);

            for(int i = 0; i < 10; i++) hal_uart_putc((char)output_logits[i]);
        }
    }
    return 0;
}