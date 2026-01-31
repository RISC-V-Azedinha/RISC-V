#ifndef HAL_TIMER_H
#define HAL_TIMER_H

#include <stdint.h>
#include "memory_map.h"

#define SYSTEM_CLOCK_HZ 100000000       // 100 MHz

// ============================================================================
// API INLINE 
// ============================================================================

/**
 * @brief Reinicia o contador de tempo (Escreve 0 no mtime).
 */
static inline void hal_timer_reset(void) {
    // Para segurança, escrevemos -1 no CMP antes para evitar IRQ espúria durante o reset
    CLINT_MTIMECMP_LO = 0xFFFFFFFF;
    CLINT_MTIMECMP_HI = 0xFFFFFFFF;
    
    CLINT_MTIME_LO = 0;
    CLINT_MTIME_HI = 0;
}

/**
 * @brief Captura o tempo atual de forma atômica.
 * @return Ciclos contados (64-bit).
 * * Lê os registradores MTIME. Como estamos em 32-bit lendo 64-bit,
 * precisamos garantir que o High não mudou durante a leitura do Low.
 */
static inline uint64_t hal_timer_get_cycles(void) {
    uint32_t hi, lo, hi2;

    do {
        hi  = CLINT_MTIME_HI;
        lo  = CLINT_MTIME_LO;
        hi2 = CLINT_MTIME_HI;
    } while (hi != hi2); // Repete se houve overflow do Low para o High durante a leitura
    
    return ((uint64_t)hi << 32) | lo;
}

/**
 * @brief Define o valor de comparação para gerar interrupção.
 * @param cycles Valor absoluto em ciclos para disparar a IRQ.
 */
static inline void hal_clint_set_cmp(uint64_t cycles) {
    // Programamos o High como MAX primeiro para evitar disparo acidental
    CLINT_MTIMECMP_HI = 0xFFFFFFFF; 
    CLINT_MTIMECMP_LO = (uint32_t)(cycles & 0xFFFFFFFF);
    CLINT_MTIMECMP_HI = (uint32_t)(cycles >> 32);
}

/**
 * @brief Configura o timer para gerar uma interrupção daqui a N ciclos.
 * @param delta_cycles Quantidade de ciclos a esperar.
 */
static inline void hal_timer_set_irq_delta(uint64_t delta_cycles) {
    uint64_t now = hal_timer_get_cycles();
    hal_clint_set_cmp(now + delta_cycles);
}

/**
 * @brief Desativa (ack) a interrupção do timer jogando o comparador para o infinito.
 */
static inline void hal_timer_irq_ack(void) {
    hal_clint_set_cmp(0xFFFFFFFFFFFFFFFF);
}

// ============================================================================
// FUNÇÕES DE DELAY (Implementadas no .c)
// ============================================================================

void hal_timer_delay_us(uint32_t us);
void hal_timer_delay_ms(uint32_t ms);

#endif /* HAL_TIMER_H */