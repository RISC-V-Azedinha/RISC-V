#include "hal_dma.h"

int hal_dma_is_busy(void) {
    // O bit 0 indica status na leitura
    return (DMA->CTRL & DMA_CTRL_BUSY);
}

void hal_dma_memcpy(uint32_t src, uint32_t dst, uint32_t size_words, int fixed_dst) {
    // 1. Segurança: Aguarda o DMA estar livre
    while(hal_dma_is_busy());

    // 2. Configura os registradores
    DMA->SRC = src;
    DMA->DST = dst;
    DMA->CNT = size_words;

    // 3. Prepara comando
    uint32_t cmd = DMA_CTRL_START;
    if (fixed_dst) {
        cmd |= DMA_CTRL_FIXED_DST;
    }

    // 4. Dispara
    DMA->CTRL = cmd;

    // 5. Bloqueio (Polling) até terminar
    // Adicionamos NOPs para evitar starvation no barramento se a CPU 
    // tentar ler status agressivamente enquanto o DMA tenta ler memória.
    while(hal_dma_is_busy()) {
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
        __asm__ volatile ("nop");
    }
}