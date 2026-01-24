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

// Base Address (Definido no Bus Interconnect)
#define NPU_BASE_ADDR       0x90000000

// Registradores de Controle e Status
#define NPU_REG_STATUS      MMIO32(NPU_BASE_ADDR + 0x00)        // RO: Status Flags
#define NPU_REG_CMD         MMIO32(NPU_BASE_ADDR + 0x04)        // WO: Comandos (Start, Clear)
#define NPU_REG_CONFIG      MMIO32(NPU_BASE_ADDR + 0x08)        // RW: Tamanho do Run (K_DIM)

// Portas de Dados (FIFOs) - Endereços Fixos para Burst
#define NPU_REG_WRITE_W     MMIO32(NPU_BASE_ADDR + 0x10)        // WO: Pesos
#define NPU_REG_WRITE_A     MMIO32(NPU_BASE_ADDR + 0x14)        // WO: Inputs (Ativações)
#define NPU_REG_READ_OUT    MMIO32(NPU_BASE_ADDR + 0x18)        // RO: Saída

// Configuração Estática
#define NPU_REG_QUANT_CFG   MMIO32(NPU_BASE_ADDR + 0x40)        // RW: Shift & Zero Point
#define NPU_REG_QUANT_MULT  MMIO32(NPU_BASE_ADDR + 0x44)        // RW: Multiplicador PPU
#define NPU_REG_FLAGS       MMIO32(NPU_BASE_ADDR + 0x48)        // RW: Flags de Controle (ReLU)
#define NPU_REG_BIAS_BASE   MMIO32(NPU_BASE_ADDR + 0x80)        // RW: Base do vetor de Bias (0x80 a 0x8C)

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

// FLAGS (0x48)
#define NPU_FLAG_RELU       (1 << 0)                            // 1 = Ativa ReLU na saída

/* ============================================================================================================== */
/* TIMER MMIO                                                                                                     */
/* ============================================================================================================== */

#define TIMER_BASE_ADDR     0x50000000
#define TIMER_REG_CTRL      MMIO32(TIMER_BASE_ADDR + 0x00)
#define TIMER_REG_LOW       MMIO32(TIMER_BASE_ADDR + 0x04)
#define TIMER_REG_HIGH      MMIO32(TIMER_BASE_ADDR + 0x08)

#define TIMER_CTRL_EN      (1 << 0)

// ----------------------------------------------------------------------------------------------------------

#endif /* MEMORY_MAP_H */