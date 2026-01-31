#ifndef MATH_OPS_H
#define MATH_OPS_H

#include <stdint.h>

/* ============================================================================
 * SOFT-MATH LIBRARY HEADERS (RV32I Support)
 * ============================================================================
 */

// Operações de 32 bits
int32_t  __mulsi3(int32_t a, int32_t b);
uint32_t __udivsi3(uint32_t n, uint32_t d);
uint32_t __umodsi3(uint32_t n, uint32_t d);
int32_t  __divsi3(int32_t a, int32_t b);
int32_t  __modsi3(int32_t a, int32_t b);

// Operações de 64 bits
int64_t  __muldi3(int64_t a, int64_t b);

#endif /* MATH_OPS_H */