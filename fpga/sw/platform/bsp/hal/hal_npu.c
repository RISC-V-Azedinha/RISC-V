#include "hal_npu.h"
#include "memory_map.h"

// Helper para empacotar bytes
static inline uint32_t pack_bytes(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return ((uint8_t)b0) | 
           ((uint8_t)b1 << 8) | 
           ((uint8_t)b2 << 16) | 
           ((uint8_t)b3 << 24);
}

void hal_npu_init(void) {
    // 1. Zera controle e configurações iniciais
    NPU_REG_CTRL = 0;
    NPU_REG_QUANT = 0;
    NPU_REG_MULT = 0;

    // 2. Zera os Bias (Crucial para testes independentes)
    // Endereços 0x20, 0x24, 0x28, 0x2C
    for(int i=0; i<4; i++) {
        volatile uint32_t *bias_reg = (volatile uint32_t *)(NPU_BASE_ADDR + 0x20 + (i*4));
        *bias_reg = 0;
    }

    // 3. Reset Lógico nos Acumuladores
    NPU_REG_CTRL = NPU_CTRL_ACC_CLEAR;
    for(volatile int i=0; i<100; i++);
    NPU_REG_CTRL = 0;
}

void hal_npu_config(uint8_t shift, uint8_t zero_point, uint32_t multiplier) {
    uint32_t quant_val = (shift & 0x1F) | ((zero_point & 0xFF) << 8);
    NPU_REG_QUANT = quant_val;
    NPU_REG_MULT = multiplier;
}

void hal_npu_set_ctrl(uint32_t flags) {
    NPU_REG_CTRL = flags;
}

void hal_npu_write_weight(int8_t w0, int8_t w1, int8_t w2, int8_t w3) {
    while (NPU_REG_STATUS & NPU_STATUS_W_FULL);
    NPU_FIFO_WEIGHTS = pack_bytes(w0, w1, w2, w3);
}

void hal_npu_write_input(int8_t i0, int8_t i1, int8_t i2, int8_t i3) {
    while (NPU_REG_STATUS & NPU_STATUS_IN_FULL);
    NPU_FIFO_ACT = pack_bytes(i0, i1, i2, i3);
}

uint32_t hal_npu_read_output(void) {
    while (!(NPU_REG_STATUS & NPU_STATUS_OUT_RDY));
    return NPU_FIFO_OUT;
}

int hal_npu_result_ready(void) {
    return (NPU_REG_STATUS & NPU_STATUS_OUT_RDY) ? 1 : 0;
}