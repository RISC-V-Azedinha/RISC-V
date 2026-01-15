#include <stdint.h>
#include "hal/hal_uart.h"
#include "npu/npu_lib.h"
#include "npu/tiny_ml.h"

// ==========================================
// CONFIGURAÇÃO DA REDE XOR (CORRIGIDA)
// ==========================================

// --- Layer 1 ---

const int8_t w1[] = {
    // In0, In1
      1,   1,   // N0: Soma (Índices 0, 1)
      1,   1,   // N1: Threshold (Índices 2, 3)
      0,   0,   // N2: Lixo (Índices 4, 5)
      0,   0    // N3: Lixo (Índices 6, 7)
};

// Bias: N0=0, N1=-20
const int32_t b1[] = {0, -20, 0, 0}; 

// --- Layer 2 ---

const int8_t w2[] = {
    // H0,  H1,  H2,  H3
      3,  -6,   0,   0   
};
const int32_t b2[] = {0}; 

const layer_dense_t l1 = {
    .weights = w1, .bias = b1,
    .in_features = 2, .out_neurons = 4, 
    .output_shift = 0, .output_mult = 1, .use_relu = 1
};

const layer_dense_t l2 = {
    .weights = w2, .bias = b2,
    .in_features = 4, .out_neurons = 1,
    .output_shift = 0, .output_mult = 1, .use_relu = 0
};

// ==========================================
// UTILS
// ==========================================
void print_val(int8_t val) {
    char hex[] = "0123456789ABCDEF";
    hal_uart_putc(hex[(val >> 4) & 0xF]);
    hal_uart_putc(hex[val & 0xF]);
}

void print_array(const char* name, int8_t* data, int len) {
    hal_uart_puts(name); hal_uart_puts("[");
    for(int i=0; i<len; i++) {
        print_val(data[i]);
        if(i < len-1) hal_uart_puts(" ");
    }
    hal_uart_puts("]");
}

// ==========================================
// MAIN
// ==========================================
void main(void) {
    hal_uart_init();
    hal_uart_puts("\n\r=== TINY ML ENGINE (XOR FINAL) ===\n\r");
    
    ml_init(); 
    
    int8_t input[4];  
    int8_t hidden[4]; 
    int8_t output[4]; 

    int cases[4][2] = {{0,0}, {0,1}, {1,0}, {1,1}};
    int expected_logic[4] = {0, 1, 1, 0}; 

    int pass_count = 0;

    for(int i=0; i<4; i++) {
        // PREPARA INPUT (0 ou 20)
        for(int k=0; k<4; k++) input[k]=0;
        input[0] = cases[i][0] ? 20 : 0;
        input[1] = cases[i][1] ? 20 : 0;
        
        hal_uart_puts("--------------------------------\n");
        hal_uart_puts("CASE: "); 
        hal_uart_putc('0'+cases[i][0]); hal_uart_putc(',');
        hal_uart_putc('0'+cases[i][1]); hal_uart_puts("\n");

        // 1. Roda L1 (2 inputs -> 4 neurons)
        ml_run_layer(&l1, input, hidden);
        print_array("   Hidden Raw: ", hidden, 4); hal_uart_puts("\n");

        // 2. Roda L2 (4 inputs -> 1 neuron)
        ml_run_layer(&l2, hidden, output);
        print_array("   Output Raw: ", output, 1); hal_uart_puts("\n");

        // VALIDAÇÃO
        int val = output[0];
        int logic_detected = (val > 30) ? 1 : 0;
        int logic_expected = expected_logic[i];

        if (logic_detected == logic_expected) {
            hal_uart_puts("   STATUS: [PASS]\n");
            pass_count++;
        } else {
            hal_uart_puts("   STATUS: [FAIL] Expected ");
            hal_uart_putc('0'+logic_expected);
            hal_uart_puts(", Got ");
            hal_uart_putc('0'+logic_detected);
            hal_uart_puts("\n");
        }
    }
    
    hal_uart_puts("================================\n");
    if (pass_count == 4) {
        hal_uart_puts("SUCESSO: REDE NEURAL FUNCIONAL!\n");
    } else {
        hal_uart_puts("FALHA: VERIFIQUE PESOS/LOGICA.\n");
    }
    
    while(1);
}