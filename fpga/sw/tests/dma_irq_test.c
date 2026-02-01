#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_plic.h"
#include "hal/hal_dma.h"
#include "memory_map.h"

// CSR Definitions
#define CSR_MIE_MEIE    (1 << 11) 
#define CSR_MSTATUS_MIE (1 << 3)  
#define MCAUSE_MEI      0x8000000B 

// Configuração de Memória (Safe Zone)
#define RAM_SAFE_ZONE   0x80010000
#define BUFFER_SIZE     64 // Palavras

volatile bool g_dma_irq_fired = false;

// --- Trap Handler ---
void __attribute__((interrupt("machine"))) trap_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    if (mcause == MCAUSE_MEI) {
        // 1. Pergunta ao PLIC quem chamou
        uint32_t source = hal_plic_claim();

        if (source == PLIC_SOURCE_DMA) {
            // Chegou a interrupção do DMA!
            g_dma_irq_fired = true;
        }

        // 2. Avisa que terminamos
        hal_plic_complete(source);
    }
}

// --- Função Auxiliar: Disparo Assíncrono do DMA ---
void dma_start_async(uint32_t src, uint32_t dst, uint32_t count) {
    // Acessa registradores diretamente para não travar no while() da HAL
    dma_reg_t* dma = (dma_reg_t*)DMA_BASE_ADDR;
    
    // Aguarda estar livre (caso anterior)
    while(dma->CTRL & DMA_CTRL_BUSY);

    dma->SRC = src;
    dma->DST = dst;
    dma->CNT = count;
    
    // Dispara (Start bit)
    dma->CTRL = DMA_CTRL_START; 
}

// --- Main ---
int main() {
    hal_uart_init();
    hal_uart_puts("\n\r=== DMA INTERRUPT TEST ===\n\r");

    // 1. Prepara Dados
    volatile uint32_t* src = (volatile uint32_t*)RAM_SAFE_ZONE;
    volatile uint32_t* dst = (volatile uint32_t*)(RAM_SAFE_ZONE + 0x400);

    for (int i=0; i<BUFFER_SIZE; i++) {
        src[i] = 0xA000 + i;
        dst[i] = 0;
    }

    // 2. Configura Interrupções
    hal_plic_init();
    
    // Configura DMA no PLIC (Source 2)
    hal_plic_set_priority(PLIC_SOURCE_DMA, 1);
    hal_plic_enable(PLIC_SOURCE_DMA);

    // Habilita CPU
    asm volatile ("csrw mtvec, %0" :: "r"(&trap_handler));
    asm volatile ("csrs mie, %0" :: "r"(CSR_MIE_MEIE));
    asm volatile ("csrs mstatus, %0" :: "r"(CSR_MSTATUS_MIE));

    hal_uart_puts(" -> IRQ Configurada. Disparando DMA...\n\r");

    // 3. Dispara DMA (Sem Bloquear)
    dma_start_async((uint32_t)src, (uint32_t)dst, BUFFER_SIZE);

    hal_uart_puts(" -> DMA disparado. CPU livre! Fazendo outra coisa...\n\r");

    // 4. Loop de Espera (Simula trabalho útil enquanto DMA copia)
    uint32_t work_counter = 0;
    while (!g_dma_irq_fired) {
        work_counter++;
        // Aqui a CPU poderia estar processando algo...
    }

    hal_uart_puts(" -> [IRQ] Interrupcao DMA Recebida!\n\r");
    hal_uart_puts(" -> Ciclos de 'trabalho' da CPU durante a copia: ");
    
    // Print simples do contador
    char buf[16];
    char *p = &buf[15];
    *p = '\0';
    if(work_counter == 0) *(--p) = '0';
    else while(work_counter > 0) { *(--p) = (work_counter % 10) + '0'; work_counter /= 10; }
    hal_uart_puts(p);
    hal_uart_puts("\n\r");

    // 5. Verifica Dados
    int errors = 0;
    for(int i=0; i<BUFFER_SIZE; i++) {
        if(dst[i] != src[i]) errors++;
    }

    if(errors == 0) hal_uart_puts(" -> SUCESSO: Dados Verificados.\n\r");
    else hal_uart_puts(" -> FALHA: Erro na verificacao de dados.\n\r");

    return 0;
}