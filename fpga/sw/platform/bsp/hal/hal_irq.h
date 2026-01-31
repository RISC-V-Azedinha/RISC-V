#ifndef HAL_IRQ_H
#define HAL_IRQ_H

#include <stdint.h>
#include <stdbool.h>

// Máscaras de Interrupção
#define IRQ_M_SOFT   (1 << 3)  // Machine Software Interrupt
#define IRQ_M_TIMER  (1 << 7)  // Machine Timer Interrupt
#define IRQ_M_EXT    (1 << 11) // Machine External Interrupt

// ============================================================================
// API DE CONTROLE DE INTERRUPÇÕES
// ============================================================================

/**
 * @brief Habilita Interrupções Globais (MSTATUS.MIE).
 */
static inline void hal_irq_global_enable(void) {
    // Usa CSRS (Set Bit) - Assume que o hardware suporta ou usaremos workaround
    // Se o hardware falhar com CSRS, trocamos por CSRW (Read-Modify-Write manual)
    unsigned long mie_bit = (1 << 3);
    asm volatile ("csrs mstatus, %0" :: "r"(mie_bit));
}

/**
 * @brief Desabilita Interrupções Globais (MSTATUS.MIE).
 */
static inline void hal_irq_global_disable(void) {
    unsigned long mie_bit = (1 << 3);
    asm volatile ("csrc mstatus, %0" :: "r"(mie_bit));
}

/**
 * @brief Habilita interrupções específicas (MIE).
 * @param mask Máscara de bits (ex: IRQ_M_TIMER | IRQ_M_SOFT).
 */
static inline void hal_irq_mask_enable(uint32_t mask) {
    // WORKAROUND: Se o hardware tiver bug com CSRS no endereço MIE (0x304)
    // podemos implementar como Read-Modify-Write manual se necessário.
    // Por enquanto, usamos a instrução padrão.
    asm volatile ("csrs mie, %0" :: "r"(mask));
}

/**
 * @brief Desabilita interrupções específicas (MIE).
 * @param mask Máscara de bits a desabilitar.
 */
static inline void hal_irq_mask_disable(uint32_t mask) {
    asm volatile ("csrc mie, %0" :: "r"(mask));
}

/**
 * @brief Configura o endereço do Trap Handler (MTVEC).
 * @param handler_addr Ponteiro para a função de tratamento.
 */
static inline void hal_irq_set_handler(void (*handler_addr)(void)) {
    // Garante modo DIRECT (bits 1:0 = 00)
    uint32_t val = (uint32_t)handler_addr & ~0x3;
    asm volatile ("csrw mtvec, %0" :: "r"(val));
}

#endif // HAL_IRQ_H