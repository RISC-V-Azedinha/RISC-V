#include <stdint.h>
#include "hal/hal_uart.h"
#include "npu/npu_lib.h" 
#include "npu/tiny_ml.h" 
#include "weights_iris.h" 

// Definição das Camadas (12 Neurônios na Oculta)
const layer_dense_t l1 = {
    .weights = W1_DATA, .bias = B1_DATA,
    .in_features = 4, .out_neurons = 12,
    .output_shift = IRIS_SHIFT, 
    .output_mult = 1, .use_relu = 1
};

const layer_dense_t l2 = {
    .weights = W2_DATA, .bias = B2_DATA,
    .in_features = 12, .out_neurons = 3,
    .output_shift = IRIS_SHIFT, 
    .output_mult = 1, .use_relu = 0
};

// Buffers
int8_t buf_in[4];
int8_t buf_hidden[16];
int8_t buf_out[4];

void main(void) {
    hal_uart_init();
    
    // Inicializa NPU (Reset e Bias Clear)
    ml_init();

    while(1) {
        // 1. Espera Sincronia (0xA5)
        while(hal_uart_getc() != 0xA5);

        // 2. Lê 4 bytes de Input
        buf_in[0] = (int8_t)hal_uart_getc();
        buf_in[1] = (int8_t)hal_uart_getc();
        buf_in[2] = (int8_t)hal_uart_getc();
        buf_in[3] = (int8_t)hal_uart_getc();

        // 3. Processamento NPU Pura
        // O driver tiny_ml gerencia o tiling automaticamente
        ml_run_layer(&l1, buf_in, buf_hidden);
        ml_run_layer(&l2, buf_hidden, buf_out);

        // 4. Envia Resposta (Protocolo Simples)
        // [Sync 0x5A] [Score0] [Score1] [Score2] [Padding]
        hal_uart_putc(0x5A);
        hal_uart_putc(buf_out[0]);
        hal_uart_putc(buf_out[1]);
        hal_uart_putc(buf_out[2]);
        hal_uart_putc(0x00); 
    }
}