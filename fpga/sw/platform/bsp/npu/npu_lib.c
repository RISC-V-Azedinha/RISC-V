#include "npu_lib.h"
#include "hal/hal_npu.h"
#include "memory_map.h"

static uint32_t current_flags = 0;

vec4_t vec4(int8_t v0, int8_t v1, int8_t v2, int8_t v3) {
    vec4_t v; v.val[0]=v0; v.val[1]=v1; v.val[2]=v2; v.val[3]=v3;
    return v;
}

static void drain_output_fifo(void) {
    while (hal_npu_result_ready()) {
        volatile uint32_t junk = hal_npu_read_output();
        (void)junk; 
    }
}

static void flush_pipeline() {
    for(int i=0; i<8; i++) hal_npu_write_input(0,0,0,0);
}

void npu_reset_system(void) {
    MMIO32(NPU_BASE_ADDR+0x20)=0; MMIO32(NPU_BASE_ADDR+0x24)=0;
    MMIO32(NPU_BASE_ADDR+0x28)=0; MMIO32(NPU_BASE_ADDR+0x2C)=0;
    hal_npu_config(0, 0, 1);
    current_flags = 0;

    // Reset limpo
    hal_npu_set_ctrl(NPU_CTRL_ACC_CLEAR | NPU_CTRL_LOAD);
    flush_pipeline(); 
    hal_npu_set_ctrl(NPU_CTRL_ACC_CLEAR);
    for(volatile int i=0; i<100; i++);
    hal_npu_set_ctrl(0);

    drain_output_fifo();
}

void npu_configure(uint8_t shift, uint32_t mult, const int32_t bias[4], uint8_t use_relu) {
    // SEM PATCHES MATEMÁTICOS - HARDWARE CORRIGIDO
    hal_npu_config(shift, 0, mult);
    
    if (bias) {
        for(int i=0; i<4; i++) MMIO32(NPU_BASE_ADDR + 0x20 + (i*4)) = bias[i];
    } else {
        for(int i=0; i<4; i++) MMIO32(NPU_BASE_ADDR + 0x20 + (i*4)) = 0;
    }

    current_flags = use_relu ? NPU_CTRL_RELU : 0;
}

void npu_load_weights(const mat4_t* w) {
    hal_npu_set_ctrl(NPU_CTRL_LOAD);
    for(int r=3; r>=0; r--) {
        hal_npu_write_weight(w->data[r][0], w->data[r][1], w->data[r][2], w->data[r][3]);
    }
    for(volatile int i=0; i<200; i++); 
    hal_npu_set_ctrl(0);
}

vec4_t npu_execute(vec4_t in) {
    drain_output_fifo();

    // 1. Reset Acumulador
    hal_npu_set_ctrl(current_flags | NPU_CTRL_ACC_CLEAR);
    hal_npu_write_input(0,0,0,0);
    for(volatile int i=0; i<50; i++); 
    hal_npu_set_ctrl(current_flags);

    // 2. Execução (Sem necessidade de pausa complexa, mas mantemos o flush)
    hal_npu_write_input(in.val[0], in.val[1], in.val[2], in.val[3]);
    flush_pipeline();

    // 3. Dump
    hal_npu_set_ctrl(current_flags | NPU_CTRL_DUMP);
    hal_npu_write_input(0,0,0,0);

    while (!hal_npu_result_ready());
    uint32_t raw = hal_npu_read_output();
    hal_npu_set_ctrl(current_flags);

    vec4_t out;
    out.val[0] = (raw >> 0) & 0xFF;
    out.val[1] = (raw >> 8) & 0xFF;
    out.val[2] = (raw >> 16) & 0xFF;
    out.val[3] = (raw >> 24) & 0xFF;
    return out;
}