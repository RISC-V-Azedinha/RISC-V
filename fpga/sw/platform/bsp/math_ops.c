#include "math_ops.h"
#include <stdint.h>

/* * Software para Operações Matemáticas (RV32I) */

// --- Multiplicação (Signed 32-bit) ---
// Usada pelo compilador para operador '*'
int32_t __mulsi3(int32_t a, int32_t b) {
    int32_t res = 0;
    while (b != 0) {
        if (b & 1) res += a;
        a <<= 1;
        b = (uint32_t)b >> 1; 
    }
    return res;
}

// --- Divisão (Unsigned 32-bit) ---
// Auxiliar para as funções abaixo
uint32_t __udivsi3(uint32_t n, uint32_t d) {
    uint32_t q = 0;
    uint32_t r = 0;
    // Algoritmo de divisão binária "restoring" simples
    for (int i = 31; i >= 0; i--) {
        r <<= 1;
        r |= (n >> i) & 1;
        if (r >= d) {
            r -= d;
            q |= (1U << i);
        }
    }
    return q;
}

// --- Resto (Unsigned 32-bit) ---
// Auxiliar
uint32_t __umodsi3(uint32_t n, uint32_t d) {
    uint32_t r = 0;
    for (int i = 31; i >= 0; i--) {
        r <<= 1;
        r |= (n >> i) & 1;
        if (r >= d) {
            r -= d;
        }
    }
    return r;
}

// --- Divisão (Signed 32-bit) ---
// Usada pelo compilador para operador '/'
int32_t __divsi3(int32_t a, int32_t b) {
    int neg = 0;
    if (a < 0) { a = -a; neg = !neg; }
    if (b < 0) { b = -b; neg = !neg; }
    int32_t res = __udivsi3(a, b);
    return neg ? -res : res;
}

// --- Resto (Signed 32-bit) ---
// Usada pelo compilador para operador '%'
int32_t __modsi3(int32_t a, int32_t b) {
    int neg = 0;
    if (a < 0) { a = -a; neg = 1; }
    if (b < 0) { b = -b; }
    int32_t res = __umodsi3(a, b);
    return neg ? -res : res;
}

// Multiplicação 64-bit 
int64_t __muldi3(int64_t a, int64_t b) {
    uint64_t ua = (uint64_t)a;
    uint64_t ub = (uint64_t)b;
    uint64_t res = 0;

    // Mesma lógica do 32-bit, mas com registradores de 64-bit
    while (ub != 0) {
        if (ub & 1) res += ua;
        ua <<= 1;
        ub >>= 1;
    }
    return (int64_t)res;
}