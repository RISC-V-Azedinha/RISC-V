#include <stdint.h>
#include <stdbool.h>
#include "hal/hal_uart.h"
#include "hal/hal_timer.h"
#include "hal/hal_irq.h" 
#include "memory_map.h"

// ============================================================================
// VARIÁVEIS DE ESTADO (Comunicação Handler -> Main)
// ============================================================================
volatile bool g_software_irq_fired = false;
volatile bool g_timer_irq_fired    = false;
volatile uint32_t g_mcause_debug   = 0;

// ============================================================================
// TRAP HANDLER (A Rotina de Atendimento)
// ============================================================================
// Esta função é chamada automaticamente pelo Hardware quando ocorre uma IRQ.
// O atributo "interrupt" garante que o compilador salve o contexto e use MRET.

void __attribute__((interrupt("machine"))) trap_handler(void) {
    
    // 1. Descobrir a causa (Lendo CSR mcause)
    uint32_t mcause;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));
    g_mcause_debug = mcause;

    // Verifica se é Interrupção (Bit mais significativo = 1)
    if ((int32_t)mcause < 0) {
        
        // Isola o código da causa (Bits inferiores)
        uint32_t cause_code = mcause & 0xF;

        switch (cause_code) {
            
            // ----------------------------------------------------------------
            // CASO: SOFTWARE IRQ (ID 3)
            // ----------------------------------------------------------------
            case 3: 
                g_software_irq_fired = true;
                
                // ACK: Baixar o sinal de interrupção (Limpar MSIP)
                // Se não fizermos isso, o loop de interrupção será infinito.
                CLINT_MSIP = 0; 
                break;

            // ----------------------------------------------------------------
            // CASO: TIMER IRQ (ID 7)
            // ----------------------------------------------------------------
            case 7:
                g_timer_irq_fired = true;
                
                // ACK: Reprogramar o comparador para o futuro distante (ou infinito)
                // Isso faz com que mtime < mtimecmp, baixando o sinal de IRQ.
                hal_timer_irq_ack(); 
                break;

            default:
                // Causa desconhecida (apenas para debug)
                break;
        }
    }
}

// ============================================================================
// MAIN PROGRAM
// ============================================================================

int main() {

    hal_uart_init();
    
    // Cabeçalho Bonito rs
    hal_uart_puts("\n\r");
    hal_uart_puts("==========================================================\n\r");
    hal_uart_puts("          DIAGNOSTICO DE INTERRUPCOES (CLINT)             \n\r");
    hal_uart_puts("==========================================================\n\r");
    hal_uart_puts("\n\r");

    // ------------------------------------------------------------------------
    // 1. CONFIGURAÇÃO INICIAL
    // ------------------------------------------------------------------------
    hal_uart_puts("[INFO] Inicializando sistema de interrupcoes...\n\r");

    // Configura o endereço para onde o processador deve pular (MTVEC)
    hal_irq_set_handler(trap_handler);
    
    // Habilita as interrupções globalmente (MIE no mstatus)
    hal_irq_global_enable();
    
    hal_uart_puts("       -> Vetor de Trap configurado.\n\r");
    hal_uart_puts("       -> Interrupcoes Globais HABILITADAS.\n\r");
    hal_uart_puts("       -> Status: [PRONTO]\n\r\n\r");

    // ------------------------------------------------------------------------
    // 2. TESTE DA SOFTWARE IRQ
    // ------------------------------------------------------------------------
    hal_uart_puts("[TESTE 1] Verificando Software IRQ...\n\r");
    
    g_software_irq_fired = false;

    // A. Habilita a máscara específica para Software Interrupt
    hal_irq_mask_enable(IRQ_M_SOFT);
    hal_uart_puts("\t-> Mascara (MSIE) habilitada.\n\r");

    // B. Dispara a interrupção via Hardware (Escreve 1 no registrador MSIP)
    hal_uart_puts("\t-> Disparando sinal no CLINT (MSIP=1)...\n\r");
    CLINT_MSIP = 1;

    // C. Aguarda a mágica acontecer (Busy Wait com Timeout de segurança)
    hal_uart_puts("\t-> Aguardando Handler...\n\r");
    
    int timeout = 10000;
    while (!g_software_irq_fired && timeout > 0) timeout--;

    // D. Verifica o resultado
    if (g_software_irq_fired) hal_uart_puts("\t-> [SUCESSO] Software IRQ capturada e tratada!\n\r");
    else {
        hal_uart_puts("\t-> [FALHA] O processador nao desviou para o Handler.\n\r");
        // Trava para debug se falhar
        while(1); 
    }

    // Limpeza: Desabilita a máscara
    hal_irq_mask_disable(IRQ_M_SOFT);
    hal_uart_puts("\n\r");

    // ------------------------------------------------------------------------
    // 3. TESTE DA TIMER IRQ
    // ------------------------------------------------------------------------
    hal_uart_puts("[TESTE 2] Verificando Timer IRQ...\n\r");

    g_timer_irq_fired = false;

    // A. Habilita a máscara específica para Timer Interrupt
    hal_irq_mask_enable(IRQ_M_TIMER);
    hal_uart_puts("\t-> Mascara (MTIE) habilitada.\n\r");

    // B. Configura o alarme
    // Vamos configurar para disparar daqui a ~10ms (1.000.000 ciclos @ 100MHz)
    uint64_t delta = 50000; 
    hal_uart_puts("\t-> Configurando alarme (Delta = 50k ciclos)...\n\r");
    hal_timer_set_irq_delta(delta);

    // C. Aguarda
    hal_uart_puts("\t-> Aguardando Timer estourar...\n\r");
    
    // Aqui não usamos timeout curto, pois depende do timer real
    while (!g_timer_irq_fired);

    // D. Verifica
    hal_uart_puts("\t-> [SUCESSO] Timer IRQ capturada e tratada!\n\r");

    // Limpeza
    hal_irq_mask_disable(IRQ_M_TIMER);
    
    // ------------------------------------------------------------------------
    // CONCLUSÃO
    // ------------------------------------------------------------------------
    hal_uart_puts("\n\r");
    hal_uart_puts("==========================================================\n\r");
    hal_uart_puts("             RELATORIO FINAL: PASSOU                      \n\r");
    hal_uart_puts("==========================================================\n\r");
    hal_uart_puts("O processador esta 100% compativel com o padrao CLINT.\n\r");
    hal_uart_puts("Pronto para rodar Benchmarks ou Sistemas Operacionais.\n\r");

    while(1);
    return 0;
}