/**
 * @file bootloader.c
 * @brief Bootloader bare-metal via UART.
 * 
 * Aguarda a magic word "CAFEBABE" via serial, recebe o tamanho do binário,
 * carrega os dados diretamente na RAM e realiza o salto para a aplicação do usuário.
 */

#include <stdint.h>

// ============================================================================
// CONFIGURAÇÃO
// ============================================================================

#define UART_BASE       0x10000000 /**< Endereço base do periférico UART. */
#define UART_DATA_REG   (*(volatile uint32_t *)(UART_BASE + 0x00)) /**< Registrador de dados (RX/TX). */
#define UART_CTRL_REG   (*(volatile uint32_t *)(UART_BASE + 0x04)) /**< Registrador de controle/status. */

#define STATUS_RX_AVAIL (1 << 1) /**< Flag indicando que há dados na FIFO de recepção. */
#define CMD_POP_FIFO    (1 << 0) /**< Comando para avançar a FIFO de recepção. */

/** 
 * @brief Endereço base da aplicação do usuário na memória.
 * @note O Bootloader fica em 0x0000. O App começa com 2KB de offset (0x80000800).
 */
#define USER_APP_BASE   0x80000800

// ============================================================================
// AUXILIARES
// ============================================================================

/**
 * @brief Aguarda em polling e lê um byte da interface UART.
 * @return O byte lido do registrador de dados.
 */
uint8_t uart_get_byte() {
    while ((UART_CTRL_REG & STATUS_RX_AVAIL) == 0);
    uint8_t c = (uint8_t)UART_DATA_REG;
    UART_CTRL_REG = CMD_POP_FIFO;
    return c;
}

/**
 * @brief Envia um caractere pela interface UART em modo polling.
 * @param c O caractere a ser enviado.
 */
void uart_putc(char c) {
    while ((UART_CTRL_REG & 1) != 0); 
    UART_DATA_REG = c;
}

/**
 * @brief Recebe 4 bytes da UART e os converte em um inteiro de 32 bits.
 * 
 * Os dados são processados em formato Little Endian (compatível com 
 * o struct.pack do Python).
 * 
 * @return O valor de 32 bits montado a partir dos bytes recebidos.
 */
uint32_t uart_get_uint32() {
    uint32_t val = 0;
    // Recebe 4 bytes (Little Endian do Python struct.pack)
    val |= ((uint32_t)uart_get_byte()) << 0;
    val |= ((uint32_t)uart_get_byte()) << 8;
    val |= ((uint32_t)uart_get_byte()) << 16;
    val |= ((uint32_t)uart_get_byte()) << 24;
    return val;
}

// ============================================================================
// BOOTLOADER PRINCIPAL
// ============================================================================

/**
 * @brief Ponto de entrada do bootloader.
 */
void main() {
    // Feedback visual que estamos no bootloader
    uart_putc('\r'); uart_putc('\n');
    uart_putc('['); uart_putc('B'); uart_putc('O'); uart_putc('O'); uart_putc('T'); uart_putc(']');
    uart_putc(' ');

    /*
     * ESPERA PELA MAGIC WORD "CAFEBABE"
     * Implementa uma máquina de estados simples que aguarda a sequência 
     * exata de bytes para evitar falsos positivos na linha serial.
     */
    while (1) {
        if (uart_get_byte() == 0xCA) {
            if (uart_get_byte() == 0xFE) {
                if (uart_get_byte() == 0xBA) {
                    if (uart_get_byte() == 0xBE) {
                        break; // Recebeu a magic word com sucesso
                    }
                }
            }
        }
        // Retorna ao início do loop aguardando um novo 0xCA
    }

    // Envia ACK para notificar a ferramenta host (script Python)
    uart_putc('!'); 

    // RECEBE O TAMANHO DO PROGRAMA (4 bytes)
    uint32_t program_size = uart_get_uint32();

    // CARREGA O BINÁRIO DO USUÁRIO NA RAM
    volatile uint8_t *ram_ptr = (volatile uint8_t *)USER_APP_BASE;
    for (uint32_t i = 0; i < program_size; i++) {
        *ram_ptr = uart_get_byte();
        ram_ptr++;
        
        // Imprime um '.' a cada 1KB processado como feedback de progresso
        if ((i & 0x3FF) == 0) uart_putc('.');
    }

    uart_putc('>'); // Indica fim da transferência
    uart_putc('\r'); uart_putc('\n');

    // JUMP PARA O APP DO USUÁRIO
    // Converte o endereço base em um ponteiro de função e o executa
    void (*user_app)() = (void (*)())USER_APP_BASE;
    user_app();

    /*
     * NOTA: Se a aplicação do usuário retornar, isso pode indicar um erro ou
     * que o programa não foi corretamente carregado. Para evitar comportamentos
     * imprevisíveis, o bootloader entra em um loop infinito, "capturando" a CPU.
    */
    while(1); 

}