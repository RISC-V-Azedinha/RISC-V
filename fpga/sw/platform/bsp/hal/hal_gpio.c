#include "hal_gpio.h"

// ============================================================================
// DISPLAYS DE 7 SEGMENTOS
// ============================================================================

void hal_seg7_write_dec(uint32_t value) {
    uint32_t bcd = 0, digits = 0;

    // Converte para BCD por divisões sucessivas (o RV32I não tem divisão em hardware,
    // mas o compilador gera a rotina de software)
    do {
        bcd |= (value % 10) << (4 * digits);
        value /= 10;
        digits++;
    } while (value != 0 && digits < 8);

    SEG7_REG_CTRL = 0;
    SEG7_REG_HEX  = bcd;
    SEG7_REG_EN   = (1u << digits) - 1;          // acende só os dígitos usados
}

void hal_seg7_set_raw(uint32_t digit, uint8_t segments) {
    volatile uint32_t *reg = (digit < 4) ? &SEG7_REG_RAW_LO : &SEG7_REG_RAW_HI;
    uint32_t shift = 8 * (digit & 3);
    *reg = (*reg & ~(0xFFu << shift)) | ((uint32_t)segments << shift);
    SEG7_REG_CTRL = SEG7_CTRL_RAW;
}
