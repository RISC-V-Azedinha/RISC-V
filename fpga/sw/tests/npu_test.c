#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_npu.h"

// ============================================================================
// UTILITÁRIOS LOCAIS
// ============================================================================

void print_hex(uint32_t val) {
    char hex_chars[] = "0123456789ABCDEF";
    hal_uart_puts("0x");
    for (int i = 7; i >= 0; i--) {
        hal_uart_putc(hex_chars[(val >> (i * 4)) & 0xF]);
    }
}

void panic(const char* msg) {
    hal_uart_puts("\n\r[FATAL] ");
    hal_uart_puts(msg);
    hal_uart_puts("\n\r");
    while(1);
}

// ============================================================================
// CENÁRIOS DE TESTE (Encapsulados para reuso)
// ============================================================================

void test_accumulation_basic() {
    hal_uart_puts("  [1/3] Teste Basico (MAC)... ");
    
    hal_npu_init();
    npu_quant_params_t config = { .mult = 1, .shift = 0, .zero_point = 0, .relu = false };
    hal_npu_configure(4, &config);

    uint32_t inputs[4];
    uint32_t weights[4];
    for (int i = 0; i < 4; i++) {
        inputs[i]  = 0x01010101; 
        weights[i] = 0x0A0A0A0A; 
    }

    hal_npu_load_inputs(inputs, 4);
    hal_npu_load_weights(weights, 4);

    hal_npu_start();
    hal_npu_wait_done();

    uint32_t results[4];
    hal_npu_read_output(results, 4);

    int erros = 0;
    for (int i = 0; i < 4; i++) {
        if (results[i] != 0x28282828) erros++;
    }

    if (erros == 0) hal_uart_puts("PASSOU\n\r");
    else {
        hal_uart_puts("FALHOU\n\r");
        panic("Erro de calculo basico.");
    }
}

void test_deep_accumulation() {
    hal_uart_puts("  [2/3] Teste de Stress (K=60)... ");
    
    uint32_t K_DIM = 60;
    hal_npu_init();
    npu_quant_params_t config = { .mult = 1, .shift = 0, .zero_point = 0, .relu = false };
    hal_npu_configure(K_DIM, &config);

    uint32_t val_input = 0x02020202; 
    uint32_t val_weight = 0x01010101; 
    
    // Nota: Mesmo carregando 1 a 1, se o DMA estiver ativo, 
    // a HAL vai disparar 60 transações de DMA pequenas. 
    // Ineficiente, mas excelente teste de robustez do arbiter!
    for (int k = 0; k < K_DIM; k++) {
        hal_npu_load_inputs(&val_input, 1);
        hal_npu_load_weights(&val_weight, 1);
    }

    hal_npu_start();
    hal_npu_wait_done();

    uint32_t results[4];
    hal_npu_read_output(results, 4);

    int erros = 0;
    for (int i = 0; i < 4; i++) {
        if (results[i] != 0x78787878) erros++;
    }

    if (erros == 0) hal_uart_puts("PASSOU\n\r");
    else panic("Erro na contagem de ciclos.");
}

void test_relu_activation() {
    hal_uart_puts("  [3/3] Teste de ReLU... ");
    
    hal_npu_init();
    npu_quant_params_t config_off = { .mult = 1, .shift = 0, .zero_point = 0, .relu = false };
    hal_npu_configure(4, &config_off);

    uint32_t inputs[4];
    uint32_t weights[4];
    for (int i = 0; i < 4; i++) {
        inputs[i]  = 0x05050505; 
        weights[i] = 0xFEFEFEFE; 
    }
    
    hal_npu_load_inputs(inputs, 4);
    hal_npu_load_weights(weights, 4);
    
    hal_npu_start();
    hal_npu_wait_done();
    
    uint32_t results_raw[4];
    hal_npu_read_output(results_raw, 4);

    if ((results_raw[0] & 0xFF) != 0xD8) panic("Erro de sinal.");

    // Parte B: ReLU ON
    npu_quant_params_t config_on = { .mult = 1, .shift = 0, .zero_point = 0, .relu = true };
    hal_npu_configure(4, &config_on);
    
    hal_npu_start();
    hal_npu_wait_done();

    uint32_t results_relu[4];
    hal_npu_read_output(results_relu, 4);
    
    if (results_relu[0] != 0x00000000) panic("ReLU inoperante.");

    hal_uart_puts("PASSOU\n\r");
}

// ============================================================================
// MAIN
// ============================================================================

void run_all_tests() {
    test_accumulation_basic();
    test_deep_accumulation();
    test_relu_activation();
}

int main() {
    hal_uart_init();
    
    // --- RODADA 1: CPU ONLY ---
    hal_uart_puts("\n\r===========================================\n\r");
    hal_uart_puts(" MODO 1: CPU WRITES (BIT-BANGING)\n\r");
    hal_uart_puts("===========================================\n\r");
    
    hal_npu_set_dma_enabled(false); // Desliga DMA
    run_all_tests();

    // --- RODADA 2: DMA ACCELERATED ---
    hal_uart_puts("\n\r===========================================\n\r");
    hal_uart_puts(" MODO 2: DMA ACCELERATED (FIXED DST)\n\r");
    hal_uart_puts("===========================================\n\r");
    
    hal_npu_set_dma_enabled(true); // Liga DMA
    run_all_tests();

    hal_uart_puts("\n\r=== TODOS OS TESTES (CPU & DMA) PASSARAM! ===\n\r");
    while(1);
    return 0;
    
}