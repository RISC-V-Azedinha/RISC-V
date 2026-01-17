#ifndef HAL_DMA_H
#define HAL_DMA_H

#include <stdint.h>

// =============================================================================
// DEFINIÇÕES DE HARDWARE (Baseado no bus_interconnect.vhd)
// =============================================================================
#define DMA_BASE_ADDR  0x40000000

// Mapeamento dos Registradores
typedef struct {
    volatile uint32_t SRC;   // 0x00: Endereço de Origem
    volatile uint32_t DST;   // 0x04: Endereço de Destino
    volatile uint32_t CNT;   // 0x08: Quantidade de palavras (32-bit)
    volatile uint32_t CTRL;  // 0x0C: Controle e Status
} dma_reg_t;

#define DMA ((dma_reg_t *)DMA_BASE_ADDR)

// Bits do Registrador de Controle (Baseado no dma_controller.vhd)
#define DMA_CTRL_START      (1 << 0) // Escrita: Inicia transferência
#define DMA_CTRL_BUSY       (1 << 0) // Leitura: 1 = Ocupado
#define DMA_CTRL_FIXED_DST  (1 << 1) // 1 = Destino Fixo (Útil para NPU/FIFO)

// =============================================================================
// PROTÓTIPOS
// =============================================================================

/**
 * @brief Verifica se o DMA está ocupado.
 * @return 1 se ocupado, 0 se livre.
 */
int hal_dma_is_busy(void);

/**
 * @brief Realiza uma cópia de memória usando o DMA.
 * * @param src Endereço de origem (físico).
 * @param dst Endereço de destino (físico).
 * @param size_words Número de palavras de 32 bits.
 * @param fixed_dst Se 1, não incrementa o endereço de destino (ex: escrita em FIFO).
 */
void hal_dma_memcpy(uint32_t src, uint32_t dst, uint32_t size_words, int fixed_dst);

#endif // HAL_DMA_H