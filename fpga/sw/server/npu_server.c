/**
 * @file npu_server.c
 * @brief Firmware v3.3: Conditional Benchmark (CPU Opcional via Flag)
 */

#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

#define MAX_K_DIM 2048
#define MAX_STORED_WEIGHTS_BYTES  (180 * 1024)

static uint32_t g_weight_store[MAX_STORED_WEIGHTS_BYTES / 4];
static uint32_t buffer_weights[MAX_K_DIM];
static uint32_t buffer_inputs[MAX_K_DIM];

typedef struct {
    uint32_t num_tiles;
    uint32_t k_dim;
    uint32_t stride_bytes;
} tiling_cfg_t;

static tiling_cfg_t g_tiling = {1, 0, 0}; 

typedef struct {
    uint32_t mult; uint32_t shift; bool relu;
} npu_state_t;
static npu_state_t g_npu_ctx = {1, 8, false};

// Helpers
static void uart_read_bytes(uint8_t *dest, uint32_t len) { for (uint32_t i = 0; i < len; i++) dest[i] = hal_uart_getc(); }
static uint32_t uart_read_u32(void) { uint8_t b[4]; uart_read_bytes(b, 4); return (uint32_t)b[0] | ((uint32_t)b[1]<<8) | ((uint32_t)b[2]<<16) | ((uint32_t)b[3]<<24); }
static void uart_write_u32(uint32_t val) { uint8_t b[] = {val&0xFF, (val>>8)&0xFF, (val>>16)&0xFF, (val>>24)&0xFF}; for(int i=0; i<4; i++) hal_uart_putc(b[i]); }
static void uart_write_u64(uint64_t val) { uart_write_u32((uint32_t)val); uart_write_u32((uint32_t)(val>>32)); }

// CPU Reference
static void cpu_inference(uint32_t *results_out) {
    int32_t acc[4] = {0};
    for (uint32_t k = 0; k < g_tiling.k_dim; k++) { 
        uint32_t w_pack = buffer_weights[k];
        uint32_t i_pack = buffer_inputs[k];
        for (int n = 0; n < 4; n++) {
            int8_t w = (int8_t)(w_pack >> (n * 8));
            int8_t i = (int8_t)(i_pack >> (n * 8));
            acc[n] += (int32_t)i * (int32_t)w;
        }
    }
    uint32_t packed_res = 0;
    for (int n = 0; n < 4; n++) {
        int32_t val = (acc[n] * (int32_t)g_npu_ctx.mult) >> g_npu_ctx.shift;
        if (g_npu_ctx.relu && val < 0) val = 0;
        if (val > 127) val = 127; if (val < -128) val = -128;
        packed_res |= ((uint8_t)val & 0xFF) << (n * 8);
    }
    *results_out = packed_res;
}

int main(void) {
    hal_uart_init();
    hal_npu_init();
    hal_npu_set_dma_enabled(true);
    hal_uart_putc('B'); 

    while (1) {
        uint8_t cmd = hal_uart_getc();
        switch (cmd) {
            case 'C': { 
                g_npu_ctx.mult  = uart_read_u32(); 
                g_npu_ctx.shift = uart_read_u32();
                uint32_t r = uart_read_u32(); g_npu_ctx.relu = (r > 0);
                hal_uart_putc('K'); break;
            }
            case 'L': {
                uint32_t total = uart_read_u32();
                if (total > MAX_STORED_WEIGHTS_BYTES) total = MAX_STORED_WEIGHTS_BYTES;
                uart_read_bytes((uint8_t*)g_weight_store, total);
                hal_uart_putc('K'); break;
            }
            case 'I': { 
                uint32_t k = uart_read_u32(); 
                if (k > MAX_K_DIM) k = MAX_K_DIM;
                uart_read_bytes((uint8_t*)buffer_inputs, k * 4);
                hal_uart_putc('K'); break;
            }
            case 'T': {
                g_tiling.num_tiles    = uart_read_u32();
                g_tiling.k_dim        = uart_read_u32();
                g_tiling.stride_bytes = uart_read_u32();
                hal_uart_putc('K'); break;
            }

            // --- BENCHMARK CONDICIONAL ---
            case 'B': { 
                uint32_t flags = uart_read_u32();
                bool do_cpu_bench = (flags & 0x02); // Bit 1 controla CPU Bench
                
                uint32_t results[16]; 
                uint32_t loops = g_tiling.num_tiles;
                if (loops > 16) loops = 16;

                npu_quant_params_t q = { .mult = g_npu_ctx.mult, .shift = g_npu_ctx.shift, .relu = g_npu_ctx.relu };
                
                uint64_t total_npu_sys_cycles = 0;
                uint64_t total_cpu_cycles = 0;

                NPU_REG_CMD = NPU_CMD_RST_PTRS;
                hal_npu_configure(g_tiling.k_dim, &q);
                hal_npu_load_inputs(buffer_inputs, g_tiling.k_dim);

                for (uint32_t i = 0; i < loops; i++) {
                    
                    uint32_t offset = i * g_tiling.stride_bytes;
                    uint32_t src_addr = (uint32_t)g_weight_store + offset;

                    // --- NPU ---
                    uint64_t t_npu_start = hal_timer_get_cycles();

                    hal_dma_memcpy(src_addr, (uint32_t)buffer_weights, g_tiling.k_dim, 0);

                    NPU_REG_CMD = NPU_CMD_RST_PTRS; 
                    hal_npu_configure(g_tiling.k_dim, &q);
                    hal_npu_load_weights(buffer_weights, g_tiling.k_dim);
                    hal_npu_start();
                    hal_npu_wait_done();

                    total_npu_sys_cycles += (hal_timer_get_cycles() - t_npu_start);
                    results[i] = NPU_REG_READ_OUT;

                    // --- CPU (OPCIONAL) ---
                    if (do_cpu_bench) {
                        uint32_t dummy_res;

                        uint64_t t_cpu_start = hal_timer_get_cycles();
                        
                        cpu_inference(&dummy_res); 
                        
                        total_cpu_cycles += (hal_timer_get_cycles() - t_cpu_start);
                    }
                }

                // Envia Resultados
                for(uint32_t i = 0; i < loops; i++) uart_write_u32(results[i]);

                // Envia Timings (CPU pode ser 0)
                uart_write_u64(total_cpu_cycles);
                uart_write_u64(0);
                uart_write_u64(total_npu_sys_cycles);
                break;
            }

            case 'P': hal_uart_putc('P'); break;
            default: break;
        }
    }
    return 0;
}