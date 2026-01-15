#include "npu_lib.h"
#include "hal/hal_npu.h"
#include "memory_map.h"

static uint32_t current_flags = 0;

vec4_t vec4(int8_t v0, int8_t v1, int8_t v2, int8_t v3) {
    vec4_t v; v.val[0]=v0; v.val[1]=v1; v.val[2]=v2; v.val[3]=v3;
    return v;
}

static void flush() {
    for(int i=0; i<8; i++) hal_npu_write_input(0,0,0,0);
}

void npu_reset_system(void) {
    // 1. Zera Registradores
    MMIO32(NPU_BASE_ADDR+0x20)=0; MMIO32(NPU_BASE_ADDR+0x24)=0;
    MMIO32(NPU_BASE_ADDR+0x28)=0; MMIO32(NPU_BASE_ADDR+0x2C)=0;
    hal_npu_config(0, 0, 1);
    current_flags = 0;

    // 2. Limpa Pipeline (Dummy Clear)
    hal_npu_set_ctrl(NPU_CTRL_ACC_CLEAR);
    hal_npu_write_input(0,0,0,0); flush();
    hal_npu_set_ctrl(0);
}

void npu_configure(uint8_t shift, uint32_t mult, const int32_t bias[4], uint8_t use_relu) {
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
    // Delay para latch
    for(volatile int i=0; i<200; i++); 
    hal_npu_set_ctrl(0);
}

vec4_t npu_execute(vec4_t in) {
    // 1. Clear (Preservando flags)
    hal_npu_set_ctrl(current_flags | NPU_CTRL_ACC_CLEAR);
    hal_npu_write_input(0,0,0,0); flush();

    // 2. Compute
    hal_npu_set_ctrl(current_flags);
    hal_npu_write_input(in.val[0], in.val[1], in.val[2], in.val[3]);

    // 3. Dump
    hal_npu_set_ctrl(current_flags | NPU_CTRL_DUMP);
    flush();

    // 4. Read
    while (!(NPU_REG_STATUS & NPU_STATUS_OUT_RDY));
    uint32_t raw = NPU_FIFO_OUT;

    vec4_t out;
    out.val[0] = (raw >> 0) & 0xFF;
    out.val[1] = (raw >> 8) & 0xFF;
    out.val[2] = (raw >> 16) & 0xFF;
    out.val[3] = (raw >> 24) & 0xFF;
    return out;
}