#include <stdint.h>
#include "hal/hal_uart.h"

// ============================================================================
// PROGRAMA PRINCIPAL
// ============================================================================

void main() {
    
    // 1. Inicialização do Hardware
    hal_uart_init();

    // 2. Teste de Boas-vindas
    hal_uart_puts("\r\n\r\n");
    hal_uart_puts("==========================================\r\n");
    hal_uart_puts("      SISTEMA INICIADO COM SUCESSO        \r\n");
    hal_uart_puts("==========================================\r\n");
    hal_uart_puts("Driver: hal_uart (com FIFO e Handshake)\r\n");
    hal_uart_puts("Digite algo para testar o Echo:\r\n");

    // 3. Loop Infinito (Echo)
    char received_char;

    while (1) {
        
        // Bloqueia e espera até o usuário digitar algo.
        // O HAL cuida de verificar o bit RX_VALID e fazer o POP na FIFO.
        received_char = hal_uart_getc();

        // Feedback visual
        hal_uart_puts("Recebido: [");
        hal_uart_putc(received_char);
        hal_uart_puts("]\r\n");

        // Opcional: testar o kbhit (non-blocking):
        /*
        if (hal_uart_kbhit()) {
            // faz algo sem travar
        }
        */

    }
    
}