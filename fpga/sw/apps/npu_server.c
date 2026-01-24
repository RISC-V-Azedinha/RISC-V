/**
 * @file npu_server.c
 * @brief Servidor de Inferência via UART.
 * 
 * * Protocolo (1 Byte Command):
 * - 'W' (0x57): Carregar Pesos (Weights)
 * - Recebe: [K_DIM (4 bytes)] + [WEIGHT_DATA (K_DIM * 4 bytes)]
 * - 'I' (0x49): Carregar Imagem (Input)
 * - Recebe: [K_DIM (4 bytes)] + [INPUT_DATA (K_DIM * 4 bytes)]
 * - 'R' (0x52): Rodar Inferência (Run)
 * - Retorna: [CLASS (4 bytes)] + [CYCLES (8 bytes)]
 * 
 */

#include <stdint.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

// Buffer Global (Máximo suportado por camada)
#define MAX_K_DIM 2048
uint32_t buffer_weights[MAX_K_DIM];
uint32_t buffer_inputs[MAX_K_DIM];

// Recebe um bloco de dados da UART (Blocking)
void uart_read_bytes(uint8_t *dest, uint32_t len) {
    for (uint32_t i = 0; i < len; i++) {
        dest[i] = hal_uart_getc();
    }
}

// Envia um bloco de dados pela UART
void uart_write_bytes(uint8_t *src, uint32_t len) {
    for (uint32_t i = 0; i < len; i++) {
        hal_uart_putc(src[i]);
    }
}

// Helper para receber uint32 (Little Endian)
uint32_t uart_read_u32() {
    uint8_t b[4];
    uart_read_bytes(b, 4);
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

// Helper para enviar uint32
void uart_write_u32(uint32_t val) {
    uint8_t b[4];
    b[0] = val & 0xFF;
    b[1] = (val >> 8) & 0xFF;
    b[2] = (val >> 16) & 0xFF;
    b[3] = (val >> 24) & 0xFF;
    uart_write_bytes(b, 4);
}

// Helper para enviar uint64
void uart_write_u64(uint64_t val) {
    uart_write_u32((uint32_t)(val & 0xFFFFFFFF));
    uart_write_u32((uint32_t)(val >> 32));
}

int main() {
    hal_uart_init();
    hal_npu_init();
    hal_npu_set_dma_enabled(true); 

    hal_uart_putc('B'); 

    uint32_t current_k = 0;

    while (1) {
        uint8_t cmd = hal_uart_getc();

        switch (cmd) {
            case 'W': // Load Weights
            {
                uint32_t k = uart_read_u32();
                if (k > MAX_K_DIM) k = MAX_K_DIM;
                current_k = k;
                
                NPU_REG_CMD = NPU_CMD_RST_PTRS;
                
                uart_read_bytes((uint8_t*)buffer_weights, k * 4);
                
                npu_quant_params_t q = { .mult = 1, .shift = 12, .zero_point = 0, .relu = 0 };
                hal_npu_configure(current_k, &q);
                
                hal_npu_load_weights(buffer_weights, current_k);
                
                hal_uart_putc('K'); 
                break;
            }

            case 'I': // Load Input
            {
                uint32_t k = uart_read_u32();
                if (k > MAX_K_DIM) k = MAX_K_DIM;
                
                uart_read_bytes((uint8_t*)buffer_inputs, k * 4);
                
                hal_npu_load_inputs(buffer_inputs, k);
                
                hal_uart_putc('K'); 
                break;
            }

            case 'R': // Run Inference
            {

                npu_quant_params_t q = { .mult = 1, .shift = 12, .zero_point = 0, .relu = 0 };
                hal_npu_configure(current_k, &q);

                hal_timer_reset();
                hal_timer_start();
                uint64_t t0 = hal_timer_get_cycles();
                
                hal_npu_start();
                hal_npu_wait_done();
                
                uint64_t t1 = hal_timer_get_cycles();
                uint64_t cycles = t1 - t0;

                // Leitura PACKED (1 palavra = 4 resultados)
                uint32_t result_packed = NPU_REG_READ_OUT;

                uart_write_u32(result_packed); 
                uart_write_u64(cycles);
                break;

            }
            
            case 'P': 
                hal_uart_putc('P');
                break;

            default: break;
        }
    }
    return 0;
}