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
/* VGA DEFINITIONS (Preservado para compatibilidade com hal_vga.c)                                               */
/* ============================================================================================================== */
#define VGA_WIDTH               320
#define VGA_HEIGHT              240
#define VGA_VSYNC_OFFSET        0x1FFFF
#define VGA_VSYNC_ADDR          (VGA_BASE_ADDR + VGA_VSYNC_OFFSET)
#define VGA_VSYNC_BIT           (1 << 0)

/* ============================================================================================================== */
/* NEURAL PROCESSING UNIT (NPU) - Atualizado para robustez                                                        */
/* ============================================================================================================== */

// Registradores de Controle e Status (CSRs)
// Uso padronizado de MMIO32 para garantir acesso volatile correto

#define NPU_REG_CTRL        MMIO32(NPU_BASE_ADDR + 0x00)
#define NPU_REG_QUANT       MMIO32(NPU_BASE_ADDR + 0x04)
#define NPU_REG_MULT        MMIO32(NPU_BASE_ADDR + 0x08)
#define NPU_REG_STATUS      MMIO32(NPU_BASE_ADDR + 0x0C)

// FIFOs de Dados

#define NPU_FIFO_WEIGHTS    MMIO32(NPU_BASE_ADDR + 0x10)
#define NPU_FIFO_ACT        MMIO32(NPU_BASE_ADDR + 0x14)
#define NPU_FIFO_OUT        MMIO32(NPU_BASE_ADDR + 0x18)

// Configuração de Bias

#define NPU_REG_BIAS_BASE   MMIO32(NPU_BASE_ADDR + 0x20)

// Flags de Controle e Status

#define NPU_CTRL_RELU_EN    (1 << 0)
#define NPU_CTRL_LOAD_MODE  (1 << 1)
#define NPU_CTRL_ACC_CLEAR  (1 << 2)
#define NPU_CTRL_ACC_DUMP   (1 << 3)

#define NPU_STATUS_IN_FULL  (1 << 0)
#define NPU_STATUS_W_FULL   (1 << 1)
#define NPU_STATUS_OUT_RDY  (1 << 3)

#endif /* MEMORY_MAP_H */