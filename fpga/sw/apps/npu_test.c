#include <stdint.h>
#include "hal/hal_uart.h"
#include "npu/npu_lib.h"

// =========================================================
// ESTATÍSTICAS & VISUALIZAÇÃO
// =========================================================
static int g_total;
static int g_pass;
static int g_fail;

void print_byte(uint8_t val) {
    char hex[] = "0123456789ABCDEF";
    hal_uart_putc(hex[(val >> 4) & 0xF]);
    hal_uart_putc(hex[val & 0xF]);
}

void print_vec_log(const char* label, vec4_t v) {
    hal_uart_puts("   ");
    hal_uart_puts(label);
    hal_uart_puts("["); 
    print_byte(v.val[0]); hal_uart_puts(" "); print_byte(v.val[1]); hal_uart_puts(" ");
    print_byte(v.val[2]); hal_uart_puts(" "); print_byte(v.val[3]); 
    hal_uart_puts("]");
}

void print_matrix_log(const mat4_t* m) {
    hal_uart_puts("   Pesos:\n");
    for(int r=0; r<4; r++) {
        hal_uart_puts("      [ ");
        for(int c=0; c<4; c++) {
            print_byte((uint8_t)m->data[r][c]); hal_uart_puts(" ");
        }
        hal_uart_puts("]\n");
    }
}

void check(vec4_t actual, int8_t e0, int8_t e1, int8_t e2, int8_t e3) {
    g_total++;
    int pass = (actual.val[0]==e0 && actual.val[1]==e1 && actual.val[2]==e2 && actual.val[3]==e3);
    
    if (pass) {
        g_pass++;
        hal_uart_puts("   STATUS: [PASS] ");
        print_vec_log("Got: ", actual); hal_uart_puts("\n");
    } else {
        g_fail++;
        hal_uart_puts("   STATUS: [FAIL] !!!\n");
        vec4_t exp = vec4(e0, e1, e2, e3);
        print_vec_log("Exp: ", exp); hal_uart_puts("\n");
        print_vec_log("Got: ", actual); hal_uart_puts("\n");
    }
    hal_uart_puts("--------------------------------------------------\n");
}

// =========================================================
// TESTES
// =========================================================

void test_1_identity() {
    hal_uart_puts("[TEST 1] Matriz Identidade\n");
    hal_uart_puts("   Desc: Input * Identity = Input. Verifica mapeamento basico.\n");
    npu_reset_system();

    mat4_t id = {{{1,0,0,0}, {0,1,0,0}, {0,0,1,0}, {0,0,0,1}}};
    print_matrix_log(&id);
    npu_load_weights(&id);
    
    vec4_t in = vec4(10, 20, 30, 40);
    print_vec_log("In : ", in); hal_uart_puts("\n");

    vec4_t res = npu_execute(in);
    check(res, 10, 20, 30, 40);
}

void test_2_signed() {
    hal_uart_puts("[TEST 2] Matematica com Sinal\n");
    hal_uart_puts("   Desc: Multiplicacao por -1. Verifica complemento de dois.\n");
    npu_reset_system();

    mat4_t neg = {{{-1,0,0,0}, {0,-1,0,0}, {0,0,-1,0}, {0,0,0,-1}}};
    print_matrix_log(&neg);
    npu_load_weights(&neg);

    vec4_t in = vec4(10, -20, 5, -5);
    print_vec_log("In : ", in); hal_uart_puts("\n");

    vec4_t res = npu_execute(in);
    // Exp: -10 (F6), 20 (14), -5 (FB), 5 (05)
    check(res, -10, 20, -5, 5);
}

void test_3_clamp() {
    hal_uart_puts("[TEST 3] Saturacao (Clamping)\n");
    hal_uart_puts("   Desc: Soma > 127 deve travar em 127 (7F).\n");
    npu_reset_system();

    mat4_t big = {{{100,100,100,100}, {0,0,0,0}, {0,0,0,0}, {0,0,0,0}}};
    print_matrix_log(&big);
    npu_load_weights(&big);

    vec4_t in = vec4(2, 0, 0, 0);
    print_vec_log("In : ", in); hal_uart_puts("\n");

    // 2 * 100 = 200 -> Clamp 127
    check(npu_execute(in), 127, 127, 127, 127);
}

void test_4_pipeline() {
    hal_uart_puts("[TEST 4] Full Pipeline (Bias + ReLU)\n");
    hal_uart_puts("   Desc: (Input - 10). Se resultado < 0, ReLU zera.\n");
    npu_reset_system();

    mat4_t id = {{{1,0,0,0}, {0,1,0,0}, {0,0,1,0}, {0,0,0,1}}};
    print_matrix_log(&id);
    npu_load_weights(&id);

    hal_uart_puts("   Cfg : Bias = -10, ReLU = ON\n");
    int32_t bias[4] = {-10, -10, -10, -10};
    npu_configure(0, 1, bias, 1); // Shift=0, Mult=1, ReLU=ON

    vec4_t in = vec4(5, 20, 0, 15);
    print_vec_log("In : ", in); hal_uart_puts("\n");

    vec4_t res = npu_execute(in);
    // 5-10=-5(0), 20-10=10, 0-10=-10(0), 15-10=5
    check(res, 0, 10, 0, 5);
}

void test_5_batch() {
    hal_uart_puts("[TEST 5] Batch Processing\n");
    hal_uart_puts("   Desc: Processa sequencia sem recarregar pesos.\n");
    npu_reset_system();

    mat4_t mat = {{{1,2,1,0}, {1,2,0,0}, {1,2,0,0}, {1,2,0,0}}};
    print_matrix_log(&mat);
    npu_load_weights(&mat);

    hal_uart_puts("   >> Batch 1:\n");
    vec4_t in1 = vec4(1,1,1,1);
    print_vec_log("In : ", in1); hal_uart_puts("\n");
    check(npu_execute(in1), 4, 8, 1, 0);

    hal_uart_puts("   >> Batch 2:\n");
    vec4_t in2 = vec4(2,0,0,0);
    print_vec_log("In : ", in2); hal_uart_puts("\n");
    check(npu_execute(in2), 2, 4, 2, 0);
}

// =========================================================
// MAIN
// =========================================================
void main(void) {
    
    g_total = 0;
    g_pass = 0;
    g_fail = 0;

    hal_uart_init();
    hal_uart_puts("\n\r");
    hal_uart_puts("==========================================\n\r");
    hal_uart_puts("      NPU ULTIMATE TEST (LIB VER)         \n\r");
    hal_uart_puts("==========================================\n\r");

    test_1_identity();
    test_2_signed();
    test_3_clamp();
    test_4_pipeline();
    test_5_batch();

    hal_uart_puts("==========================================\n\r");
    hal_uart_puts("RESUMO FINAL:\n\r");
    hal_uart_puts("   Total : "); print_byte(g_total); hal_uart_puts("\n\r");
    hal_uart_puts("   Pass  : "); print_byte(g_pass);  hal_uart_puts("\n\r");
    hal_uart_puts("   Fail  : "); print_byte(g_fail);  hal_uart_puts("\n\r");

    if (g_fail == 0) {
        hal_uart_puts("\n   STATUS: SISTEMA OPERACIONAL (READY)!\n\r");
    } else {
        hal_uart_puts("\n   STATUS: ERROS DETECTADOS.\n\r");
    }

    while(1); 
}