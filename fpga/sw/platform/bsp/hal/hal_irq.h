#ifndef HAL_IRQ_H
#define HAL_IRQ_H

#include <stdint.h>
#include <stdbool.h>

// Máscaras de Interrupção
#define IRQ_M_SOFT   (1 << 3)  // Machine Software Interrupt
#define IRQ_M_TIMER  (1 << 7)  // Machine Timer Interrupt
#define IRQ_M_EXT    (1 << 11) // Machine External Interrupt

// ============================================================================
// DEFINIÇÕES DO DISPATCHER 
// ============================================================================

// Tipo para função de Callback (Handler)
typedef void (*irq_handler_t)(void);

/**
 * @brief Inicializa o sistema de interrupções centralizado.
 * - Configura o mtvec para o Dispatcher.
 * - Habilita interrupções externas no PLIC e na CPU.
 */
void hal_irq_init(void);

/**
 * @brief Registra uma função para tratar uma fonte específica do PLIC.
 * @param source_id ID da fonte (ex: PLIC_SOURCE_DMA).
 * @param handler Ponteiro para a função void minha_funcao(void).
 */
void hal_irq_register(uint32_t source_id, irq_handler_t handler);


// ============================================================================
// API DE CONTROLE DE INTERRUPÇÕES (INLINE)
// ============================================================================

/**
 * @brief Habilita Interrupções Globais (MSTATUS.MIE).
 */
static inline void hal_irq_global_enable(void) {
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