/**
 * @file benchmark.c
 * @brief Benchmark de Eficiência de Memória e Movimentação de Dados (NPU RISC-V).
 * * Este programa isola a NPU para medir os ganhos arquiteturais de:
 * 1. Aceleração de Barramento: PIO (Programmed I/O) vs DMA.
 * 2. Eficiência de Localidade: Reuso de Dados (Input Stationary) vs Sem Reuso.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_timer.h"

// ============================================================================
// CONFIGURAÇÃO DO EXPERIMENTO
// ============================================================================

#define K_DIM       8192    // Profundidade do Tensor (Garante saturação do barramento)
#define ITERATIONS  16      // Número de batches/inferências para tirar a média
#define FILTERS     16      // Número de filtros para teste de localidade

// Buffers na RAM (seção .bss)
uint32_t input_data[K_DIM];
uint32_t weight_data[K_DIM];

// ============================================================================
// UTILITÁRIOS DE PRINT E TEMPO
// ============================================================================

void print_u32(uint32_t n) {
    char buf[12]; int i = 0; if (n == 0) { hal_uart_putc('0'); return; }
    while (n > 0) { buf[i++] = (n % 10) + '0'; n /= 10; } while (i > 0) hal_uart_putc(buf[--i]);
}

void print_u64_hex(uint64_t n) {
    hal_uart_puts("0x"); char hex[] = "0123456789ABCDEF";
    for (int i = 60; i >= 0; i -= 4) hal_uart_putc(hex[(n >> i) & 0xF]);
}

void print_speedup(uint64_t slow, uint64_t fast) {
    if (fast == 0) { hal_uart_puts("INF"); return; }
    uint32_t s = (uint32_t)slow; uint32_t f = (uint32_t)fast; if (f == 0) f = 1;
    uint32_t integer = s / f; uint32_t remainder = s % f; uint32_t fraction = (remainder * 100) / f; 
    print_u32(integer); hal_uart_putc('.');
    if (fraction < 10) hal_uart_putc('0'); print_u32(fraction);
}

// ============================================================================
// WORKLOADS
// ============================================================================

void npu_setup() {
    npu_quant_params_t config = { .mult = 1, .shift = 8, .zero_point = 0, .relu = false };
    hal_npu_configure(K_DIM, &config);
}

// Executa o ciclo completo de uma inferência
void npu_inference() {
    hal_npu_load_inputs(input_data, K_DIM);
    hal_npu_load_weights(weight_data, K_DIM);
    hal_npu_start();
    hal_npu_wait_done();
    
    uint32_t results[4];
    hal_npu_read_output(results, 4); // Esvazia o buffer
}

// CENÁRIO A: Sem Reuso (Recarrega Inputs e Weights a cada filtro)
void workload_locality_bad() {
    for(int f=0; f<FILTERS; f++) {
        hal_npu_load_inputs(input_data, K_DIM);  // Overhead de Barramento
        hal_npu_load_weights(weight_data, K_DIM);
        hal_npu_start();
        hal_npu_wait_done();
        uint32_t results[4]; hal_npu_read_output(results, 4);
    }
}

// CENÁRIO B: Com Reuso de Input (Carrega Input apenas 1x)
void workload_locality_good() {
    hal_npu_load_inputs(input_data, K_DIM);      // Carga única
    for(int f=0; f<FILTERS; f++) {
        hal_npu_load_weights(weight_data, K_DIM);
        hal_npu_start();
        hal_npu_wait_done();
        uint32_t results[4]; hal_npu_read_output(results, 4);
    }
}

// ============================================================================
// MAIN EXPERIMENT
// ============================================================================

int main() {
    hal_uart_init();
    hal_npu_init();
    
    // Zera os arrays (apenas para evitar lixo)
    for(int i=0; i<K_DIM; i++) { input_data[i] = 0; weight_data[i] = 0; }

    hal_uart_puts("\n\r===============================================\n\r");
    hal_uart_puts("   NPU DATA MOVEMENT PROFILER (Cycle Exact)  \n\r");
    hal_uart_puts("===============================================\n\n\r");

    uint64_t start, end;
    uint64_t t_pio = 0, t_dma = 0;

    // ------------------------------------------------------------------------
    // TESTE 1: PIO vs DMA (Avaliação do Barramento)
    // ------------------------------------------------------------------------
    hal_uart_puts("--- [ TESTE 1: PROTOCOLO DE BARRAMENTO ] ---\n\r");

    // [1A] Modo PIO (CPU escrevendo MMIO palavra por palavra)
    hal_uart_puts("-> Running PIO Mode... ");
    hal_npu_set_dma_enabled(false);
    npu_setup();
    npu_inference(); // Warm-up
    start = hal_timer_get_cycles();
    for(int i=0; i<ITERATIONS; i++) npu_inference();
    end = hal_timer_get_cycles();
    t_pio = (end - start);
    hal_uart_puts("Done.\n\r");

    // [1B] Modo DMA (Hardware Offloading e Burst)
    hal_uart_puts("-> Running DMA Mode... ");
    hal_npu_set_dma_enabled(true);
    npu_setup();
    npu_inference(); // Warm-up
    start = hal_timer_get_cycles();
    for(int i=0; i<ITERATIONS; i++) npu_inference();
    end = hal_timer_get_cycles();
    t_dma = (end - start);
    hal_uart_puts("Done.\n\r");

    // Relatório Teste 1
    hal_uart_puts("\n\r[Resultados Teste 1]\n\r");
    hal_uart_puts("Ciclos Totais PIO: "); print_u64_hex(t_pio); hal_uart_puts("\n\r");
    hal_uart_puts("Ciclos Totais DMA: "); print_u64_hex(t_dma); hal_uart_puts("\n\r");
    hal_uart_puts("Aceleracao do DMA (Speedup): "); print_speedup(t_pio, t_dma); hal_uart_puts("x\n\n\r");

    // ------------------------------------------------------------------------
    // TESTE 2: REUSO DE DADOS (Eficiência do Array Sistólico)
    // ------------------------------------------------------------------------
    hal_uart_puts("--- [ TESTE 2: DATA REUSE (LOCALITY) ] ---\n\r");
    
    uint64_t t_bad = 0, t_good = 0;
    hal_npu_set_dma_enabled(true); // Sempre usa o DMA como base para este teste

    // [2A] Sem Reuso
    hal_uart_puts("-> Running No Reuse (Reload All)... ");
    npu_setup();
    start = hal_timer_get_cycles();
    workload_locality_bad();
    end = hal_timer_get_cycles();
    t_bad = (end - start);
    hal_uart_puts("Done.\n\r");

    // [2B] Com Reuso (Input Stationary)
    hal_uart_puts("-> Running Input Reuse (Stationary)... ");
    npu_setup(); 
    start = hal_timer_get_cycles();
    workload_locality_good();
    end = hal_timer_get_cycles();
    t_good = (end - start);
    hal_uart_puts("Done.\n\r");

    // Relatório Teste 2
    hal_uart_puts("\n\r[Resultados Teste 2]\n\r");
    hal_uart_puts("Ciclos Sem Reuso:   "); print_u64_hex(t_bad); hal_uart_puts("\n\r");
    hal_uart_puts("Ciclos Com Reuso:   "); print_u64_hex(t_good); hal_uart_puts("\n\r");
    hal_uart_puts("Ganho de Localidade: "); print_speedup(t_bad, t_good); hal_uart_puts("x\n\r");

    hal_uart_puts("\n\r>>> PROFILING COMPLETED <<<\n\r");
    
    while(1);
    return 0;   
}