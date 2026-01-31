/**
 * @file benchmark.c
 * @brief Benchmark para Validação da NPU RISC-V.
 * 
 * * Este programa realiza uma bateria de testes exaustiva para validar:
 * 1. Corretude Matemática (CPU vs NPU).
 * 2. Desempenho (Throughput e Latência).
 * 3. Eficiência do DMA (Offloading).
 * 4. Eficiência de Localidade (Reuso de Dados).
 * 
 * * Metodologia:
 * - Medição cycle-exact usando Timer de Hardware de 64-bit.
 * - Isolamento de overhead de configuração (medindo apenas inferência).
 * - Comparação justa entre CPU Escalar (Software) e NPU Sistólica (Hardware).
 * 
 */

#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"
#include "hal/hal_dma.h"
#include "hal/hal_timer.h"

// ============================================================================
// CONFIGURAÇÃO DO EXPERIMENTO
// ============================================================================

#define K_DIM       2048    // Profundidade do Tensor (Satura o pipeline)
#define ITERATIONS  16      // Número de batches 
#define FILTERS     16      // Número de filtros para teste de localidade

// GABARITO DE CORRETUDE (MATH CHECK)
// CPU: Calcula a soma pura (Full Precision). 
//      Input(2) * Weight(1) * K(2048) = 4096.
#define EXPECTED_CPU 4096 

// NPU: Calcula soma com Quantização de Borda (Edge Quantization).
//      (4096 >> 8) = 16 (0x10). 
//      Saída empacotada (4 pixels de 8 bits): 0x10101010.
#define EXPECTED_NPU 0x10101010 

// Buffers alocados na RAM (seção .bss)
uint32_t input_data[K_DIM];
uint32_t weight_data[K_DIM];

// ============================================================================
// WORKLOADS: COMPUTACIONAIS (BASELINE & NPU)
// ============================================================================

// 1. CPU BASELINE (RV32I Software Implementation)
// Simula o custo real de processar dados empacotados (INT8) em arquitetura de 32 bits.

uint32_t workload_cpu_gold() {

    int32_t acc[4][4];

    // Zera acumuladores
    for(int r=0; r<4; r++) for(int c=0; c<4; c++) acc[r][c] = 0;
    
    // Loop Principal (K)
    for (int k = 0; k < K_DIM; k++) {
        uint32_t in = input_data[k];
        uint32_t wg = weight_data[k];
        
        // Unpacking (Extração de bytes via Shift/Mask)
        int8_t in_vec[4] = {(int8_t)in, (int8_t)(in>>8), (int8_t)(in>>16), (int8_t)(in>>24)};
        int8_t wg_vec[4] = {(int8_t)wg, (int8_t)(wg>>8), (int8_t)(wg>>16), (int8_t)(wg>>24)};

        // Núcleo Matemático (16 MACs)
        for (int r = 0; r < 4; r++) {
            for (int c = 0; c < 4; c++) {
                acc[r][c] += in_vec[r] * wg_vec[c];
            }
        }

    }

    return (uint32_t)acc[0][0]; // Retorna 1 elemento para verificação

}

// Configuração da NPU (isolada para não afetar métrica de throughput)
void npu_setup() {

    // Config: Mult=1, Shift=8 (Divisão por 256), Sem ReLU
    npu_quant_params_t config = { .mult = 1, .shift = 8, .zero_point = 0, .relu = false };
    hal_npu_configure(K_DIM, &config);

}

// 2. NPU INFERENCE (Hardware Acceleration)
// Executa o ciclo completo de uma inferência: Carga -> Execução -> Leitura
uint32_t npu_inference() {

    hal_npu_load_inputs(input_data, K_DIM);
    hal_npu_load_weights(weight_data, K_DIM);
    hal_npu_start();
    hal_npu_wait_done();
    
    uint32_t results[4];
    hal_npu_read_output(results, 4);
    return results[0]; 

}

// ============================================================================
// WORKLOADS: LOCALIDADE & REUSO DE DADOS
// ============================================================================

// CENÁRIO A: Sem Reuso 
// Pior caso: Recarrega a imagem de entrada (Input) para cada novo filtro.

void workload_locality_bad() {
    for(int f=0; f<FILTERS; f++) {
        hal_npu_load_inputs(input_data, K_DIM);  // <--- GARGALO: Recarga desnecessária
        hal_npu_load_weights(weight_data, K_DIM);
        hal_npu_start();
        hal_npu_wait_done();
    }
}

// CENÁRIO B: Com Reuso de Input (Input Stationary)
// Melhor caso: Carrega imagem uma vez e troca apenas os pesos (Filtros).

void workload_locality_good() {

    // 1. Carga Inicial da Imagem (Input)
    hal_npu_load_inputs(input_data, K_DIM);

    // 2. Loop de Filtros (Apenas Weights variam)
    for(int f=0; f<FILTERS; f++) {
        hal_npu_load_weights(weight_data, K_DIM);
        hal_npu_start();
        hal_npu_wait_done();
    }

}

// ============================================================================
// UTILITÁRIOS
// ============================================================================

void *memset(void *dest, int val, size_t len) {
    unsigned char *ptr = (unsigned char*)dest; while (len-- > 0) *ptr++ = val; return dest;
}

void print_u32(uint32_t n) {
    char buf[12]; int i = 0; if (n == 0) { hal_uart_putc('0'); return; }
    while (n > 0) { buf[i++] = (n % 10) + '0'; n /= 10; } while (i > 0) hal_uart_putc(buf[--i]);
}

void print_hex(uint32_t n) {
    hal_uart_puts("0x"); char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) hal_uart_putc(hex[(n >> i) & 0xF]);
}

void print_u64_hex(uint64_t n) {
    hal_uart_puts("0x"); char hex[] = "0123456789ABCDEF";
    for (int i = 60; i >= 0; i -= 4) hal_uart_putc(hex[(n >> i) & 0xF]);
}

// Calcula Speedup usando aritmética de inteiros (simula ponto flutuante)
void print_speedup(uint64_t slow, uint64_t fast) {
    if (fast == 0) { hal_uart_puts("INF"); return; }
    uint32_t s = (uint32_t)slow; uint32_t f = (uint32_t)fast; if (f == 0) f = 1;
    uint32_t integer = s / f; uint32_t remainder = s % f; uint32_t fraction = (remainder * 100) / f; 
    print_u32(integer); hal_uart_putc('.');
    if (fraction < 10) hal_uart_putc('0'); print_u32(fraction);
}

// ============================================================================
// MAIN
// ============================================================================

int main() {
    
    hal_uart_init();
    hal_npu_init();
    
    // Geração de Dados Sintéticos (Input=2, Weight=1)
    for(int i=0; i<K_DIM; i++) { 
        input_data[i]  = 0x02020202; 
        weight_data[i] = 0x01010101; 
    }

    hal_uart_puts("\n\r===============================================\n\r");
    hal_uart_puts("   RISC-V NPU BENCHMARK (Cycle Exact)    \n\r");
    hal_uart_puts("===============================================\n\n\r");
    hal_uart_puts("Strategy: Throughput Measurement\n\r");
    hal_uart_puts("K_DIM:    "); print_u32(K_DIM); hal_uart_puts("\n\r");
    hal_uart_puts("Batches:  "); print_u32(ITERATIONS); hal_uart_puts("\n\n\r");

    uint64_t start, end;
    uint64_t t_cpu = 0, t_npu_pio = 0, t_npu_dma = 0;
    uint32_t check_val = 0;

    // ------------------------------------------------------------------------
    // 1. CPU BASELINE
    // ------------------------------------------------------------------------

    hal_uart_puts("[1] CPU Baseline...         ");

    // Warm-up
    workload_cpu_gold(); 
    
    // Validação de Corretude
    check_val = workload_cpu_gold();
    if (check_val != EXPECTED_CPU) {

        hal_uart_puts("FAIL! (Got: "); print_u32(check_val); hal_uart_puts(")\n\r");

    } else {

        // Benchmark

        start = hal_timer_get_cycles();
        for(int i=0; i<ITERATIONS; i++) workload_cpu_gold();
        end = hal_timer_get_cycles();
        t_cpu = (end - start);
        hal_uart_puts("PASS & Done.\n\r");

    }

    // ------------------------------------------------------------------------
    // 2. NPU (PIO MODE)
    // ------------------------------------------------------------------------

    hal_uart_puts("[2] NPU (PIO Transfer)...   ");
    hal_npu_set_dma_enabled(false);
    npu_setup();

    // Warm-up
    npu_inference(); 
    
    // Validação de Corretude
    check_val = npu_inference();
    if (check_val != EXPECTED_NPU) {

        hal_uart_puts("FAIL! (Got: "); print_hex(check_val); hal_uart_puts(")\n\r");

    } else {

        // Benchmark

        start = hal_timer_get_cycles();
        for(int i=0; i<ITERATIONS; i++) npu_inference();
        end = hal_timer_get_cycles();
        t_npu_pio = (end - start);
        hal_uart_puts("PASS & Done.\n\r");

    }

    // ------------------------------------------------------------------------
    // 3. NPU (DMA MODE)
    // ------------------------------------------------------------------------

    hal_uart_puts("[3] NPU (DMA Transfer)...   ");
    hal_npu_set_dma_enabled(true);
    npu_setup();

    // Warm-up
    npu_inference(); 
    
    // Validação de Corretude
    check_val = npu_inference();
    if (check_val != EXPECTED_NPU) {

        hal_uart_puts("FAIL! (Got: "); print_hex(check_val); hal_uart_puts(")\n\r");

    } else {

        // Benchmark

        start = hal_timer_get_cycles();
        for(int i=0; i<ITERATIONS; i++) npu_inference();
        end = hal_timer_get_cycles();
        t_npu_dma = (end - start);
        hal_uart_puts("PASS & Done.\n\r");

    }

    // ------------------------------------------------------------------------
    // REPORT 1: PERFORMANCE
    // ------------------------------------------------------------------------

    if (t_cpu > 0 && t_npu_dma > 0) {

        hal_uart_puts("\n\r-----------------------------------------------\n\r");
        hal_uart_puts("             PERFORMANCE REPORT                \n\r");
        hal_uart_puts("-----------------------------------------------\n\n\r");
        
        hal_uart_puts("Total Cycles (16 batches):\n\r");
        hal_uart_puts("  CPU: "); print_u64_hex(t_cpu); hal_uart_puts("\n\r");
        hal_uart_puts("  PIO: "); print_u64_hex(t_npu_pio); hal_uart_puts("\n\r");
        hal_uart_puts("  DMA: "); print_u64_hex(t_npu_dma); hal_uart_puts("\n\r");

        // AVG PER INFERENCE (Bitwise Shift por 4 = Divisão por 16)
        hal_uart_puts("\n\rCycles per Inference (Avg):\n\r");
        hal_uart_puts("  CPU: "); print_u64_hex(t_cpu >> 4); hal_uart_puts("\n\r");
        hal_uart_puts("  PIO: "); print_u64_hex(t_npu_pio >> 4); hal_uart_puts("\n\r");
        hal_uart_puts("  DMA: "); print_u64_hex(t_npu_dma >> 4); hal_uart_puts("\n\r");
        
        hal_uart_puts("\n\r-----------------------------------------------\n\r");
        hal_uart_puts("             SPEEDUP ANALYSIS                  \n\r");
        hal_uart_puts("-----------------------------------------------\n\n\r");
        
        hal_uart_puts("NPU vs CPU Speedup:       "); 
        print_speedup(t_cpu, t_npu_dma); hal_uart_puts("x\n\r");
        
        hal_uart_puts("DMA vs PIO Efficiency:    "); 
        print_speedup(t_npu_pio, t_npu_dma); hal_uart_puts("x\n\r");
        
        hal_uart_puts("\n\r>>> SYSTEM VERIFIED & BENCHMARKED <<<\n\r");

    } else {

        hal_uart_puts("\n\r>>> BENCHMARK INCOMPLETE <<<\n\r");

    }

    // ------------------------------------------------------------------------
    // 4. LOCALITY TEST (DATA REUSE)
    // ------------------------------------------------------------------------

    hal_uart_puts("\n\r-----------------------------------------------\n\r");
    hal_uart_puts("             LOCALITY / REUSE TEST             \n\r");
    hal_uart_puts("-----------------------------------------------\n\n\r");
    hal_uart_puts("Scenario: 1 Image x 16 Filters (K=2048)\n\r");

    uint64_t t_bad = 0, t_good = 0;

    // BAD LOCALITY

    hal_uart_puts("[A] No Reuse (Reload Input)... ");
    hal_npu_set_dma_enabled(true);
    npu_setup();
    
    start = hal_timer_get_cycles();
    workload_locality_bad();
    end = hal_timer_get_cycles();
    
    t_bad = (end - start);
    hal_uart_puts("Done.\n\r");

    // GOOD LOCALITY

    hal_uart_puts("[B] Input Reuse (Static Input)... ");
    npu_setup(); 
    
    start = hal_timer_get_cycles();
    workload_locality_good();
    end = hal_timer_get_cycles();
    
    t_good = (end - start);
    hal_uart_puts("Done.\n\r");

    // REPORT 2: LOCALITY

    hal_uart_puts("\n\rCycles (16 Filters):\n\r");
    hal_uart_puts("  No Reuse: "); print_u64_hex(t_bad); hal_uart_puts("\n\r");
    hal_uart_puts("  Reuse:    "); print_u64_hex(t_good); hal_uart_puts("\n\r");
    
    hal_uart_puts("\n\rReuse Efficiency Gain:    "); 
    print_speedup(t_bad, t_good); hal_uart_puts("x\n\r");
    
    hal_uart_puts("\n\r>>> LOCALITY TEST COMPLETED <<<\n\r");
    
    while(1);
    return 0;   

}