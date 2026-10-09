#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

#include <stdint.h>

/* ============================================================================================================== */
/* MACROS DE ACESSO (VOLATILE)                                                                                    */
/* ============================================================================================================== */

#define MMIO32(addr)            (*(volatile uint32_t *)(addr))
#define MMIO8(addr)             (*(volatile uint8_t  *)(addr))

/* ============================================================================================================== */
/* MAPA DE ENDEREÇOS BASE                                                                                         */
/* ============================================================================================================== */

#define UART_BASE_ADDR      0x10000000
#define GPIO_BASE_ADDR      0x20000000
#define VGA_BASE_ADDR       0x30000000
#define CLINT_BASE_ADDR     0x50000000
#define PLIC_BASE_ADDR      0x60000000
#define NPU_BASE_ADDR       0x90000000

/* ============================================================================================================== */
/* UART DEFINITIONS                                                                                               */
/* ============================================================================================================== */

#define UART_REG_DATA_OFFSET    0x00
#define UART_REG_CTRL_OFFSET    0x04
#define UART_DATA_REG_ADDR      (UART_BASE_ADDR + UART_REG_DATA_OFFSET)
#define UART_CTRL_REG_ADDR      (UART_BASE_ADDR + UART_REG_CTRL_OFFSET)

#define UART_STATUS_TX_BUSY     (1 << 0)
#define UART_STATUS_RX_VALID    (1 << 1)
#define UART_CMD_RX_POP         (1 << 0)
#define UART_CMD_RX_FLUSH       (1 << 2)

/* ============================================================================================================== */
/* VGA DEFINITIONS (Preservado para compatibilidade com hal_vga.c)                                                */
/* ============================================================================================================== */

#define VGA_WIDTH               320
#define VGA_HEIGHT              240
#define VGA_VSYNC_OFFSET        0x1FFFF
#define VGA_VSYNC_ADDR          (VGA_BASE_ADDR + VGA_VSYNC_OFFSET)
#define VGA_VSYNC_BIT           (1 << 0)

/* ============================================================================================================== */
/* NEURAL PROCESSING UNIT (NPU) MMIO                                                                              */
/* ============================================================================================================== */

// Registradores de Controle e Status
#define NPU_REG_STATUS      MMIO32(NPU_BASE_ADDR + 0x00)        // RO: Status Flags
#define NPU_REG_CMD         MMIO32(NPU_BASE_ADDR + 0x04)        // WO: Comandos (Start, Clear)
#define NPU_REG_CONFIG      MMIO32(NPU_BASE_ADDR + 0x08)        // RW: Tamanho do Run (K_DIM)

// Portas de Dados (FIFOs) - Endereços Fixos para Burst
#define NPU_REG_WRITE_W     MMIO32(NPU_BASE_ADDR + 0x10)        // WO: Pesos
#define NPU_REG_WRITE_A     MMIO32(NPU_BASE_ADDR + 0x14)        // WO: Inputs (Ativações)
#define NPU_REG_READ_OUT    MMIO32(NPU_BASE_ADDR + 0x18)        // RO: Saída
#define NPU_REG_WRITE_IMG   MMIO32(NPU_BASE_ADDR + 0x1C)        // WO: Imagem crua do im2col (4 pixels int8)

// Bases das regiões na RAM local (Pesos residentes): os resets de ponteiro voltam para cá
#define NPU_REG_W_BASE      MMIO32(NPU_BASE_ADDR + 0x20)        // RW: Base da região de Pesos
#define NPU_REG_I_BASE      MMIO32(NPU_BASE_ADDR + 0x24)        // RW: Base da região de Inputs

// im2col em hardware: as janelas da convolução saem da imagem crua (porta IMG)
#define NPU_REG_IM2COL_EN   MMIO32(NPU_BASE_ADDR + 0x28)        // RW: 1 = Inputs gerados pelo im2col
#define NPU_REG_IM2COL_GEOM MMIO32(NPU_BASE_ADDR + 0x2C)        // RW: [7:0] IN_W | [15:8] OUT_W | [19:16] STRIDE | [23:20] KW
#define NPU_REG_IM2COL_NWIN MMIO32(NPU_BASE_ADDR + 0x30)        // RW: Total de janelas

// Sequenciador de tiles e formato da saída
#define NPU_REG_TILES       MMIO32(NPU_BASE_ADDR + 0x34)        // RW: [15:0] Tiles por START | bit16 RW_W | bit17 RW_I
#define NPU_REG_OUT_CFG     MMIO32(NPU_BASE_ADDR + 0x38)        // RW: bit0 ORDER (linhas em ordem) | bit1 UNPACK (1 ativação/palavra)
#define NPU_TILES_RW_W      (1 << 16)                           // A cada tile, a leitura dos Pesos volta a W_BASE
#define NPU_TILES_RW_I      (1 << 17)                           // A cada tile, a leitura dos Inputs volta a I_BASE
#define NPU_OUT_ORDER       (1 << 0)
#define NPU_OUT_UNPACK      (1 << 1)
#define NPU_TILES_BIAS      (1 << 18)                           // Tile t usa o vetor de bias t (0x80 + 16t)
#define NPU_TILES_BIAS_BASE(b) ((uint32_t)(b) << 19)             // Banco de bias do primeiro tile (biases residentes)

// Descritores de camada: programa executado pelo processador de comandos da NPU
#define NPU_REG_DESC        MMIO32(NPU_BASE_ADDR + 0x0C)        // WO: Porta do programa (Fixed Dest, via DMA)
#define NPU_STATUS_PROG_END (1 << 4)                            // Programa terminado (fila vazia, último comando = END)
#define NPU_DESC_WRITE(reg) (0x10000000u | (reg))               // Seguido do dado: escreve um registrador
#define NPU_DESC_WAIT       0x20000000u                         // Espera a execução corrente terminar
#define NPU_DESC_END        0x30000000u                         // Fim do programa
#define NPU_REG_MODE        MMIO32(NPU_BASE_ADDR + 0x3C)        // RW: bit0 GEMV (densa com lote 1 nas 4 linhas)
#define NPU_MODE_GEMV       (1 << 0)
#define NPU_MODE_STREAM_I   (1 << 1)                            // Leitura espera o Input chegar (DMA após o START)
#define NPU_MODE_STREAM_W   (1 << 2)                            // Leitura espera o Peso chegar
#define NPU_MODE_OVERLAP    (1 << 3)                            // Tiles encadeados (acumuladores sombra)
#define NPU_OUT_LOOP        (1 << 2)                            // Saída vai para a RAM de Inputs (fusão de camadas)

// Configuração Estática
#define NPU_REG_QUANT_CFG   MMIO32(NPU_BASE_ADDR + 0x40)        // RW: Shift & Zero Point
#define NPU_REG_QUANT_MULT  MMIO32(NPU_BASE_ADDR + 0x44)        // RW: Multiplicador PPU
#define NPU_REG_FLAGS       MMIO32(NPU_BASE_ADDR + 0x48)        // RW: Flags de Controle (ReLU)
#define NPU_REG_BIAS_BASE   MMIO32(NPU_BASE_ADDR + 0x80)        // RW: Banco de Bias (0x80 a 0xFC: 8 tiles x 4 colunas)

// --- BITMASKS ---------------------------------------------------------------------------------------------

// STATUS (0x00)
#define NPU_STATUS_BUSY     (1 << 0)
#define NPU_STATUS_DONE     (1 << 1)
#define NPU_STATUS_OUT_VLD  (1 << 3)

// CMD (0x04)
#define NPU_CMD_RST_PTRS    (1 << 0)                            // Reseta todos ponteiros
#define NPU_CMD_START       (1 << 1)                            // Dispara execução
#define NPU_CMD_ACC_CLEAR   (1 << 2)                            // Limpa acumuladores antes de rodar
#define NPU_CMD_ACC_NO_DRAIN (1 << 3)                           // 1=Mantém resultado no Array (Tiling), 0=Salva na FIFO
#define NPU_CMD_RST_W_RD    (1 << 4)                            // Reseta leitura de Pesos (Reuso)
#define NPU_CMD_RST_I_RD    (1 << 5)                            // Reseta leitura de Inputs (Reuso)
#define NPU_CMD_RST_WR_W    (1 << 6)                            // Reseta escrita de Pesos
#define NPU_CMD_RST_WR_I    (1 << 7)                            // Reseta escrita de Inputs
#define NPU_CMD_DBUF_EN     (1 << 8)                            // Double Buffering (Ping-Pong) neste START:
                                                                 // troca os bancos físicos de Pesos/Inputs.
                                                                 // Só tem efeito em bitstreams gerados com
                                                                 // DOUBLE_BUFFER => true no npu_top.

// FLAGS (0x48)
#define NPU_FLAG_RELU       (1 << 0)                            // 1 = Ativa ReLU na saída

/* ============================================================================================================== */
/* CLINT (Core Local Interruptor) MMIO                                                                            */
/* ============================================================================================================== */

// Offsets Padrão RISC-V (Adaptados para nosso bus de 32-bit)

#define CLINT_MSIP          MMIO32(CLINT_BASE_ADDR + 0x00)      // Machine Software Interrupt Pending
#define CLINT_MTIMECMP_LO   MMIO32(CLINT_BASE_ADDR + 0x08)      // Timer Compare Low
#define CLINT_MTIMECMP_HI   MMIO32(CLINT_BASE_ADDR + 0x0C)      // Timer Compare High
#define CLINT_MTIME_LO      MMIO32(CLINT_BASE_ADDR + 0x10)      // Timer Value Low
#define CLINT_MTIME_HI      MMIO32(CLINT_BASE_ADDR + 0x14)      // Timer Value High

/* ============================================================================================================== */
/* PLIC (Platform-Level Interrupt Controller) MMIO [NOVO]                                                         */
/* ============================================================================================================== */

// Offsets Padrão RISC-V (Mini-PLIC: Context 0 = Machine Mode Hart 0)
#define PLIC_PRIORITY_BASE  (PLIC_BASE_ADDR + 0x000000)
#define PLIC_PENDING_BASE   (PLIC_BASE_ADDR + 0x001000)
#define PLIC_ENABLE_BASE    (PLIC_BASE_ADDR + 0x002000)
#define PLIC_THRESHOLD      MMIO32(PLIC_BASE_ADDR + 0x200000)
#define PLIC_CLAIM          MMIO32(PLIC_BASE_ADDR + 0x200004)

// Macro para acessar prioridade de uma fonte específica (ID 1 a 31)
#define PLIC_PRIORITY(id)   MMIO32(PLIC_PRIORITY_BASE + ((id) * 4))

// Registradores Globais (Bitmaps)
#define PLIC_PENDING        MMIO32(PLIC_PENDING_BASE)   // Bitmask (Bits 0-31)
#define PLIC_ENABLE         MMIO32(PLIC_ENABLE_BASE)    // Bitmask (Bits 0-31)

// ----------------------------------------------------------------------------------------------------------

#endif /* MEMORY_MAP_H */