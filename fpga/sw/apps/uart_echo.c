#include <stdint.h>

// ============================================================================
// CONFIGURAÇÃO DE HARDWARE
// ============================================================================
// IMPORTANTE: Altere este endereço para onde você mapeou a UART no seu SoC/Interconnect
#define UART_BASE_ADDR  0x10000000

// Definição dos registradores (ponteiros voláteis para impedir otimização do compilador)
#define UART_DATA_REG   (*(volatile uint32_t *)(UART_BASE_ADDR + 0x00))
#define UART_CTRL_REG   (*(volatile uint32_t *)(UART_BASE_ADDR + 0x04))

// Máscaras de Bits (Conforme definido no VHDL)
#define STATUS_TX_BUSY  (1 << 0)  // Bit 0: Transmissor ocupado
#define STATUS_RX_VALID (1 << 1)  // Bit 1: Tem dado novo para ler
#define CMD_CLEAR_RX    (1 << 0)  // Bit 0 (Escrita): Limpar flag de RX

// ============================================================================
// DRIVERS DE BAIXO NÍVEL
// ============================================================================

/**
 * Envia um caractere pela UART (Blocking)
 */
void uart_putc(char c) {
    // 1. Polling: Espera o transmissor ficar livre (Bit 0 = 0)
    // Enquanto (Status E Mascara_Busy) for diferente de zero, espera.
    while ((UART_CTRL_REG & STATUS_TX_BUSY) != 0);

    // 2. Escreve o dado para transmissão
    UART_DATA_REG = c;
}

/**
 * Recebe um caractere da UART (Blocking)
 * AQUI ESTÁ A MUDANÇA CRÍTICA PARA O SEU HARDWARE NOVO
 */
char uart_getc() {
    // 1. Polling: Espera chegar um dado (Bit 1 = 1)
    // Enquanto (Status E Mascara_Valid) for igual a zero, espera.
    while ((UART_CTRL_REG & STATUS_RX_VALID) == 0);

    // 2. Lê o dado do buffer
    char c = (char)UART_DATA_REG;

    // 3. HANDSHAKE EXPLÍCITO:
    // Avisa o hardware que já lemos, para ele baixar a flag RX_VALID.
    // Escrevemos '1' no bit 0 do registrador de controle.
    UART_CTRL_REG = CMD_CLEAR_RX;

    return c;
}

/**
 * Envia uma string completa (terminada em null)
 */
void uart_puts(const char *str) {
    while (*str) {
        uart_putc(*str++);
    }
}

// ============================================================================
// PROGRAMA PRINCIPAL
// ============================================================================

// Se você não tiver um arquivo de startup (.s), o entry point pode ser aqui.
// Caso contrário, chame main() do seu crt0.s
void main() {
    
    // Teste 1: Hello World simples
    uart_puts("\r\n\r\n--- INICIANDO TESTE UART ---\r\n");
    uart_puts("Hardware: Manual Polling (Sem FIFO)\r\n");
    uart_puts("Digite qualquer tecla para ecoar:\r\n");

    // Teste 2: Loop de Echo (O teste de fogo para o problema de repetição)
    char received;
    while (1) {
        // Espera digitar
        received = uart_getc();

        // Processa (Ex: converte para maiúsculo visualmente se for letra minúscula)
        // Isso é só pra provar que o processador leu e processou
        
        // Devolve pro terminal (Echo)
        uart_puts("Voce digitou: ");
        uart_putc(received);
        uart_puts("\r\n");
    }
}