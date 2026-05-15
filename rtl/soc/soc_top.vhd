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
--             Arquitetura: Harvard Modificada com Crossbar e DMA Dual-Master.
-- 
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
        UART_RTS_i  : in  std_logic;         -- Entrada RTS da UART 

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

    -- Master Read (Acesso à Memória - Source)
        signal s_dma_m_rd_addr   : std_logic_vector(31 downto 0);
        signal s_dma_m_rd_data   : std_logic_vector(31 downto 0);
        signal s_dma_m_rd_vld    : std_logic;
        signal s_dma_m_rd_rdy    : std_logic;

    -- Master Write (Acesso à Memória/IP - Destino)
        signal s_dma_m_wr_addr   : std_logic_vector(31 downto 0);
        signal s_dma_m_wr_data   : std_logic_vector(31 downto 0);
        signal s_dma_m_wr_we     : std_logic;
        signal s_dma_m_wr_vld    : std_logic;
        signal s_dma_m_wr_rdy    : std_logic;
    
    -- Slave (Configuração via Bus)
        signal s_dma_s_addr      : std_logic_vector(3 downto 0);
        signal s_dma_s_wdata     : std_logic_vector(31 downto 0);
        signal s_dma_s_rdata     : std_logic_vector(31 downto 0);
        signal s_dma_s_we        : std_logic;
        signal s_dma_s_vld       : std_logic;
        signal s_dma_s_rdy       : std_logic;

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
        signal s_ram_data_a, s_ram_data_b : std_logic_vector(31 downto 0);     
        signal s_ram_data_w               : std_logic_vector(31 downto 0);     
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
        signal s_gpio_data_rx : std_logic_vector(31 downto 0);                 
        signal s_gpio_data_tx : std_logic_vector(31 downto 0);                 
        signal s_gpio_we      : std_logic;
        signal s_gpio_vld     : std_logic;
        signal s_gpio_rdy     : std_logic;

    -- VGA
        signal s_vga_addr    : std_logic_vector(16 downto 0);
        signal s_vga_data_rx : std_logic_vector(31 downto 0);                  
        signal s_vga_data_tx : std_logic_vector(31 downto 0);                  
        signal s_vga_we      : std_logic;
        signal s_vga_vld     : std_logic;
        signal s_vga_rdy     : std_logic;

    -- NPU 
        signal s_npu_addr     : std_logic_vector(31 downto 0);
        signal s_npu_data_rx  : std_logic_vector(31 downto 0);                 
        signal s_npu_data_tx  : std_logic_vector(31 downto 0);                 
        signal s_npu_we       : std_logic;
        signal s_npu_vld      : std_logic;
        signal s_npu_rst_n    : std_logic;
        signal s_npu_rdy      : std_logic;

    -- CLINT 
        signal s_clint_addr    : std_logic_vector(4 downto 0);
        signal s_clint_data_rx : std_logic_vector(31 downto 0);
        signal s_clint_data_tx : std_logic_vector(31 downto 0);
        signal s_clint_we      : std_logic;
        signal s_clint_vld     : std_logic;
        signal s_clint_rdy     : std_logic;

    -- PLIC 
        signal s_plic_addr     : std_logic_vector(23 downto 0);
        signal s_plic_data_rx  : std_logic_vector(31 downto 0);
        signal s_plic_data_tx  : std_logic_vector(31 downto 0);
        signal s_plic_we       : std_logic;
        signal s_plic_vld      : std_logic;
        signal s_plic_rdy      : std_logic;

    -- === Auxiliares =============================================================================================

    -- Sinais de Interrupção
        signal s_irq_external    : std_logic;
        signal s_irq_timer       : std_logic;
        signal s_irq_soft        : std_logic;

    -- Sinais de Interrupção dos Periféricos
        signal s_uart_irq        : std_logic;
        signal s_dma_irq         : std_logic;
        signal s_npu_irq         : std_logic;

    -- Vetor de Fontes de Interrupção para o PLIC
        signal s_plic_sources    : std_logic_vector(31 downto 0);

    -- === Controle de DEBUG ======================================================================================

        signal s_soc_en          : std_logic;
        signal s_is_fetch_stage  : std_logic;
        signal s_debug_rst       : std_logic; 
        signal s_sys_rst         : std_logic;

    -- Sinais de multiplexação UART
        signal s_uart_rx_soc     : std_logic;
        signal s_uart_rx_debug   : std_logic;
        signal s_uart_tx_soc     : std_logic;
        signal s_uart_tx_debug   : std_logic;

    -- Sinais de Leitura de Registradores (Debug)
        signal s_debug_reg_addr  : std_logic_vector(4 downto 0);
        signal s_debug_reg_data  : std_logic_vector(31 downto 0);

begin

    -- ============================================================================================================
    -- CONTROLE DE RESET E INTERRUPÇÕES
    -- ============================================================================================================

    s_sys_rst <= Reset_i OR s_debug_rst;

    s_plic_sources <= (
        1 => s_uart_irq, 
        2 => s_dma_irq,
        3 => s_npu_irq,
        others => '0'
    );

    -- ============================================================================================================
    -- MULTIPLEXAÇÃO FÍSICA DE DEBUG VIA RTS
    -- ============================================================================================================
    
    s_uart_rx_soc   <= UART_RX_i when UART_RTS_i = '0' else '1'; 
    s_uart_rx_debug <= UART_RX_i when UART_RTS_i = '1' else '1';
    UART_TX_o       <= s_uart_tx_debug when (UART_RTS_i = '1' or s_soc_en = '0') else s_uart_tx_soc;

    -- ============================================================================================================
    -- DEBUG CONTROLLER
    -- ============================================================================================================
    
    U_DEBUG: entity work.debug_controller
        generic map (
            CLK_FREQ         => CLK_FREQ,
            BAUD_RATE        => BAUD_RATE
        )
        port map (
            clk_i            => CLK_i,
            rst_i            => Reset_i,
            uart_rx_i        => s_uart_rx_debug,
            uart_tx_o        => s_uart_tx_debug,
            uart_rts_i       => UART_RTS_i,
            is_fetch_stage_i => s_is_fetch_stage,
            soc_en_o         => s_soc_en,
            debug_rst_o      => s_debug_rst,
            reg_addr_o       => s_debug_reg_addr,
            reg_data_i       => s_debug_reg_data,
            pc_i             => s_cpu_imem_addr
        );

    -- ============================================================================================================
    -- NÚCLEO PROCESSADOR (CPU)
    -- ============================================================================================================

    U_CORE: entity work.processor_top
        port map (
            CLK_i               => CLK_i,
            Reset_i             => s_sys_rst,
            soc_en_i            => s_soc_en,
            is_fetch_stage_o    => s_is_fetch_stage,
            debug_reg_addr_i    => s_debug_reg_addr,
            debug_reg_data_o    => s_debug_reg_data,
            IMem_addr_o         => s_cpu_imem_addr,
            IMem_data_i         => s_cpu_imem_data,
            IMem_vld_o          => s_cpu_imem_vld, 
            IMem_rdy_i          => s_cpu_imem_rdy,
            DMem_addr_o         => s_cpu_dmem_addr,
            DMem_data_o         => s_cpu_dmem_wdata,
            DMem_data_i         => s_cpu_dmem_rdata,
            DMem_we_o           => s_cpu_dmem_we,
            DMem_rdy_i          => s_cpu_dmem_rdy,
            DMem_vld_o          => s_cpu_dmem_vld,
            Irq_External_i      => s_irq_external,
            Irq_Timer_i         => s_irq_timer,
            Irq_Software_i      => s_irq_soft
        );

    -- ============================================================================================================
    -- DMA CONTROLLER (Dual-Master)
    -- ============================================================================================================
    
    U_DMA: entity work.dma_controller
        port map (
            clk_i       => CLK_i,
            rst_i       => s_sys_rst,
            soc_en_i    => s_soc_en,
            
            -- Slave (Config)
            cfg_addr_i  => s_dma_s_addr,
            cfg_data_i  => s_dma_s_wdata, 
            cfg_data_o  => s_dma_s_rdata, 
            cfg_we_i    => s_dma_s_we,
            cfg_vld_i   => s_dma_s_vld,
            cfg_rdy_o   => s_dma_s_rdy,
            
            -- Master Read (Source)
            m_rd_addr_o => s_dma_m_rd_addr,
            m_rd_vld_o  => s_dma_m_rd_vld,
            m_rd_data_i => s_dma_m_rd_data,
            m_rd_rdy_i  => s_dma_m_rd_rdy,

            -- Master Write (Destino)
            m_wr_addr_o => s_dma_m_wr_addr,
            m_wr_data_o => s_dma_m_wr_data,
            m_wr_we_o   => s_dma_m_wr_we,
            m_wr_vld_o  => s_dma_m_wr_vld,
            m_wr_rdy_i  => s_dma_m_wr_rdy,
            
            irq_done_o  => s_dma_irq
        );

    -- ============================================================================================================
    -- HUB DE INTERCONEXÃO (CROSSBAR INTERCONNECT)
    -- ============================================================================================================
    
    U_BUS: entity work.bus_interconnect
        port map (
            -- Sinais Globais
            clk_i => CLK_i,
            rst_i => s_sys_rst,

            -- Interface Core: IMem (CPU Direto)
            imem_addr_i => s_cpu_imem_addr,
            imem_data_o => s_cpu_imem_data,
            imem_vld_i  => s_cpu_imem_vld, 
            imem_rdy_o  => s_cpu_imem_rdy,

            -- Master 0: CPU DMem 
            cpu_addr_i  => s_cpu_dmem_addr,
            cpu_data_i  => s_cpu_dmem_wdata,
            cpu_we_i    => s_cpu_dmem_we,
            cpu_vld_i   => s_cpu_dmem_vld,
            cpu_data_o  => s_cpu_dmem_rdata,
            cpu_rdy_o   => s_cpu_dmem_rdy,

            -- Master 1: DMA Read
            dma_rd_addr_i => s_dma_m_rd_addr,
            dma_rd_vld_i  => s_dma_m_rd_vld,
            dma_rd_data_o => s_dma_m_rd_data,
            dma_rd_rdy_o  => s_dma_m_rd_rdy,

            -- Master 2: DMA Write
            dma_wr_addr_i => s_dma_m_wr_addr,
            dma_wr_data_i => s_dma_m_wr_data,
            dma_wr_we_i   => s_dma_m_wr_we,
            dma_wr_vld_i  => s_dma_m_wr_vld,
            dma_wr_rdy_o  => s_dma_m_wr_rdy,

            -- Interface ROM
            rom_addr_a_o => s_rom_addr_a, rom_data_a_i => s_rom_data_a,
            rom_addr_b_o => s_rom_addr_b, rom_data_b_i => s_rom_data_b,
            rom_vld_a_o  => s_rom_vld_a,  rom_rdy_a_i  => s_rom_rdy_a,
            rom_vld_b_o  => s_rom_vld_b,  rom_rdy_b_i  => s_rom_rdy_b,

            -- Interface RAM
            ram_addr_a_o => s_ram_addr_a, ram_data_a_i => s_ram_data_a,
            ram_addr_b_o => s_ram_addr_b, ram_data_b_i => s_ram_data_b,
            ram_data_b_o => s_ram_data_w,                               
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
            dma_data_i   => s_dma_s_rdata, 
            dma_data_o   => s_dma_s_wdata, 
            dma_we_o     => s_dma_s_we,
            dma_vld_o    => s_dma_s_vld,
            dma_rdy_i    => s_dma_s_rdy,

            -- Interface CLINT
            clint_addr_o  => s_clint_addr,
            clint_data_i  => s_clint_data_rx,
            clint_data_o  => s_clint_data_tx,
            clint_we_o    => s_clint_we,
            clint_vld_o   => s_clint_vld,
            clint_rdy_i   => s_clint_rdy,

            -- Interface PLIC
            plic_addr_o   => s_plic_addr, 
            plic_data_i   => s_plic_data_rx, 
            plic_data_o   => s_plic_data_tx, 
            plic_we_o     => s_plic_we, 
            plic_vld_o    => s_plic_vld, 
            plic_rdy_i    => s_plic_rdy
        );

    -- ============================================================================================================
    -- COMPONENTES DO SISTEMA
    -- ============================================================================================================

    U_ROM: entity work.boot_rom
        generic map ( INIT_FILE => INIT_FILE )
        port map (
            clk      => CLK_i,
            vld_a_i  => s_rom_vld_a, rdy_a_o  => s_rom_rdy_a, addr_a_i => s_rom_addr_a, data_a_o => s_rom_data_a,
            vld_b_i  => s_rom_vld_b, addr_b_i => s_rom_addr_b, data_b_o => s_rom_data_b, rdy_b_o  => s_rom_rdy_b
        );

    U_RAM: entity work.dual_port_ram
        generic map (ADDR_WIDTH => 16)  
        port map (
            clk      => CLK_i,
            vld_a_i  => s_ram_vld_a, rdy_a_o => s_ram_rdy_a, we_a => (others => '0'), addr_a => s_ram_addr_a(17 downto 2), data_a_i => (others => '0'), data_a_o => s_ram_data_a,
            vld_b_i  => s_ram_vld_b, we_b => s_ram_we_b, addr_b => s_ram_addr_b(17 downto 2), data_b_i => s_ram_data_w, data_b_o => s_ram_data_b, rdy_b_o => s_ram_rdy_b
        );

    U_UART : entity work.uart_controller
        generic map ( CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE )
        port map (
            clk => CLK_i, rst => s_sys_rst, addr_i => s_uart_addr, data_i => s_uart_data_tx, data_o => s_uart_data_rx, rdy_o => s_uart_rdy, we_i => s_uart_we, vld_i => s_uart_vld, uart_tx_pin => s_uart_tx_soc, uart_rx_pin => s_uart_rx_soc, irq_o => s_uart_irq
        );

    U_GPIO: entity work.gpio_controller
        port map (
            clk => CLK_i, rst => s_sys_rst, vld_i => s_gpio_vld, we_i => s_gpio_we, addr_i => s_gpio_addr, data_i => s_gpio_data_tx, data_o => s_gpio_data_rx, rdy_o => s_gpio_rdy, gpio_leds => GPIO_LEDS_o, gpio_sw => GPIO_SW_i
        );

    U_VGA: entity work.vga_peripheral
        port map (
            clk => CLK_i, rst => s_sys_rst, we_i => s_vga_we, addr_i => s_vga_addr, data_i => s_vga_data_tx, data_o => s_vga_data_rx, rdy_o => s_vga_rdy, vld_i => s_vga_vld, vga_hs_o => VGA_HS_o, vga_vs_o => VGA_VS_o, vga_r_o => VGA_R_o, vga_g_o => VGA_G_o, vga_b_o => VGA_B_o
        );

    U_CLINT: entity work.clint
        port map (
            clk_i => CLK_i, rst_i => s_sys_rst, soc_en_i => s_soc_en, addr_i => s_clint_addr, data_i => s_clint_data_tx, data_o => s_clint_data_rx, we_i => s_clint_we, vld_i => s_clint_vld, rdy_o => s_clint_rdy, irq_timer_o => s_irq_timer, irq_soft_o => s_irq_soft
        );

    U_PLIC: entity work.plic
        port map (
            Clk_i => CLK_i, Reset_i => s_sys_rst, Addr_i => s_plic_addr, Data_i => s_plic_data_tx, Data_o => s_plic_data_rx, We_i => s_plic_we, Vld_i => s_plic_vld, Rdy_o => s_plic_rdy, Irq_Sources_i => s_plic_sources, Irq_Req_o => s_irq_external
        );

    s_npu_rst_n <= not s_sys_rst;

    U_NPU: entity work.npu_top
        port map (
            clk => CLK_i, rst_n => s_npu_rst_n, soc_en_i => s_soc_en, vld_i => s_npu_vld, we_i => s_npu_we, addr_i => s_npu_addr, data_i => s_npu_data_tx, data_o => s_npu_data_rx, rdy_o => s_npu_rdy, irq_done_o => s_npu_irq
        );

end architecture;