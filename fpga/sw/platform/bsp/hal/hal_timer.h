#ifndef HAL_TIMER_H
#define HAL_TIMER_H

#include <stdint.h>
#include "memory_map.h"

// ============================================================================
// DEFINIÇÕES DE HARDWARE (ATOMIC SNAPSHOT)
// ============================================================================

#define TIMER_REG_CTRL  MMIO32(TIMER_BASE_ADDR + 0x00)
#define TIMER_REG_LOW   MMIO32(TIMER_BASE_ADDR + 0x04)
#define TIMER_REG_HIGH  MMIO32(TIMER_BASE_ADDR + 0x08)

// Bits de Controle
#define TIMER_CMD_ENABLE    (1 << 0)    // 1=Rodando, 0=Parado
#define TIMER_CMD_RESET     (1 << 1)    // 1=Zera Contador (Auto-clear)
#define TIMER_CMD_SNAPSHOT  (1 << 2)    // 1=Atualiza Shadow Regs (Auto-clear)

#define SYSTEM_CLOCK_HZ 100000000       // 100 MHz

// ============================================================================
// API INLINE 
// ============================================================================

// A função é declarada como inline para evitar o overhead fixo de
// chamada de função, que poderia introduzir ruído nas medições de
// temporização em benchmarks de baixa latência.

/**
 * @brief Reinicia o timer (Zera e Para).
 */
static inline void hal_timer_reset(void) {
    TIMER_REG_CTRL = TIMER_CMD_RESET; 
}

/**
 * @brief Inicia a contagem.
 */
static inline void hal_timer_start(void) {

    // Escreve apenas o bit ENABLE.
    // O hardware mantém o contador incrementando.
    TIMER_REG_CTRL = TIMER_CMD_ENABLE;

}

/**
 * @brief Para a contagem (congela o valor atual).
 */
static inline void hal_timer_stop(void) {

    TIMER_REG_CTRL = 0; // ENABLE=0

}

/**
 * @brief Captura o tempo atual de forma atômica.
 * @return Ciclos contados (64-bit).
 * * Esta função envia o comando SNAPSHOT para o hardware, que copia 
 * o contador interno para os registradores de leitura instantaneamente.
 */
static inline uint64_t hal_timer_get_cycles(void) {

    // 1. Dispara o Snapshot.
    // Mantemos o bit ENABLE ligado para não parar a contagem enquanto lemos.
    TIMER_REG_CTRL = TIMER_CMD_ENABLE | TIMER_CMD_SNAPSHOT;
    
    // 2. Lê os registradores de sombra (Shadow Registers).
    // Como são estáticos (até o próximo snapshot), a ordem de leitura não importa.
    uint32_t lo = TIMER_REG_LOW;
    uint32_t hi = TIMER_REG_HIGH;
    
    return ((uint64_t)hi << 32) | lo;
    
}

// ============================================================================
// FUNÇÕES DE DELAY (Implementadas no .c)
// ============================================================================

void hal_timer_delay_us(uint32_t us);
void hal_timer_delay_ms(uint32_t ms);

#endif /* HAL_TIMER_H */