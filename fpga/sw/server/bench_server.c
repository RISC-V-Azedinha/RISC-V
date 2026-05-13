/**
 * @file bench_server.c
 * @brief Firmware de Benchmark Bare-Metal (GEMM - 16 MACs/ciclo)
 *        CORRIGIDO: Otimizado para alimentar 4 inputs independentes por ciclo.
 */

#include <stdint.h>
#include <stdbool.h>

#include "memory_map.h"
#include "hal/hal_uart.h"
#include "hal/hal_timer.h"
#include "hal/hal_dma.h"

#define MAX_K_DIM 8192

static uint32_t buffer_weights[MAX_K_DIM];
static uint32_t buffer_inputs[MAX_K_DIM];

uint8_t uart_read_byte() { return hal_uart_getc(); }

uint32_t uart_read_u32() {
    uint32_t val = 0;
    val |= ((uint32_t)hal_uart_getc() << 24);
    val |= ((uint32_t)hal_uart_getc() << 16);
    val |= ((uint32_t)hal_uart_getc() << 8);
    val |= ((uint32_t)hal_uart_getc());
    return val;
}

void uart_write_u64(uint64_t val) {
    hal_uart_putc((uint8_t)(val >> 56));
    hal_uart_putc((uint8_t)(val >> 48));
    hal_uart_putc((uint8_t)(val >> 40));
    hal_uart_putc((uint8_t)(val >> 32));
    hal_uart_putc((uint8_t)(val >> 24));
    hal_uart_putc((uint8_t)(val >> 16));
    hal_uart_putc((uint8_t)(val >> 8));
    hal_uart_putc((uint8_t)(val & 0xFF));
}

int main() {
    hal_uart_init(); 

    while(1) {
        uint8_t cmd = uart_read_byte();

        if (cmd == 'B') {
            uint32_t k_dim = uart_read_u32();       
            uint8_t sparsity = uart_read_byte();    

            if (k_dim > MAX_K_DIM) k_dim = MAX_K_DIM;

            // ------------------------------------------------------------
            // ETAPA 1: Geração de Dados Sintéticos (AGORA 4 VALORES DE 8 BITS POR INDEX)
            // ------------------------------------------------------------
            uint32_t lfsr = 0xACE1u; 
            for(uint32_t i = 0; i < k_dim; i++) {
                lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u); 
                
                if ((lfsr % 100) < sparsity) {
                    buffer_inputs[i] = 0; // Palavra inteira com 4 Zeros
                } else {
                    buffer_inputs[i] = lfsr; // 4 bytes aleatórios empacotados
                }
                buffer_weights[i] = lfsr * 13; // 4 pesos aleatórios
            }

            // ------------------------------------------------------------
            // ETAPA 2: BENCHMARK CPU OTIMIZADO (Unrolled & Register-Focused)
            // ------------------------------------------------------------
            uint64_t t_cpu_start = hal_timer_get_cycles();
            int32_t out0 = 0, out1 = 0, out2 = 0, out3 = 0;

            for (uint32_t k = 0; k < k_dim; k++) {
                uint32_t i_pack = buffer_inputs[k];
                if (i_pack == 0) continue; 
                
                uint32_t w_pack = buffer_weights[k];
                
                // Extraímos os inputs uma única vez para registradores locais
                int8_t i0 = (int8_t)(i_pack & 0xFF);
                int8_t i1 = (int8_t)((i_pack >> 8) & 0xFF);
                int8_t i2 = (int8_t)((i_pack >> 16) & 0xFF);
                int8_t i3 = (int8_t)((i_pack >> 24) & 0xFF);

                // Extraímos os pesos e acumulamos (Simulando o esforço dos 16 MACs)
                // Fizemos o unroll manual para evitar o custo de loops internos (i e w)
                int8_t w0 = (int8_t)(w_pack & 0xFF);
                int8_t w1 = (int8_t)((w_pack >> 8) & 0xFF);
                int8_t w2 = (int8_t)((w_pack >> 16) & 0xFF);
                int8_t w3 = (int8_t)((w_pack >> 24) & 0xFF);

                out0 += (i0 * w0) + (i1 * w0) + (i2 * w0) + (i3 * w0);
                out1 += (i0 * w1) + (i1 * w1) + (i2 * w1) + (i3 * w1);
                out2 += (i0 * w2) + (i1 * w2) + (i2 * w2) + (i3 * w2);
                out3 += (i0 * w3) + (i1 * w3) + (i2 * w3) + (i3 * w3);
            }
            uint64_t total_cpu_cycles = hal_timer_get_cycles() - t_cpu_start;

            // ------------------------------------------------------------
            // ETAPA 3: BENCHMARK NPU (100% Capacidade - 16 MACs)
            // ------------------------------------------------------------
            MMIO32(NPU_BASE_ADDR + 0x44) = 1;   
            MMIO32(NPU_BASE_ADDR + 0x40) = 8;   
            MMIO32(NPU_BASE_ADDR + 0x48) = 0;   
            MMIO32(NPU_BASE_ADDR + 0x04) = 0xC1; 

            // ALIMENTAÇÃO GEMM: Manda a palavra de 32-bits intacta! 
            // 4 inputs independentes entram na matriz a cada ciclo de escrita.
            for (uint32_t k = 0; k < k_dim; k++) {
                MMIO32(NPU_BASE_ADDR + 0x14) = buffer_inputs[k]; 
            }

            // MEDIÇÃO
            uint64_t t_npu_start = hal_timer_get_cycles();
            
            MMIO32(NPU_BASE_ADDR + 0x04) = (1 << 6); 
            hal_dma_memcpy((uint32_t)buffer_weights, NPU_BASE_ADDR + 0x10, k_dim, 1);
            
            MMIO32(NPU_BASE_ADDR + 0x08) = k_dim; 
            MMIO32(NPU_BASE_ADDR + 0x04) = 0x36; 

            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 0))); 
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 1))); 
            
            uint64_t total_npu_cycles = hal_timer_get_cycles() - t_npu_start;
            
            uint32_t trash;
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            while (!(MMIO32(NPU_BASE_ADDR + 0x00) & (1 << 3))); trash = MMIO32(NPU_BASE_ADDR + 0x18);
            (void)trash;

            // ------------------------------------------------------------
            // ETAPA 4: Resultados
            // ------------------------------------------------------------
            uart_write_u64(total_cpu_cycles);
            uart_write_u64(total_npu_cycles);
        }
    }
    return 0;
}