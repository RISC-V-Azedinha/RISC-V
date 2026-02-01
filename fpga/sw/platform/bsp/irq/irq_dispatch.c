#include "../hal/hal_irq.h"
#include "../hal/hal_plic.h"
#include <stddef.h>

// Tabela de Vetores de Interrupção (RAM)
static irq_handler_t g_isr_table[PLIC_MAX_SOURCES] = { NULL };

// ----------------------------------------------------------------------------
// CENTRAL TRAP HANDLER 
// ----------------------------------------------------------------------------
// Esta função é chamada automaticamente pelo Hardware quando ocorre IRQ

void __attribute__((interrupt("machine"))) irq_dispatch_handler(void) {
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    // Verifica se é Interrupção Externa de Máquina (PLIC) -> Código 11 (0xB)
    // O bit mais significativo é 1 (interrupt), então MCAUSE = 0x8000000B
    if (mcause == 0x8000000B) { 
        
        // 1. CLAIM: Pergunta ao PLIC quem chamou
        uint32_t source = hal_plic_claim();

        // 2. DISPATCH: Chama a função registrada para esse ID
        if (source > 0 && source < PLIC_MAX_SOURCES) {
            if (g_isr_table[source] != NULL) {
                g_isr_table[source](); // Executa o Callback da Aplicação
            }
        }

        // 3. COMPLETE: Avisa o PLIC que terminamos
        hal_plic_complete(source);
    }
    // Aqui poderíamos tratar Timer (0x80000007) ou Software (0x80000003) no futuro
}

// ----------------------------------------------------------------------------
// IMPLEMENTAÇÃO DA API 
// ----------------------------------------------------------------------------

void hal_irq_init(void) {

    // 1. Inicializa o controlador PLIC (zera prioridades e enables)
    hal_plic_init();

    // 2. Aponta o mtvec da CPU para o nosso Dispatcher Central
    hal_irq_set_handler(irq_dispatch_handler);

    // 3. Habilita Interrupções Externas (Bit 11 do mie)
    // Isso permite que sinais vindos do PLIC cheguem ao núcleo
    hal_irq_mask_enable(IRQ_M_EXT);

}

void hal_irq_register(uint32_t source_id, irq_handler_t handler) {

    if (source_id < PLIC_MAX_SOURCES) {
        g_isr_table[source_id] = handler;
    }
    
}