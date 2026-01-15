#include <stdint.h>
#include "hal/hal_uart.h"
#include "npu/npu_lib.h" 
#include "npu/tiny_ml.h" 
#include "weights_mnist.h"

// Camada 1: 784 entradas -> 64 neurônios
const layer_dense_t l1 = {
    .weights = W1_DATA, .bias = B1_DATA,
    .in_features = 784, .out_neurons = 64,
    .output_shift = MNIST_SHIFT, 
    .output_mult = 1, .use_relu = 1
};

// Camada 2: 64 entradas -> 10 neurônios
const layer_dense_t l2 = {
    .weights = W2_DATA, .bias = B2_DATA,
    .in_features = 64, .out_neurons = 10,
    .output_shift = MNIST_SHIFT, 
    .output_mult = 1, .use_relu = 0
};

// Buffers (Globais para não estourar a stack)
int8_t img_buffer[784];    // Buffer da imagem
int8_t hidden_buffer[64];  // Camada oculta
int8_t output_buffer[16];  // Saída (10 classes + padding)

void main(void) {
    hal_uart_init();
    ml_init();

    while(1) {
        // 1. Espera Sincronia (0xA5)
        while(hal_uart_getc() != 0xA5);

        // 2. Lê a imagem completa (784 bytes)
        for(int i=0; i<784; i++) {
            img_buffer[i] = (int8_t)hal_uart_getc();
        }

        // 3. Processamento NPU
        // L1: O Tiling da NPU vai quebrar 784x64 em centenas de blocos 4x4
        ml_run_layer(&l1, img_buffer, hidden_buffer);
        
        // L2: 64x10
        ml_run_layer(&l2, hidden_buffer, output_buffer);

        // 4. Envia Resposta (10 Scores)
        // [Sync 0x5A] [Score0] ... [Score9]
        hal_uart_putc(0x5A);
        for(int i=0; i<10; i++) {
            hal_uart_putc(output_buffer[i]);
        }
    }
}