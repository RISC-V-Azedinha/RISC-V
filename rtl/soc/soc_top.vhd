------------------------------------------------------------------------------------------------------------------
-- 
-- File: soc_top.vhd
-- 
--   ███████╗ ██████╗  ██████╗    ████████╗ ██████╗ ██████╗ 
--   ██╔════╝██╔═══██╗██╔════╝    ╚══██╔══╝██╔═══██╗██╔══██╗
--   ███████╗██║   ██║██║            ██║   ██║   ██║██████╔╝
--   ╚════██║██║   ██║██║            ██║   ██║   ██║██╔═══╝ 
--   ███████║╚██████╔╝╚██████╗       ██║   ╚██████╔╝██║     
--   ╚══════╝ ╚═════╝  ╚═════╝       ╚═╝    ╚═════╝ ╚═╝     
-- 
-- Descrição : Top-level do SoC RISC-V. 
--             Integra o núcleo processador com memórias e periféricos reais.
--             Utiliza arquitetura Dual-Port para ROM e RAM (Harvard Modificada).
-- 
-- Autor     : [André Maiolini]
-- Data      : [30/12/2025]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv_isa_pkg.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do SoC Top-Level (SOC_TOP)
-------------------------------------------------------------------------------------------------------------------

entity soc_top is
    generic (

        INIT_FILE : string  := "build/fpga/boot/bootloader.hex";
        CLK_FREQ  : integer := 100_000_000;  -- Frequência do Clock em Hz
        BAUD_RATE : integer := 115_200       -- Taxa de Baud para a UART
    
    );
    port (

        -- Sinais de Controle do Sistema ------------------------------------------------
        CLK_i       : in  std_logic;         -- Clock de sistema
        Reset_i     : in  std_logic;         -- Sinal de Reset assíncrono ativo alto
        
        -- Pinos Externos (Interface UART) ----------------------------------------------
        UART_TX_o   : out std_logic;         -- Saída TX da UART
        UART_RX_i   : in  std_logic;         -- Entrada RX da UART

        -- Pinos Externos (Interface GPIO) ----------------------------------------------
        GPIO_LEDS_o : out std_logic_vector(15 downto 0);
        GPIO_SW_i   : in  std_logic_vector(15 downto 0);

        -- Pinos Externos (Interface VGA) -----------------------------------------------
        VGA_HS_o    : out std_logic;
        VGA_VS_o    : out std_logic;
        VGA_R_o     : out std_logic_vector(3 downto 0);
        VGA_G_o     : out std_logic_vector(3 downto 0);
        VGA_B_o     : out std_logic_vector(3 downto 0)

    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do SoC Top-Level (SOC_TOP)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of soc_top is

    -- === Sinais de Interconexão (Core <-> Hub) ===
    signal s_imem_addr                : std_logic_vector(31 downto 0);
    signal s_imem_data                : std_logic_vector(31 downto 0);
    signal s_dmem_addr                : std_logic_vector(31 downto 0);
    signal s_dmem_data_w              : std_logic_vector(31 downto 0);
    signal s_dmem_data_r              : std_logic_vector(31 downto 0);
    signal s_dmem_we                  : std_logic_vector( 3 downto 0);

    -- Sinais de Handshake (Core <-> Hub)
    signal s_imem_vld                 : std_logic; 
    signal s_imem_rdy                 : std_logic;
    signal s_dmem_vld                 : std_logic; 
    signal s_dmem_rdy                 : std_logic; 

    -- === Sinais de Interconexão (Hub <-> Componentes) ===
    
    -- Boot ROM
    signal s_rom_addr_a, s_rom_addr_b : std_logic_vector(31 downto 0);
    signal s_rom_data_a, s_rom_data_b : std_logic_vector(31 downto 0);
    signal s_rom_vld_a                : std_logic; 
    signal s_rom_rdy_a                : std_logic;
    signal s_rom_vld_b                : std_logic;
    signal s_rom_rdy_b                : std_logic;

    -- RAM
    signal s_ram_addr_a, s_ram_addr_b : std_logic_vector(31 downto 0);
    signal s_ram_data_a, s_ram_data_b : std_logic_vector(31 downto 0); -- Saídas da RAM
    signal s_ram_data_w               : std_logic_vector(31 downto 0); -- Entrada da RAM
    signal s_ram_we_b                 : std_logic_vector( 3 downto 0);
    signal s_ram_vld_a                : std_logic; 
    signal s_ram_rdy_a                : std_logic;
    signal s_ram_vld_b                : std_logic;
    signal s_ram_rdy_b                : std_logic;

    -- UART
    signal s_uart_addr                : std_logic_vector( 3 downto 0);
    signal s_uart_data_rx             : std_logic_vector(31 downto 0);
    signal s_uart_data_tx             : std_logic_vector(31 downto 0);
    signal s_uart_we                  : std_logic;
    signal s_uart_vld                 : std_logic;
    signal s_uart_rdy                 : std_logic;

    -- GPIO
    signal s_gpio_addr    : std_logic_vector(3 downto 0);
    signal s_gpio_data_rx : std_logic_vector(31 downto 0); -- Do GPIO para o Bus
    signal s_gpio_data_tx : std_logic_vector(31 downto 0); -- Do Bus para o GPIO
    signal s_gpio_we      : std_logic;
    signal s_gpio_vld     : std_logic;
    signal s_gpio_rdy     : std_logic;

    -- VGA
    signal s_vga_addr   : std_logic_vector(16 downto 0);
    signal s_vga_data_rx: std_logic_vector(31 downto 0); -- Dado lido da VRAM
    signal s_vga_data_tx: std_logic_vector(31 downto 0); -- Dado escrito na VRAM (Cor)
    signal s_vga_we     : std_logic;
    signal s_vga_vld    : std_logic;
    signal s_vga_rdy    : std_logic;

    -- NPU (Neural Processing Unit)
    signal s_npu_addr     : std_logic_vector(31 downto 0);
    signal s_npu_data_rx  : std_logic_vector(31 downto 0); -- NPU -> Bus
    signal s_npu_data_tx  : std_logic_vector(31 downto 0); -- Bus -> NPU
    signal s_npu_we       : std_logic;
    signal s_npu_vld      : std_logic;
    signal s_npu_rst_n    : std_logic;
    signal s_npu_rdy      : std_logic := '1';

begin

    -- =========================================================================
    -- NÚCLEO PROCESSADOR (CPU)
    -- =========================================================================

    U_CORE: entity work.processor_top
        port map (
            CLK_i               => CLK_i,
            Reset_i             => Reset_i,
            IMem_addr_o         => s_imem_addr,
            IMem_data_i         => s_imem_data,
            IMem_vld_o          => s_imem_vld, 
            IMem_rdy_i          => s_imem_rdy,
            DMem_addr_o         => s_dmem_addr,
            DMem_data_o         => s_dmem_data_w,
            DMem_data_i         => s_dmem_data_r,
            DMem_we_o           => s_dmem_we,
            DMem_rdy_i          => s_dmem_rdy,
            DMem_vld_o          => s_dmem_vld
        );

    -- =========================================================================
    -- HUB DE INTERCONEXÃO (BUS INTERCONNECT)
    -- =========================================================================
    
    U_BUS: entity work.bus_interconnect
        port map (
            -- Interface Core
            imem_addr_i     => s_imem_addr,
            imem_data_o     => s_imem_data,
            dmem_addr_i     => s_dmem_addr,
            dmem_data_i     => s_dmem_data_w,
            dmem_we_i       => s_dmem_we,
            dmem_data_o     => s_dmem_data_r,

            -- Handshake Core
            imem_vld_i      => s_imem_vld, 
            imem_rdy_o      => s_imem_rdy,
            dmem_vld_i      => s_dmem_vld,
            dmem_rdy_o      => s_dmem_rdy,

            -- Interface ROM
            rom_addr_a_o    => s_rom_addr_a,
            rom_data_a_i    => s_rom_data_a,
            rom_addr_b_o    => s_rom_addr_b,
            rom_data_b_i    => s_rom_data_b,
            rom_vld_a_o     => s_rom_vld_a, 
            rom_rdy_a_i     => s_rom_rdy_a,
            rom_vld_b_o     => s_rom_vld_b,
            rom_rdy_b_i     => s_rom_rdy_b,

            -- Interface RAM
            ram_addr_a_o    => s_ram_addr_a,
            ram_data_a_i    => s_ram_data_a,
            ram_addr_b_o    => s_ram_addr_b,
            ram_data_b_i    => s_ram_data_b,
            ram_data_b_o    => s_ram_data_w,
            ram_we_b_o      => s_ram_we_b,
            ram_vld_a_o     => s_ram_vld_a, 
            ram_rdy_a_i     => s_ram_rdy_a,
            ram_vld_b_o     => s_ram_vld_b,
            ram_rdy_b_i     => s_ram_rdy_b,

            -- Interface UART
            uart_addr_o     => s_uart_addr,
            uart_data_i     => s_uart_data_rx,
            uart_data_o     => s_uart_data_tx,
            uart_we_o       => s_uart_we,
            uart_vld_o      => s_uart_vld,
            uart_rdy_i      => s_uart_rdy,

            -- Interface GPIO
            gpio_addr_o     => s_gpio_addr,
            gpio_data_i     => s_gpio_data_rx,
            gpio_data_o     => s_gpio_data_tx,
            gpio_we_o       => s_gpio_we,
            gpio_vld_o      => s_gpio_vld,
            gpio_rdy_i      => s_gpio_rdy,

            -- Interface VGA
            vga_addr_o      => s_vga_addr,
            vga_data_i      => s_vga_data_rx, 
            vga_data_o      => s_vga_data_tx, 
            vga_we_o        => s_vga_we,
            vga_vld_o       => s_vga_vld,
            vga_rdy_i       => s_vga_rdy,

            -- Interface NPU 
            npu_addr_o      => s_npu_addr,
            npu_data_i      => s_npu_data_rx,
            npu_data_o      => s_npu_data_tx,
            npu_we_o        => s_npu_we,
            npu_vld_o       => s_npu_vld,
            npu_rdy_i       => s_npu_rdy

        );

    -- =========================================================================
    -- COMPONENTES DO SISTEMA
    -- =========================================================================

    U_ROM: entity work.boot_rom
        generic map (
            INIT_FILE => INIT_FILE
        )
        port map (
            clk          => CLK_i,
            vld_a_i      => s_rom_vld_a, 
            rdy_a_o      => s_rom_rdy_a,
            addr_a_i     => s_rom_addr_a,
            data_a_o     => s_rom_data_a,
            vld_b_i      => s_rom_vld_b,
            addr_b_i     => s_rom_addr_b,
            data_b_o     => s_rom_data_b,
            rdy_b_o      => s_rom_rdy_b
        );

    U_RAM: entity work.dual_port_ram
        generic map (ADDR_WIDTH => 15)  -- 128 KB de RAM
        port map (
            clk          => CLK_i,
            vld_a_i      => s_ram_vld_a, 
            rdy_a_o      => s_ram_rdy_a,
            we_a         => (others => '0'),
            addr_a       => s_ram_addr_a(16 downto 2),
            data_a_i     => (others => '0'),
            data_a_o     => s_ram_data_a,
            vld_b_i      => s_ram_vld_b,
            we_b         => s_ram_we_b,
            addr_b       => s_ram_addr_b(16 downto 2),
            data_b_i     => s_ram_data_w,
            data_b_o     => s_ram_data_b,
            rdy_b_o      => s_ram_rdy_b
        );

    U_UART : entity work.uart_controller
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk          => CLK_i,
            rst          => Reset_i,
            addr_i       => s_uart_addr,      
            data_i       => s_uart_data_tx,   
            data_o       => s_uart_data_rx,  
            rdy_o        => s_uart_rdy, 
            we_i         => s_uart_we,        
            vld_i        => s_uart_vld,
            uart_tx_pin  => UART_TX_o,
            uart_rx_pin  => UART_RX_i
        );

    U_GPIO: entity work.gpio_controller
        port map (
            clk         => CLK_i,
            rst         => Reset_i,
            
            -- Conexão com o Bus Interconnect
            vld_i       => s_gpio_vld,
            we_i        => s_gpio_we,
            addr_i      => s_gpio_addr,
            data_i      => s_gpio_data_tx,
            data_o      => s_gpio_data_rx,
            rdy_o       => s_gpio_rdy,
            gpio_leds   => GPIO_LEDS_o,
            gpio_sw     => GPIO_SW_i
        );

    U_VGA: entity work.vga_peripheral
        port map (
            clk         => CLK_i,
            rst         => Reset_i,
            
            -- Interface com o Processador
            we_i        => s_vga_we,
            addr_i      => s_vga_addr,
            data_i      => s_vga_data_tx,
            data_o      => s_vga_data_rx,
            rdy_o       => s_vga_rdy,
            vld_i       => s_vga_vld,
            
            -- Interface Física
            vga_hs_o    => VGA_HS_o,
            vga_vs_o    => VGA_VS_o,
            vga_r_o     => VGA_R_o,
            vga_g_o     => VGA_G_o,
            vga_b_o     => VGA_B_o
        );

    -- Inverte o Reset 
    s_npu_rst_n <= not Reset_i;

    U_NPU: entity work.npu_top
        port map (
            clk     => CLK_i,
            rst_n   => s_npu_rst_n,
            
            -- Conexão com o Bus Interconnect
            sel_i   => s_npu_vld,
            we_i    => s_npu_we,
            addr_i  => s_npu_addr,
            data_i  => s_npu_data_tx,
            data_o  => s_npu_data_rx
        );

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------