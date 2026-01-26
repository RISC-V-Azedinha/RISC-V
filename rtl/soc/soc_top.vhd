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
--             Arquitetura: Harvard Modificada (Barramento de Dados Compartilhado com DMA).
-- 
-- Autor     : [André Maiolini]
-- Data      : [16/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do SoC Top-Level (SOC_TOP)
-------------------------------------------------------------------------------------------------------------------

entity soc_top is
    generic (

        INIT_FILE : string  := "build/fpga/boot/bootloader.hex";
        CLK_FREQ  : integer := 100_000_000;  -- Frequência do Clock em Hz
        BAUD_RATE : integer := 921_600       -- Taxa de Baud para a UART (bps)
    
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

    -- === Sinais da CPU ==========================================================================================

    -- Barramento de Instruções (IMem)
        
        signal s_cpu_imem_addr   : std_logic_vector(31 downto 0);
        signal s_cpu_imem_data   : std_logic_vector(31 downto 0);
        signal s_cpu_imem_vld    : std_logic; 
        signal s_cpu_imem_rdy    : std_logic;

    -- Barramento de Dados (DMem)
        
        signal s_cpu_dmem_addr   : std_logic_vector(31 downto 0);
        signal s_cpu_dmem_wdata  : std_logic_vector(31 downto 0);
        signal s_cpu_dmem_rdata  : std_logic_vector(31 downto 0);
        signal s_cpu_dmem_we     : std_logic_vector( 3 downto 0);
        signal s_cpu_dmem_vld    : std_logic; 
        signal s_cpu_dmem_rdy    : std_logic;

    -- === Sinais do DMA ==========================================================================================

    -- Master (Acesso à Memória)

        signal s_dma_m_addr      : std_logic_vector(31 downto 0);
        signal s_dma_m_wdata     : std_logic_vector(31 downto 0);
        signal s_dma_m_rdata     : std_logic_vector(31 downto 0);              -- Retorno do Arbiter
        signal s_dma_m_we        : std_logic;                                  -- 1 bit
        signal s_dma_m_vld       : std_logic;
        signal s_dma_m_rdy       : std_logic;
    
    -- Slave (Configuração via Bus)

        signal s_dma_s_addr      : std_logic_vector(3 downto 0);
        signal s_dma_s_wdata     : std_logic_vector(31 downto 0);
        signal s_dma_s_rdata     : std_logic_vector(31 downto 0);
        signal s_dma_s_we        : std_logic;
        signal s_dma_s_vld       : std_logic;
        signal s_dma_s_rdy       : std_logic;
    
    -- Interrupção

        -- signal s_dma_irq         : std_logic;

    -- === Sinais do Arbiter (Saída para o Interconnect) ==========================================================

        signal s_arb_addr        : std_logic_vector(31 downto 0);
        signal s_arb_wdata       : std_logic_vector(31 downto 0);
        signal s_arb_rdata       : std_logic_vector(31 downto 0);
        signal s_arb_we_bit      : std_logic;                                  -- 1 bit (não usado direto)
        signal s_arb_vld         : std_logic;
        signal s_arb_rdy         : std_logic;

    -- Mux de Write Enable (Combinação CPU 4-bits / DMA 1-bit)
        
        signal s_combined_we     : std_logic_vector(3 downto 0);

    -- === Sinais de Interconexão (Periféricos e Memórias) ========================================================
    
    -- Boot ROM

        signal s_rom_addr_a, s_rom_addr_b : std_logic_vector(31 downto 0);
        signal s_rom_data_a, s_rom_data_b : std_logic_vector(31 downto 0);
        signal s_rom_vld_a                : std_logic; 
        signal s_rom_rdy_a                : std_logic;
        signal s_rom_vld_b                : std_logic;
        signal s_rom_rdy_b                : std_logic;

    -- RAM

        signal s_ram_addr_a, s_ram_addr_b : std_logic_vector(31 downto 0);
        signal s_ram_data_a, s_ram_data_b : std_logic_vector(31 downto 0);     -- Saídas da RAM
        signal s_ram_data_w               : std_logic_vector(31 downto 0);     -- Entrada da RAM
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
        signal s_gpio_data_rx : std_logic_vector(31 downto 0);                 -- Do GPIO para o Bus
        signal s_gpio_data_tx : std_logic_vector(31 downto 0);                 -- Do Bus para o GPIO
        signal s_gpio_we      : std_logic;
        signal s_gpio_vld     : std_logic;
        signal s_gpio_rdy     : std_logic;

    -- VGA
        
        signal s_vga_addr   : std_logic_vector(16 downto 0);
        signal s_vga_data_rx: std_logic_vector(31 downto 0);                   -- Dado lido da VRAM
        signal s_vga_data_tx: std_logic_vector(31 downto 0);                   -- Dado escrito na VRAM (Cor)
        signal s_vga_we     : std_logic;
        signal s_vga_vld    : std_logic;
        signal s_vga_rdy    : std_logic;

    -- NPU (Neural Processing Unit)
        
        signal s_npu_addr     : std_logic_vector(31 downto 0);
        signal s_npu_data_rx  : std_logic_vector(31 downto 0);                 -- NPU -> Bus
        signal s_npu_data_tx  : std_logic_vector(31 downto 0);                 -- Bus -> NPU
        signal s_npu_we       : std_logic;
        signal s_npu_vld      : std_logic;
        signal s_npu_rst_n    : std_logic;
        signal s_npu_rdy      : std_logic;

    -- TIMER

        signal s_timer_addr    : std_logic_vector(3 downto 0);
        signal s_timer_data_rx : std_logic_vector(31 downto 0);
        signal s_timer_data_tx : std_logic_vector(31 downto 0);
        signal s_timer_we      : std_logic;
        signal s_timer_vld     : std_logic;
        signal s_timer_rdy     : std_logic;

    -- === Auxiliares =============================================================================================

    -- Sinais Auxiliares para o DMA WE expandido
    
        signal s_dma_we_expanded : std_logic_vector(3 downto 0);
        signal s_arb_we_vector   : std_logic_vector(3 downto 0);

    -- ============================================================================================================

begin

    -- ============================================================================================================
    -- Expansão do WE do DMA (1 bit -> 4 bits) ANTES do Arbiter
    -- ============================================================================================================

    s_dma_we_expanded <= (others => s_dma_m_we);

    -- ============================================================================================================
    -- NÚCLEO PROCESSADOR (CPU)
    -- ============================================================================================================

    U_CORE: entity work.processor_top
        port map (
            CLK_i               => CLK_i,
            Reset_i             => Reset_i,
            IMem_addr_o         => s_cpu_imem_addr,
            IMem_data_i         => s_cpu_imem_data,
            IMem_vld_o          => s_cpu_imem_vld, 
            IMem_rdy_i          => s_cpu_imem_rdy,
            DMem_addr_o         => s_cpu_dmem_addr,
            DMem_data_o         => s_cpu_dmem_wdata,
            DMem_data_i         => s_cpu_dmem_rdata,
            DMem_we_o           => s_cpu_dmem_we,
            DMem_rdy_i          => s_cpu_dmem_rdy,
            DMem_vld_o          => s_cpu_dmem_vld
        );

    -- =========================================================================
    -- DMA CONTROLLER
    -- =========================================================================
    
    U_DMA: entity work.dma_controller
        port map (
            clk_i       => CLK_i,
            rst_i       => Reset_i,
            cfg_addr_i  => s_dma_s_addr,
            cfg_data_i  => s_dma_s_wdata, 
            cfg_data_o  => s_dma_s_rdata, 
            cfg_we_i    => s_dma_s_we,
            cfg_vld_i   => s_dma_s_vld,
            cfg_rdy_o   => s_dma_s_rdy,
            m_addr_o    => s_dma_m_addr,
            m_data_o    => s_dma_m_wdata,
            m_data_i    => s_dma_m_rdata, 
            m_we_o      => s_dma_m_we, 
            m_vld_o     => s_dma_m_vld,
            m_rdy_i     => s_dma_m_rdy,
            irq_done_o  => open
        );

    -- =========================================================================
    -- BUS ARBITER (Gerencia CPU vs DMA no Canal de Dados)
    -- =========================================================================
    
    U_ARBITER: entity work.bus_arbiter
        port map (
            clk_i       => CLK_i,
            rst_i       => Reset_i,
            
            -- Master 0: CPU
            m0_addr_i   => s_cpu_dmem_addr,
            m0_wdata_i  => s_cpu_dmem_wdata,
            m0_we_i     => s_cpu_dmem_we,   
            m0_vld_i    => s_cpu_dmem_vld,
            m0_rdata_o  => s_cpu_dmem_rdata,
            m0_rdy_o    => s_cpu_dmem_rdy,
            
            -- Master 1: DMA
            m1_addr_i   => s_dma_m_addr,
            m1_wdata_i  => s_dma_m_wdata,
            m1_we_i     => s_dma_we_expanded,
            m1_vld_i    => s_dma_m_vld,
            m1_rdata_o  => s_dma_m_rdata,
            m1_rdy_o    => s_dma_m_rdy,
            
            -- Slave Output: Vai para DMem port do Interconnect
            s_addr_o    => s_arb_addr,
            s_wdata_o   => s_arb_wdata,
            s_we_o      => s_arb_we_vector,
            s_vld_o     => s_arb_vld,
            s_rdata_i   => s_arb_rdata,
            s_rdy_i     => s_arb_rdy
        );

    -- ============================================================================================================
    -- HUB DE INTERCONEXÃO (BUS INTERCONNECT)
    -- ============================================================================================================
    
    U_BUS: entity work.bus_interconnect
        port map (
            -- Interface Core: IMem (CPU Direto)
            imem_addr_i => s_cpu_imem_addr,
            imem_data_o => s_cpu_imem_data,
            imem_vld_i  => s_cpu_imem_vld, 
            imem_rdy_o  => s_cpu_imem_rdy,

            -- Interface Core: DMem (Vem do Arbiter!)
            dmem_addr_i => s_arb_addr,
            dmem_data_i => s_arb_wdata,
            dmem_we_i   => s_arb_we_vector,
            dmem_data_o => s_arb_rdata,
            dmem_vld_i  => s_arb_vld,
            dmem_rdy_o  => s_arb_rdy,

            -- Interface ROM
            rom_addr_a_o => s_rom_addr_a, rom_data_a_i => s_rom_data_a,
            rom_addr_b_o => s_rom_addr_b, rom_data_b_i => s_rom_data_b,
            rom_vld_a_o  => s_rom_vld_a,  rom_rdy_a_i  => s_rom_rdy_a,
            rom_vld_b_o  => s_rom_vld_b,  rom_rdy_b_i  => s_rom_rdy_b,

            -- Interface RAM
            ram_addr_a_o => s_ram_addr_a, ram_data_a_i => s_ram_data_a,
            ram_addr_b_o => s_ram_addr_b, ram_data_b_i => s_ram_data_b, -- Read
            ram_data_b_o => s_ram_data_w,                               -- Write
            ram_we_b_o   => s_ram_we_b,
            ram_vld_a_o  => s_ram_vld_a,  ram_rdy_a_i  => s_ram_rdy_a,
            ram_vld_b_o  => s_ram_vld_b,  ram_rdy_b_i  => s_ram_rdy_b,

            -- Interface UART
            uart_addr_o  => s_uart_addr,    uart_data_i  => s_uart_data_rx,
            uart_data_o  => s_uart_data_tx, uart_we_o    => s_uart_we,
            uart_vld_o   => s_uart_vld,     uart_rdy_i   => s_uart_rdy,

            -- Interface GPIO
            gpio_addr_o  => s_gpio_addr,    gpio_data_i  => s_gpio_data_rx,
            gpio_data_o  => s_gpio_data_tx, gpio_we_o    => s_gpio_we,
            gpio_vld_o   => s_gpio_vld,     gpio_rdy_i   => s_gpio_rdy,

            -- Interface VGA
            vga_addr_o   => s_vga_addr,     vga_data_i   => s_vga_data_rx,
            vga_data_o   => s_vga_data_tx,  vga_we_o     => s_vga_we,
            vga_vld_o    => s_vga_vld,      vga_rdy_i    => s_vga_rdy,

            -- Interface NPU 
            npu_addr_o   => s_npu_addr,     npu_data_i   => s_npu_data_rx,
            npu_data_o   => s_npu_data_tx,  npu_we_o     => s_npu_we,
            npu_vld_o    => s_npu_vld,      npu_rdy_i    => s_npu_rdy,
            
            -- DMA Slave (Config)
            dma_addr_o   => s_dma_s_addr,
            dma_data_i   => s_dma_s_rdata, -- Interconnect lê do DMA
            dma_data_o   => s_dma_s_wdata, -- Interconnect escreve no DMA
            dma_we_o     => s_dma_s_we,
            dma_vld_o    => s_dma_s_vld,
            dma_rdy_i    => s_dma_s_rdy,

            -- Interface TIMER
            timer_addr_o  => s_timer_addr,
            timer_data_i  => s_timer_data_rx,
            timer_data_o  => s_timer_data_tx,
            timer_we_o    => s_timer_we,
            timer_vld_o   => s_timer_vld,
            timer_rdy_i   => s_timer_rdy
            
        );

    -- ============================================================================================================
    -- COMPONENTES DO SISTEMA
    -- ============================================================================================================

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
        generic map (ADDR_WIDTH => 16)  -- 256 KB de RAM
        port map (
            clk          => CLK_i,
            vld_a_i      => s_ram_vld_a, 
            rdy_a_o      => s_ram_rdy_a,
            we_a         => (others => '0'),
            addr_a       => s_ram_addr_a(17 downto 2),
            data_a_i     => (others => '0'),
            data_a_o     => s_ram_data_a,
            vld_b_i      => s_ram_vld_b,
            we_b         => s_ram_we_b,
            addr_b       => s_ram_addr_b(17 downto 2),
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

    U_TIMER: entity work.timer_controller
        port map (
            clk_i   => CLK_i,
            rst_i   => Reset_i,
            addr_i  => s_timer_addr,
            data_i  => s_timer_data_tx,
            data_o  => s_timer_data_rx,
            we_i    => s_timer_we,
            vld_i   => s_timer_vld,
            rdy_o   => s_timer_rdy
        );

    -- Inverte o Reset 
    s_npu_rst_n <= not Reset_i;

    U_NPU: entity work.npu_top
        port map (
            clk     => CLK_i,
            rst_n   => s_npu_rst_n,
            
            -- Conexão com o Bus Interconnect
            vld_i   => s_npu_vld,
            we_i    => s_npu_we,
            addr_i  => s_npu_addr,
            data_i  => s_npu_data_tx,
            data_o  => s_npu_data_rx,
            rdy_o   => s_npu_rdy
        );

    -- ============================================================================================================

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------