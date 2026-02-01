#ifndef HAL_PLIC_H
#define HAL_PLIC_H

#include <stdint.h>

// ============================================================================
// DEFINIÇÕES E CONSTANTES
// ============================================================================

// IDs das Fontes de Interrupção (Mapeamento do Hardware soc_top.vhd)
#define PLIC_SOURCE_NONE    0
#define PLIC_SOURCE_UART    1
#define PLIC_SOURCE_GPIO    2  // Reservado (futuro)
#define PLIC_SOURCE_DMA     3  // Reservado (futuro)
#define PLIC_SOURCE_NPU     4  // Reservado (futuro)

#define PLIC_MAX_SOURCES    32

// ============================================================================
// PROTÓTIPOS DA API
// ============================================================================

/**
 * @brief Inicializa o PLIC.
 * - Desabilita todas as fontes.
 * - Zera todas as prioridades.
 * - Define o Threshold como 0 (Permite tudo).
 */
void hal_plic_init(void);

/**
 * @brief Habilita uma fonte de interrupção específica para o Contexto 0 (Machine).
 * @param source_id ID da fonte (1 a 31).
 */
void hal_plic_enable(uint32_t source_id);

/**
 * @brief Desabilita uma fonte de interrupção.
 * @param source_id ID da fonte.
 */
void hal_plic_disable(uint32_t source_id);

/**
 * @brief Define a prioridade de uma fonte.
 * @param source_id ID da fonte.
 * @param priority Valor de 0 a 7 (7 = Mais urgente).
 */
void hal_plic_set_priority(uint32_t source_id, uint32_t priority);

/**
 * @brief Define o nível mínimo de prioridade para interromper o Core.
 * @param threshold Valor de 0 a 7.
 */
void hal_plic_set_threshold(uint32_t threshold);

/**
 * @brief Reivindica (Claim) a interrupção pendente de maior prioridade.
 * DEVE ser chamado no início do Handler de Interrupção Externa.
 * @return ID da fonte vencedora. Se retornar 0, não há interrupção pendente.
 */
uint32_t hal_plic_claim(void);

/**
 * @brief Finaliza (Complete) o tratamento da interrupção.
 * DEVE ser chamado no final do Handler, após tratar o dispositivo.
 * @param source_id O ID que foi retornado pelo hal_plic_claim().
 */
void hal_plic_complete(uint32_t source_id);

#endif // HAL_PLIC_H