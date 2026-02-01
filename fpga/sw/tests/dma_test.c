#include <stdint.h>
#include "../platform/bsp/hal/hal_uart.h"
#include "../platform/bsp/hal/hal_dma.h"

// =========================================================
// UTILITÁRIOS DE IMPRESSÃO
// =========================================================
void print_hex(uint32_t n) {
    hal_uart_puts("0x");
    char hex_chars[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) {
        hal_uart_putc(hex_chars[(n >> i) & 0xF]);
    }
}

void print_dec(uint32_t n) {
    if (n == 0) { hal_uart_putc('0'); return; }
    char buffer[12];
    int i = 0;
    while (n > 0) {
        buffer[i++] = (n % 10) + '0';
        n /= 10;
    }
    while (i > 0) hal_uart_putc(buffer[--i]);
}

// =========================================================
// CONFIGURAÇÃO DO TESTE
// =========================================================
// Usamos uma região segura no meio da RAM (128KB Total)
// RAM Base: 0x80000000
// Safe Zone: 0x80010000 (Offset 64KB)
#define RAM_SAFE_ZONE  0x80010000
#define BUFFER_SIZE    128 // Palavras (512 Bytes)

// =========================================================
// MAIN
// =========================================================
void main() {
    hal_uart_init();
    
    hal_uart_puts("\n\r");
    hal_uart_puts("==============================\n\r");
    hal_uart_puts("   SOC DMA TEST (FPGA)        \n\r");
    hal_uart_puts("==============================\n\r");

    // Definição manual dos ponteiros para garantir que não colidam com Stack/Text
    volatile uint32_t* src_ptr = (volatile uint32_t*)(RAM_SAFE_ZONE);
    volatile uint32_t* dst_ptr = (volatile uint32_t*)(RAM_SAFE_ZONE + 0x1000); // +4KB

    // 1. Preenchimento (CPU)
    hal_uart_puts("[CPU] Preenchendo Source...\n\r");
    for (uint32_t i = 0; i < BUFFER_SIZE; i++) {
        src_ptr[i] = 0xCAFEBABE + i; // Padrão reconhecível
        dst_ptr[i] = 0x00000000;     // Limpa destino
    }

    // 2. Transferência (DMA)
    hal_uart_puts("[DMA] Iniciando transferencia...\n\r");
    hal_uart_puts("      SRC: "); print_hex((uint32_t)src_ptr); hal_uart_puts("\n\r");
    hal_uart_puts("      DST: "); print_hex((uint32_t)dst_ptr); hal_uart_puts("\n\r");
    hal_uart_puts("      CNT: "); print_dec(BUFFER_SIZE); hal_uart_puts("\n\r");

    // Chama a HAL (Destino Incremental = 0 no fixed_dst)
    hal_dma_memcpy((uint32_t)src_ptr, (uint32_t)dst_ptr, BUFFER_SIZE, 0);

    hal_uart_puts("[DMA] Transferencia concluida.\n\r");

    // 3. Verificação (CPU)
    hal_uart_puts("[CPU] Verificando dados...\n\r");
    
    int errors = 0;
    for (uint32_t i = 0; i < BUFFER_SIZE; i++) {
        if (dst_ptr[i] != src_ptr[i]) {
            errors++;
            if (errors <= 3) { // Mostra apenas os primeiros erros
                hal_uart_puts("      ERR ["); print_dec(i); hal_uart_puts("]: ");
                print_hex(dst_ptr[i]); hal_uart_puts(" != "); print_hex(src_ptr[i]);
                hal_uart_puts("\n\r");
            }
        }
    }

    if (errors == 0) {
        hal_uart_puts("\n\r>>> SUCESSO: MEMORIA COPIADA CORRETAMENTE! <<<\n\r");
    } else {
        hal_uart_puts("\n\r>>> FALHA: ERROS ENCONTRADOS: "); print_dec(errors); hal_uart_puts(" <<<\n\r");
    }

    while(1);
}