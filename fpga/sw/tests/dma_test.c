#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_dma.h"
#include "hal/hal_uart.h"
#include "hal/hal_plic.h"
#include "hal/hal_irq.h"

// Configuração do Teste
#define BUFFER_SIZE   1024         // 1024 palavras (4KB)
#define RAM_SRC       0x80010000   // Área segura na RAM
#define RAM_DST       0x80012000   // src + 8KB (longe o suficiente)

// Flag de Sincronização
volatile bool g_dma_done = false;

// =========================================================
// HANDLER DA INTERRUPÇÃO 
// =========================================================

void my_dma_handler(void) {

    // Apenas sinaliza a flag
    //  O trabalho pesado de verificação fica na main
    g_dma_done = true;

}

// =========================================================
// FUNÇÕES AUXILIARES
// =========================================================

// Disparo Assíncrono (não bloqueante)
void dma_start_async(uint32_t src, uint32_t dst, uint32_t count) {

    dma_reg_t* dma = (dma_reg_t*)DMA_BASE_ADDR;
    
    // Garante que o DMA está livre antes de configurar
    while(dma->CTRL & DMA_CTRL_BUSY);

    // Configura e Dispara
    dma->SRC = src;
    dma->DST = dst;
    dma->CNT = count;
    dma->CTRL = DMA_CTRL_START; 

}

// =========================================================
// MAIN
// =========================================================

int main() {

    // 1. Inicializa Sistema Básico
    hal_uart_init(); 
    hal_uart_puts("\n\r=== DMA IRQ TEST ===============\n\r");

    // 2. Prepara o Cenário na RAM
    volatile uint32_t* src = (volatile uint32_t*)RAM_SRC;
    volatile uint32_t* dst = (volatile uint32_t*)RAM_DST;

    hal_uart_puts(" -> Preparando 4KB de dados...\n\r");
    for(int i=0; i<BUFFER_SIZE; i++) {
        src[i] = 0xCAFE0000 + i;        // Padrão conhecido
        dst[i] = 0x00000000;            // Limpa destino
    }

    // 3. Configura Interrupções
    hal_irq_init();                     
    hal_irq_register(PLIC_SOURCE_DMA, my_dma_handler);
    hal_plic_set_priority(PLIC_SOURCE_DMA, 1);
    hal_plic_enable(PLIC_SOURCE_DMA);

    // Liga a chave geral
    hal_irq_global_enable();

    // 4. Executa a Operação
    hal_uart_puts(" -> Disparando DMA...\n\r");
    dma_start_async((uint32_t)src, (uint32_t)dst, BUFFER_SIZE);
    
    hal_uart_puts(" -> DMA em progresso. Aguardando IRQ...\n\r");

    // 5. Espera Passiva (Wait for Event)
    // Aqui a CPU fica presa até o hardware avisar que acabou.
    while(!g_dma_done) {
        // Em um sistema real, poderíamos usar 'asm("wfi")' para economizar energia
        // Ou realizar processamento paralelo
    }

    hal_uart_puts(" -> [IRQ] Evento Recebido! DMA reportou fim.\n\r");

    // 6. Verificação de Integridade 
    hal_uart_puts(" -> Verificando integridade dos dados...\n\r");
    
    int erros = 0;
    for(int i=0; i<BUFFER_SIZE; i++) {
        if (dst[i] != (0xCAFE0000 + i)) {
            erros++;
            // Para não spamar o terminal, avisa só o primeiro erro
            if (erros == 1) {
                hal_uart_puts("    [ERRO] Divergencia no indice 0.\n\r");
            }
        }
    }

    if (erros == 0) hal_uart_puts(" -> SUCESSO TOTAL: Todos os 1024 words foram copiados.\n\r");
    else hal_uart_puts(" -> FALHA CRITICA: Dados corrompidos.\n\r");

    return 0;

}