/**
 * @file mlp_server.c
 * @brief Versão de DEBUG
 */

#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"
#include "memory_map.h"

#define ALIGN_128 __attribute__((aligned(16)))

ALIGN_128 static uint8_t  g_weight_store[180 * 1024];
ALIGN_128 static uint32_t g_bias_store[1024];
ALIGN_128 static uint32_t buffer_A[2048]; 
ALIGN_128 static uint32_t buffer_B[2048]; 

#define SYSTOLIC_ROWS 4

// --- Helpers ---
static inline uint8_t fast_getc(void) {
    while ((MMIO32(UART_CTRL_REG_ADDR) & UART_STATUS_RX_VALID) == 0);
    uint8_t c = (uint8_t)MMIO32(UART_DATA_REG_ADDR);
    MMIO32(UART_CTRL_REG_ADDR) = UART_CMD_RX_POP;
    return c;
}

static void uart_read_bytes(uint8_t *dest, uint32_t len) {
    for(uint32_t i=0; i<len; i++) dest[i] = fast_getc();
}

static uint32_t uart_read_u32(void) { 
    uint8_t b0 = fast_getc(); uint8_t b1 = fast_getc();
    uint8_t b2 = fast_getc(); uint8_t b3 = fast_getc();
    return (uint32_t)b0 | ((uint32_t)b1<<8) | ((uint32_t)b2<<16) | ((uint32_t)b3<<24); 
}

static void uart_write_u32(uint32_t val) { 
    hal_uart_putc(val & 0xFF); hal_uart_putc((val >> 8) & 0xFF);
    hal_uart_putc((val >> 16) & 0xFF); hal_uart_putc((val >> 24) & 0xFF);
}

static void uart_write_u64(uint64_t val) { 
    uart_write_u32((uint32_t)val); uart_write_u32((uint32_t)(val>>32)); 
}

int main(void) {
    hal_uart_init();
    hal_npu_init();
    hal_npu_set_dma_enabled(true); 

    while (1) {
        uint8_t cmd = fast_getc();

        switch (cmd) {
            case 'P': hal_uart_putc('O'); break;

            case 'L': {
                uint32_t total = uart_read_u32();
                if(total > sizeof(g_weight_store)) total = sizeof(g_weight_store);
                uart_read_bytes(g_weight_store, total);
                hal_uart_putc('K');
                break;
            }

            case 'B': {
                uint32_t total = uart_read_u32();
                if(total > sizeof(g_bias_store)) total = sizeof(g_bias_store);
                uart_read_bytes((uint8_t*)g_bias_store, total);
                hal_uart_putc('K');
                break;
            }

            case 'I': {
                uint32_t total = uart_read_u32(); 
                if(total > sizeof(buffer_A)) total = sizeof(buffer_A);
                uart_read_bytes((uint8_t*)buffer_A, total);
                hal_uart_putc('K');
                break;
            }

            case 'R': {
                uint32_t num_layers = uart_read_u32();
                uint32_t *p_in  = buffer_A;
                uint32_t *p_out = buffer_B;
                uint32_t final_len = 0;

                hal_timer_reset(); hal_timer_start();
                uint64_t t_start = hal_timer_get_cycles();

                for (uint32_t l = 0; l < num_layers; l++) {
                    uint32_t n_in_words = uart_read_u32();
                    uint32_t n_out      = uart_read_u32();
                    uint32_t w_off      = uart_read_u32(); 
                    uint32_t b_off      = uart_read_u32();
                    
                    npu_quant_params_t q;
                    q.mult = uart_read_u32(); q.shift = uart_read_u32();
                    q.zero_point = uart_read_u32(); q.relu = (uart_read_u32() > 0);

                    uint8_t  *layer_weights = g_weight_store + w_off;
                    uint32_t *layer_biases  = g_bias_store + b_off;

                    // Debug: Indica inicio da camada
                    hal_uart_putc('L'); 

                    for (uint32_t o = 0; o < n_out; o++) {
                        hal_npu_init(); 
                        hal_npu_configure(n_in_words, &q);
                        hal_npu_load_inputs(p_in, n_in_words);
                        
                        uint32_t w_idx = o * n_in_words * 4;
                        hal_npu_load_weights((uint32_t*)(layer_weights + w_idx), n_in_words);

                        NPU_REG_BIAS_BASE = layer_biases[o];

                        hal_npu_start();
                        hal_npu_wait_done();

                        // Drain: Lê 4 vezes, guarda a última
                        uint32_t val;
                        for(int i=0; i<SYSTOLIC_ROWS; i++) val = NPU_REG_READ_OUT;
                        p_out[o] = val;

                        // Debug: Ponto a cada neurônio
                        hal_uart_putc('.');
                    }
                    
                    final_len = n_out;
                    uint32_t *temp = p_in; p_in = p_out; p_out = temp;
                }

                uint64_t t_end = hal_timer_get_cycles();
                
                // Marca fim dos debugs para o Python saber que vêm dados
                hal_uart_putc('!'); 

                uart_write_u64(t_end - t_start);
                uart_write_u32(final_len);
                for (uint32_t i = 0; i < final_len; i++) uart_write_u32(p_in[i]);
                break;
            }
        }
    }
    return 0;
}