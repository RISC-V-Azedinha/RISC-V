#include "hal_timer.h"
#include "math_ops.h"

// ============================================================================
// FUNÇÕES DE DELAY (BLOQUEANTE)
// ============================================================================

void hal_timer_delay_us(uint32_t us) {

    uint64_t start = hal_timer_get_cycles();
    
    // Otimização Bare-Metal:
    // 1 us = 100 ciclos (@ 100MHz).
    // Nota: Cuidado com overflow se us for muito grande (uint32_t max * 100).
    uint64_t cycles_to_wait = (uint64_t)us * (SYSTEM_CLOCK_HZ / 1000000);
    
    while ((hal_timer_get_cycles() - start) < cycles_to_wait);

}

void hal_timer_delay_ms(uint32_t ms) {

    uint64_t start = hal_timer_get_cycles();
    
    // 1 ms = 100.000 ciclos (@ 100MHz).
    uint64_t cycles_to_wait = (uint64_t)ms * (SYSTEM_CLOCK_HZ / 1000);
    
    while ((hal_timer_get_cycles() - start) < cycles_to_wait);
    
}