#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

#include <stdint.h>

/* ============================================================================================================== */
/* CONFIGURAÇÃO DO BARRAMENTO (BASEADA NO BUS INTERCONNECT)                                                       */
/* ============================================================================================================== */

/* * Lógica do Bus Interconnect (bus_interconnect.vhd):
 * s_dmem_sel_uart <= '1' when dmem_addr_i(31 downto 28) = x"1"
 * s_dmem_sel_gpio <= '1' when dmem_addr_i(31 downto 28) = x"2"
 * s_dmem_sel_vga  <= '1' when dmem_addr_i(31 downto 28) = x"3"
 */

#define UART_BASE_ADDR      0x10000000   // Base da UART
#define GPIO_BASE_ADDR      0x20000000   // Base do GPIO
#define VGA_BASE_ADDR       0x30000000   // Base da VGA

/* ============================================================================================================== */
/* UART DEFINITIONS                                                                                               */
/* ============================================================================================================== */

#define UART_REG_DATA_OFFSET    0x00                                      // Offset do Registrador de Dados 
#define UART_REG_CTRL_OFFSET    0x04                                      // Offset do Registrador de Controle
#define UART_DATA_REG_ADDR      (UART_BASE_ADDR + UART_REG_DATA_OFFSET)   // Endereço do Registrador de Dados
#define UART_CTRL_REG_ADDR      (UART_BASE_ADDR + UART_REG_CTRL_OFFSET)   // Endereço do Registrador de Controle

/* Status Bits (Read) */

#define UART_STATUS_TX_BUSY     (1 << 0)                                  // Bit 0 - Transmissor ocupado 
#define UART_STATUS_RX_VALID    (1 << 1)                                  // Bit 1 - Dado recebido válido

/* Command Bits (Write) */

#define UART_CMD_RX_POP         (1 << 0)                                  // Bit 0 - Limpa a flag RX_VALID

/* ============================================================================================================== */
/* VGA DEFINITIONS                                                                                                */
/* ============================================================================================================== */

/* Memória VRAM começa em 0x30000000 */

#define VGA_WIDTH               320                                       // Largura da tela em pixels
#define VGA_HEIGHT              240                                       // Altura da tela em pixels

/* Offset do VSYNC (Endereço 0x1FFFF dentro da faixa da VGA) */
/* Endereço Físico: 0x30000000 + 0x1FFFF = 0x3001FFFF */

#define VGA_VSYNC_OFFSET        0x1FFFF                                   // Offset do Registrador VSYNC
#define VGA_VSYNC_ADDR          (VGA_BASE_ADDR + VGA_VSYNC_OFFSET)        // Endereço do Registrador VSYNC

/* ============================================================================================================== */
/* MACROS DE ACESSO                                                                                               */
/* ============================================================================================================== */

#define MMIO32(addr)            (*(volatile uint32_t *)(addr))            // Acesso a um registrador de 32 bits
#define MMIO8(addr)             (*(volatile uint8_t  *)(addr))            // Acesso a um registrador de 8 bits

#endif /* MEMORY_MAP_H */