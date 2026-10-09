/**
 * @file bootloader.c
 * @brief Bootloader bare-metal via UART, com cópia persistente no cartão microSD.
 *
 * Fluxo, como num microcontrolador:
 *
 *   1. Espera ~1 s pela magic word "CAFEBABE" na UART.
 *      Recebeu: recebe o tamanho e o binário direto na RAM. Se o bit 31 do tamanho estiver ligado
 *      (upload.py --save), grava também o programa no cartão. Depois executa.
 *   2. Não recebeu: procura um programa válido no cartão (mágica + tamanho + checksum) e, se achar,
 *      copia para a RAM e executa.
 *   3. Sem cartão ou sem programa válido: continua esperando pela UART, como antes.
 *
 * Um upload de tamanho 0 com o bit 31 ligado (upload.py --erase-sd) apaga o cabeçalho do cartão: a placa
 * volta a esperar pela UART no boot.
 *
 * Formato no cartão (blocos de 512 bytes, sem sistema de arquivos):
 *   bloco 1      cabeçalho { SD_MAGIC, tamanho, checksum, ~SD_MAGIC }
 *   bloco 2...   o programa
 * Fica no espaço livre entre o MBR e a primeira partição, então o cartão continua funcionando no
 * computador. Antes de gravar, o bootloader confere a tabela de partições e recusa se não couber.
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

#define MTIME_LO        (*(volatile uint32_t *)0x50000010) /**< Contador do CLINT (1 tick por ciclo). */
#define TICKS_MS        100000u                            /**< Ticks por milissegundo a 100 MHz. */

#define SD_BASE         0x70000000 /**< Mestre SPI do slot de microSD. */
#define SD_DATA         (*(volatile uint32_t *)(SD_BASE + 0x0))
#define SD_CTRL         (*(volatile uint32_t *)(SD_BASE + 0x4))
#define SD_DIV          (*(volatile uint32_t *)(SD_BASE + 0x8))
#define SD_STATUS       (*(volatile uint32_t *)(SD_BASE + 0xC))
#define SD_CS           (1 << 0)
#define SD_PWR          (1 << 1)
#define SD_BUSY         (1 << 0)

#define SD_DIV_INIT     124        /**< 400 kHz na inicialização. */
#define SD_DIV_FAST     3          /**< 12,5 MHz depois dela. */

#define SD_MAGIC        0x44535652 /**< "RVSD" em little endian. */
#define SD_HDR_BLOCK    1          /**< Bloco do cabeçalho; o programa vem logo depois. */

#define SAVE_FLAG       0x80000000 /**< Bit 31 do tamanho: gravar o programa no cartão. */
#define BOOT_WAIT_MS    1000       /**< Espera pela UART antes de tentar o cartão. */

/**
 * @brief Endereço base da aplicação do usuário na memória.
 * @note O Bootloader fica em 0x0000. O App começa com 2KB de offset (0x80000800).
 */
#define USER_APP_BASE   0x80000800
#define USER_APP_MAX    (256 * 1024 - 0x800)

static uint32_t sd_block[128];     /**< Bloco de trabalho (cabeçalho e MBR), alinhado em palavras. */
#define sd_buf ((uint8_t *)sd_block)
static uint32_t sd_hc;             /**< 1 = cartão SDHC/SDXC (endereço em blocos). */

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

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
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

/**
 * @brief Procura a magic word "CAFEBABE" na UART.
 * @param timeout_ms Tempo máximo de espera; 0 = espera para sempre.
 * @return 1 se recebeu a magic word, 0 se o tempo acabou.
 */
static int wait_magic(uint32_t timeout_ms) {
    static const uint8_t magic[4] = {0xCA, 0xFE, 0xBA, 0xBE};
    uint32_t start = MTIME_LO, matched = 0;

    while (matched < 4) {
        if (timeout_ms && (MTIME_LO - start) >= timeout_ms * TICKS_MS) return 0;
        if ((UART_CTRL_REG & STATUS_RX_AVAIL) == 0) continue;

        uint8_t c = uart_get_byte();
        if (c == magic[matched])  matched++;
        else                      matched = (c == magic[0]);   // Recomeça (aproveitando um novo 0xCA)
    }
    return 1;
}

/**
 * @brief Checksum do programa: soma com rotação, palavra a palavra (o tamanho é arredondado para 4).
 */
static uint32_t checksum(const uint32_t *p, uint32_t size) {
    uint32_t sum = 0;
    for (uint32_t i = 0; i < (size + 3) / 4; i++) sum = ((sum << 1) | (sum >> 31)) + p[i];
    return sum;
}

static uint32_t get_le32(const uint8_t *p) {
    return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
}

// ============================================================================
// CARTÃO MICROSD (MODO SPI)
// ============================================================================

static uint8_t spi(uint8_t b) {
    SD_DATA = b;
    while (SD_STATUS & SD_BUSY);
    return (uint8_t)SD_DATA;
}

static void sd_deselect(void) {
    SD_CTRL = SD_PWR;
    spi(0xFF);                                     // O cartão só solta o MISO depois de mais um byte
}

/**
 * @brief Envia um comando (com o cartão selecionado) e devolve a resposta R1 (0xFF = sem resposta).
 *
 * O CRC7 vai certo em todos os comandos: pela especificação, no modo SPI só o CMD0 e o CMD8 conferem o CRC,
 * mas há cartões que conferem todos (e respondem 0x08, erro de CRC, ao ACMD41 sem ele).
 */
static uint8_t sd_cmd(uint8_t cmd, uint32_t arg) {
    uint8_t frame[6] = {0x40 | cmd, arg >> 24, arg >> 16, arg >> 8, arg, 0};
    uint8_t crc = 0;
    for (int i = 0; i < 5; i++) {
        uint8_t b = frame[i];
        for (int j = 0; j < 8; j++, b <<= 1) {
            crc <<= 1;
            if ((b ^ crc) & 0x80) crc ^= 0x09;    // Polinômio x^7 + x^3 + 1
        }
    }
    frame[5] = (crc << 1) | 1;                     // CRC7 + bit de fim

    SD_CTRL = SD_PWR | SD_CS;
    spi(0xFF);
    for (int i = 0; i < 6; i++) spi(frame[i]);

    uint8_t r = 0xFF;
    for (int i = 0; i < 10 && (r & 0x80); i++) r = spi(0xFF);
    return r;
}

/**
 * @brief Espera um byte diferente de 'idle' no MISO.
 * @return O byte recebido, ou 'idle' se o tempo acabou.
 */
static uint8_t sd_wait(uint8_t idle, uint32_t timeout_ms) {
    uint32_t start = MTIME_LO;
    uint8_t r;
    while ((r = spi(0xFF)) == idle && (MTIME_LO - start) < timeout_ms * TICKS_MS);
    return r;
}

/**
 * @brief Liga e inicializa o cartão (SD v1, SDHC ou SDXC).
 * @return 1 se o cartão respondeu, 0 se não há cartão ou ele não aceitou a inicialização.
 */
static int sd_init(void) {
    SD_CTRL = 0;                                   // Desliga o cartão e espera ele descarregar
    SD_DIV  = SD_DIV_INIT;
    uint32_t start = MTIME_LO;
    while ((MTIME_LO - start) < 20 * TICKS_MS);
    SD_CTRL = SD_PWR;                              // Liga, espera estabilizar e manda 80 clocks sem CS
    start = MTIME_LO;
    while ((MTIME_LO - start) < 20 * TICKS_MS);
    for (int i = 0; i < 10; i++) spi(0xFF);

    uint8_t r = 0xFF;
    for (int i = 0; i < 10 && r != 0x01; i++) r = sd_cmd(0, 0);     // CMD0: modo SPI
    if (r != 0x01) { sd_deselect(); return 0; }

    uint32_t v2 = 0;
    if ((sd_cmd(8, 0x1AA) & 0xFE) == 0) {          // CMD8: só os cartões SD v2 aceitam (sem "comando ilegal")
        uint8_t ocr[4];
        for (int i = 0; i < 4; i++) ocr[i] = spi(0xFF);
        if (ocr[2] != 0x01 || ocr[3] != 0xAA) { sd_deselect(); return 0; }
        v2 = 1;
    }

    start = MTIME_LO;                              // ACMD41: espera o cartão sair do estado ocioso
    do {
        sd_cmd(55, 0);
        r = sd_cmd(41, v2 ? 0x40000000 : 0);
    } while (r == 0x01 && (MTIME_LO - start) < 1000 * TICKS_MS);
    if (r != 0x00) { sd_deselect(); return 0; }

    sd_hc = 0;
    if (v2 && sd_cmd(58, 0) == 0x00) {       // CMD58: o bit CCS diz se o endereço é em blocos
        sd_hc = (spi(0xFF) & 0x40) != 0;
        spi(0xFF); spi(0xFF); spi(0xFF);
    }
    if (!sd_hc) sd_cmd(16, 512);             // CMD16: blocos de 512 bytes nos cartões antigos

    sd_deselect();
    SD_DIV = SD_DIV_FAST;
    return 1;
}

static int sd_read(uint32_t block, uint8_t *dst) {
    int ok = 0;
    if (sd_cmd(17, sd_hc ? block : block * 512) == 0x00 && sd_wait(0xFF, 200) == 0xFE) {
        for (int i = 0; i < 512; i++) dst[i] = spi(0xFF);
        spi(0xFF); spi(0xFF);                      // CRC (não conferido)
        ok = 1;
    }
    sd_deselect();
    return ok;
}

static int sd_write(uint32_t block, const uint8_t *src) {
    int ok = 0;
    if (sd_cmd(24, sd_hc ? block : block * 512) == 0x00) {
        uint16_t crc = 0;                          // CRC16-CCITT do bloco (há cartões que conferem)
        spi(0xFF);
        spi(0xFE);                                 // Token de início do bloco
        for (int i = 0; i < 512; i++) {
            spi(src[i]);
            crc  = (crc >> 8) | (crc << 8);
            crc ^= src[i];
            crc ^= (crc & 0xFF) >> 4;
            crc ^= crc << 12;
            crc ^= (crc & 0xFF) << 5;
        }
        spi(crc >> 8); spi(crc);
        ok = (spi(0xFF) & 0x1F) == 0x05            // Bloco aceito
             && sd_wait(0x00, 500) != 0x00;        // Fim da gravação (o cartão segura o MISO em 0)
    }
    sd_deselect();
    return ok;
}

/**
 * @brief Grava o programa que está na RAM no cartão (size = 0: só apaga o cabeçalho).
 */
static void sd_save(uint32_t size) {
    uint32_t sum = checksum((const uint32_t *)USER_APP_BASE, size);
    uint32_t blocks = (size + 511) / 512;

    uart_puts("SD: ");
    if (!sd_init() || !sd_read(0, sd_buf)) { uart_puts("sem cartao\r\n"); return; }

    // Espaço livre antes da primeira partição (ou o cartão inteiro, se não houver tabela de partições)
    uint32_t limit = 0xFFFFFFFF;
    if (sd_buf[0] == 0xEB || sd_buf[0] == 0xE9) limit = 0;                     // FAT sem MBR: nada livre
    else if (sd_buf[510] == 0x55 && sd_buf[511] == 0xAA) {
        for (int i = 0; i < 4; i++) {
            const uint8_t *e = &sd_buf[0x1BE + 16 * i];
            uint32_t first = get_le32(e + 8);
            if (e[4] != 0 && first < limit) limit = first;
        }
    }
    if (SD_HDR_BLOCK + 1 + blocks > limit) { uart_puts("sem espaco antes da particao\r\n"); return; }

    // Mesmo programa já gravado: não reescreve
    if (size && sd_read(SD_HDR_BLOCK, sd_buf)) {
        const uint32_t *h = sd_block;
        if (h[0] == SD_MAGIC && h[1] == size && h[2] == sum && h[3] == ~SD_MAGIC) {
            uart_puts("ja gravado\r\n");
            return;
        }
    }

    // Invalida o cabeçalho, grava o programa e só então o cabeçalho novo (um corte no meio não deixa lixo)
    for (int i = 0; i < 512; i++) sd_buf[i] = 0;
    if (!sd_write(SD_HDR_BLOCK, sd_buf)) { uart_puts("erro\r\n"); return; }
    if (size == 0) { uart_puts("apagado\r\n"); return; }
    for (uint32_t b = 0; b < blocks; b++) {
        if (!sd_write(SD_HDR_BLOCK + 1 + b, (const uint8_t *)USER_APP_BASE + 512 * b)) {
            uart_puts("erro\r\n");
            return;
        }
        if ((b & 1) == 0) uart_putc('.');
    }
    uint32_t *h = sd_block;
    h[0] = SD_MAGIC; h[1] = size; h[2] = sum; h[3] = ~SD_MAGIC;
    uart_puts(sd_write(SD_HDR_BLOCK, sd_buf) ? "gravado\r\n" : "erro\r\n");
}

/**
 * @brief Copia o programa do cartão para a RAM.
 * @return 1 se havia um programa válido e ele foi carregado.
 */
static int sd_load(void) {
    uart_puts("SD: ");
    if (!sd_init() || !sd_read(SD_HDR_BLOCK, sd_buf)) { uart_puts("sem cartao\r\n"); return 0; }

    const uint32_t *h = sd_block;
    uint32_t size = h[1], sum = h[2];
    if (h[0] != SD_MAGIC || h[3] != ~SD_MAGIC || size == 0 || size > USER_APP_MAX) {
        uart_puts("sem programa\r\n");
        return 0;
    }

    for (uint32_t b = 0; b < (size + 511) / 512; b++) {
        if (!sd_read(SD_HDR_BLOCK + 1 + b, (uint8_t *)USER_APP_BASE + 512 * b)) { uart_puts("erro\r\n"); return 0; }
    }
    if (checksum((const uint32_t *)USER_APP_BASE, size) != sum) { uart_puts("checksum invalido\r\n"); return 0; }

    uart_puts("carregado\r\n");
    return 1;
}

// ============================================================================
// BOOTLOADER PRINCIPAL
// ============================================================================

/**
 * @brief Ponto de entrada do bootloader.
 */
void main() {
    // Feedback visual que estamos no bootloader
    uart_puts("\r\n[BOOT] ");

    /*
     * ESPERA PELA MAGIC WORD "CAFEBABE"
     * Por ~1 s; sem resposta, tenta o programa gravado no cartão. Sem cartão (ou sem programa),
     * espera pela UART para sempre, como antes.
     */
    int uart = wait_magic(BOOT_WAIT_MS);
    if (uart || !sd_load()) {
        uint32_t program_size;
        do {
            if (!uart) wait_magic(0);
            uart = 0;

            // Envia ACK para notificar a ferramenta host (script Python)
            uart_putc('!'); 

            // RECEBE O TAMANHO DO PROGRAMA (4 bytes; o bit 31 pede a gravação no cartão)
            uint32_t word = uart_get_uint32();
            program_size = word & ~SAVE_FLAG;

            // CARREGA O BINÁRIO DO USUÁRIO NA RAM
            volatile uint8_t *ram_ptr = (volatile uint8_t *)USER_APP_BASE;
            for (uint32_t i = 0; i < program_size; i++) {
                *ram_ptr = uart_get_byte();
                ram_ptr++;

                // Imprime um '.' a cada 1KB processado como feedback de progresso
                if ((i & 0x3FF) == 0) uart_putc('.');
            }

            if (word & SAVE_FLAG) {
                uart_puts("\r\n");
                sd_save(program_size);
            }

            uart_putc('>'); // Indica fim da transferência
            uart_putc('\r'); uart_putc('\n');
        } while (program_size == 0);              // Só apagou o cartão: volta a esperar um programa
    }

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
