------------------------------------------------------------------------------------------------------------------
-- 
-- File: bus_interconnect.vhd
-- 
--  ██████╗ ██╗   ██╗███████╗ 
--  ██╔══██╗██║   ██║██╔════╝ 
--  ██████╔╝██║   ██║███████╗ 
--  ██╔══██╗██║   ██║╚════██║ 
--  ██████╔╝╚██████╔╝███████║ 
--  ╚═════╝  ╚═════╝ ╚══════╝ 
-- 
-- Descrição : Interconectador de Barramento (Bus Interconnect) para o SoC RISC-V.
--             Realiza a decodificação de endereços e roteamento de dados entre 
--             o Processador (Mestre) e os componentes endereçáveis (ROM, RAM, UART).
-- 
-- Autor     : [André Maiolini]
-- Data      : [16/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Interconectador de Barramento (BUS INTERCONNECT)
-------------------------------------------------------------------------------------------------------------------

entity bus_interconnect is
    port (

        -- ========================================================================================
        -- INTERFACE COM O PROCESSADOR (CORE) - IMem
        -- ========================================================================================

        -- Barramento de Instruções (IMem - Fetch)

            imem_addr_i         : in  std_logic_vector(31 downto 0);
            imem_data_o         : out std_logic_vector(31 downto 0);

        -- Handshake da CPU

            imem_vld_i          : in  std_logic; 
            imem_rdy_o          : out std_logic;

        -- ========================================================================================
        -- INTERFACE COM O MASTER (ARBITER) - DMem
        -- ========================================================================================

        -- Barramento de Dados (DMem - Load/Store)

            dmem_addr_i         : in  std_logic_vector(31 downto 0);
            dmem_data_i         : in  std_logic_vector(31 downto 0); -- Dados para escrita
            dmem_we_i           : in  std_logic_vector( 3 downto 0); -- Write Enable
            dmem_data_o         : out std_logic_vector(31 downto 0); -- Dados lidos

        -- Handshake da CPU

            dmem_vld_i          : in  std_logic; 
            dmem_rdy_o          : out std_logic;

        -- ========================================================================================
        -- INTERFACES PARA COMPONENTES (MEMÓRIAS E PERIFÉRICOS)
        -- ========================================================================================

        -- Interface: Boot ROM (Dual Port)

            rom_addr_a_o        : out std_logic_vector(31 downto 0);
            rom_data_a_i        : in  std_logic_vector(31 downto 0);
            rom_addr_b_o        : out std_logic_vector(31 downto 0);
            rom_data_b_i        : in  std_logic_vector(31 downto 0);
            rom_vld_a_o         : out std_logic; 
            rom_rdy_a_i         : in  std_logic;
            rom_vld_b_o         : out std_logic; 
            rom_rdy_b_i         : in  std_logic;

        -- Interface: RAM (Dual Port)

            ram_addr_a_o        : out std_logic_vector(31 downto 0);
            ram_data_a_i        : in  std_logic_vector(31 downto 0);
            ram_addr_b_o        : out std_logic_vector(31 downto 0);
            ram_data_b_i        : in  std_logic_vector(31 downto 0); -- Leitura
            ram_data_b_o        : out std_logic_vector(31 downto 0); -- Escrita
            ram_we_b_o          : out std_logic_vector( 3 downto 0);
            ram_vld_a_o         : out std_logic;
            ram_rdy_a_i         : in  std_logic;
            ram_vld_b_o         : out std_logic;
            ram_rdy_b_i         : in  std_logic;

        -- Interface: UART

            uart_addr_o         : out std_logic_vector(3 downto 0);
            uart_data_i         : in  std_logic_vector(31 downto 0);
            uart_data_o         : out std_logic_vector(31 downto 0);
            uart_we_o           : out std_logic;
            uart_vld_o          : out std_logic;
            uart_rdy_i          : in  std_logic;
        
        -- Interface: GPIO

            gpio_addr_o         : out std_logic_vector(3 downto 0);
            gpio_data_i         : in  std_logic_vector(31 downto 0);
            gpio_data_o         : out std_logic_vector(31 downto 0);
            gpio_we_o           : out std_logic;
            gpio_vld_o          : out std_logic;
            gpio_rdy_i          : in  std_logic;

        -- Interface: VGA

            vga_addr_o          : out std_logic_vector(16 downto 0);
            vga_data_i          : in  std_logic_vector(31 downto 0); -- Leitura 
            vga_data_o          : out std_logic_vector(31 downto 0); -- Escrita (cor)
            vga_we_o            : out std_logic;
            vga_vld_o           : out std_logic;
            vga_rdy_i           : in  std_logic;

        -- Interface: NPU (Neural Processing Unit)

            npu_addr_o          : out std_logic_vector(31 downto 0); 
            npu_data_i          : in  std_logic_vector(31 downto 0); -- Leitura da NPU
            npu_data_o          : out std_logic_vector(31 downto 0); -- Escrita na NPU
            npu_we_o            : out std_logic;                     -- Write Enable
            npu_vld_o           : out std_logic;                     -- Chip Select
            npu_rdy_i           : in  std_logic;

        -- Interface: DMA Config (Slave Interface)

            dma_addr_o          : out std_logic_vector(3 downto 0); 
            dma_data_i          : in  std_logic_vector(31 downto 0); -- Read Config
            dma_data_o          : out std_logic_vector(31 downto 0); -- Write Config
            dma_we_o            : out std_logic;
            dma_vld_o           : out std_logic;
            dma_rdy_i           : in  std_logic;

        -- Interface Timer

            timer_addr_o        : out std_logic_vector(3 downto 0);
            timer_data_i        : in  std_logic_vector(31 downto 0);
            timer_data_o        : out std_logic_vector(31 downto 0);
            timer_we_o          : out std_logic;
            timer_vld_o         : out std_logic;
            timer_rdy_i         : in  std_logic

        -- ========================================================================================

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Definição da implementação do Interconectador de Barramento (BUS INTERCONNECT)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of bus_interconnect is

    type slave_t is (
        SLV_NONE, SLV_ROM, SLV_RAM, SLV_UART, SLV_GPIO, SLV_VGA, SLV_NPU, SLV_DMA, SLV_TIMER
    );

    signal imem_slv : slave_t;
    signal dmem_slv : slave_t;

begin

    --------------------------------------------------------------------------
    -- Address decode (com latch implícito)
    --------------------------------------------------------------------------
    imem_slv <= SLV_ROM   when imem_addr_i(31 downto 28) = x"0" else
                SLV_RAM   when imem_addr_i(31 downto 28) = x"8" else
                SLV_NONE;

    dmem_slv <= SLV_ROM   when dmem_addr_i(31 downto 28) = x"0" else
                SLV_UART  when dmem_addr_i(31 downto 28) = x"1" else
                SLV_GPIO  when dmem_addr_i(31 downto 28) = x"2" else
                SLV_VGA   when dmem_addr_i(31 downto 28) = x"3" else
                SLV_DMA   when dmem_addr_i(31 downto 28) = x"4" else
                SLV_TIMER when dmem_addr_i(31 downto 28) = x"5" else
                SLV_RAM   when dmem_addr_i(31 downto 28) = x"8" else
                SLV_NPU   when dmem_addr_i(31 downto 28) = x"9" else
                SLV_NONE;

    --------------------------------------------------------------------------
    -- IMEM
    --------------------------------------------------------------------------
    rom_addr_a_o <= imem_addr_i;
    ram_addr_a_o <= imem_addr_i;

    rom_vld_a_o <= imem_vld_i when imem_slv = SLV_ROM else '0';
    ram_vld_a_o <= imem_vld_i when imem_slv = SLV_RAM else '0';

    imem_data_o <= rom_data_a_i when imem_slv = SLV_ROM else
                   ram_data_a_i when imem_slv = SLV_RAM else
                   (others => '0');

    imem_rdy_o <= rom_rdy_a_i when imem_slv = SLV_ROM else
                  ram_rdy_a_i when imem_slv = SLV_RAM else
                  '0';

    --------------------------------------------------------------------------
    -- DMEM
    --------------------------------------------------------------------------
    rom_addr_b_o <= dmem_addr_i;
    ram_addr_b_o <= dmem_addr_i;
    ram_data_b_o <= dmem_data_i;
    ram_we_b_o   <= dmem_we_i when (dmem_slv = SLV_RAM and dmem_vld_i = '1') else (others => '0');

    rom_vld_b_o <= dmem_vld_i when dmem_slv = SLV_ROM else '0';
    ram_vld_b_o <= dmem_vld_i when dmem_slv = SLV_RAM else '0';

    uart_addr_o <= dmem_addr_i(3 downto 0);
    uart_data_o <= dmem_data_i;
    uart_we_o   <= '1' when (dmem_slv = SLV_UART and dmem_we_i /= "0000") else '0';
    uart_vld_o  <= dmem_vld_i when dmem_slv = SLV_UART else '0';

    gpio_addr_o <= dmem_addr_i(3 downto 0);
    gpio_data_o <= dmem_data_i;
    gpio_we_o   <= '1' when (dmem_slv = SLV_GPIO and dmem_we_i /= "0000") else '0';
    gpio_vld_o  <= dmem_vld_i when dmem_slv = SLV_GPIO else '0';

    vga_addr_o <= dmem_addr_i(16 downto 0);
    vga_data_o <= dmem_data_i;
    vga_we_o   <= '1' when (dmem_slv = SLV_VGA and dmem_we_i /= "0000") else '0';
    vga_vld_o  <= dmem_vld_i when dmem_slv = SLV_VGA else '0';

    npu_addr_o <= dmem_addr_i;
    npu_data_o <= dmem_data_i;
    npu_we_o   <= '1' when (dmem_slv = SLV_NPU and dmem_we_i /= "0000") else '0';
    npu_vld_o  <= dmem_vld_i when dmem_slv = SLV_NPU else '0';

    dma_addr_o <= dmem_addr_i(3 downto 0);
    dma_data_o <= dmem_data_i;
    dma_we_o   <= '1' when (dmem_slv = SLV_DMA and dmem_we_i /= "0000") else '0';
    dma_vld_o  <= dmem_vld_i when dmem_slv = SLV_DMA else '0';

    timer_addr_o <= dmem_addr_i(3 downto 0);
    timer_data_o <= dmem_data_i;
    timer_we_o   <= '1' when (dmem_slv = SLV_TIMER and dmem_we_i /= "0000") else '0';
    timer_vld_o  <= dmem_vld_i when dmem_slv = SLV_TIMER else '0';

    dmem_data_o <=
        rom_data_b_i  when dmem_slv = SLV_ROM   else
        ram_data_b_i  when dmem_slv = SLV_RAM   else
        uart_data_i   when dmem_slv = SLV_UART  else
        gpio_data_i   when dmem_slv = SLV_GPIO  else
        vga_data_i    when dmem_slv = SLV_VGA   else
        npu_data_i    when dmem_slv = SLV_NPU   else
        dma_data_i    when dmem_slv = SLV_DMA   else
        timer_data_i  when dmem_slv = SLV_TIMER else
        (others => '0');

    dmem_rdy_o <=
        rom_rdy_b_i when dmem_slv = SLV_ROM   else
        ram_rdy_b_i when dmem_slv = SLV_RAM   else
        uart_rdy_i  when dmem_slv = SLV_UART  else
        gpio_rdy_i  when dmem_slv = SLV_GPIO  else
        vga_rdy_i   when dmem_slv = SLV_VGA   else
        npu_rdy_i   when dmem_slv = SLV_NPU   else
        dma_rdy_i   when dmem_slv = SLV_DMA   else
        timer_rdy_i when dmem_slv = SLV_TIMER else
        '0';

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------