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
-- Data      : [30/12/2025]    
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
        -- 1. INTERFACE COM O PROCESSADOR (CORE)
        -- ========================================================================================

        -- Barramento de Instruções (IMem - Fetch)
        imem_addr_i         : in  std_logic_vector(31 downto 0);
        imem_data_o         : out std_logic_vector(31 downto 0);

        -- Handshake da CPU
        imem_vld_i          : in  std_logic; 
        imem_rdy_o          : out std_logic;

        -- Barramento de Dados (DMem - Load/Store)
        dmem_addr_i         : in  std_logic_vector(31 downto 0);
        dmem_data_i         : in  std_logic_vector(31 downto 0); -- Dados para escrita
        dmem_we_i           : in  std_logic_vector( 3 downto 0); -- Write Enable
        dmem_data_o         : out std_logic_vector(31 downto 0); -- Dados lidos

        -- Handshake da CPU
        dmem_vld_i          : in  std_logic; 
        dmem_rdy_o          : out std_logic;

        -- ========================================================================================
        -- 2. INTERFACES PARA COMPONENTES (MEMÓRIAS E PERIFÉRICOS)
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
        npu_rdy_i           : in  std_logic

    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Definição da implementação do Interconectador de Barramento (BUS INTERCONNECT)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of bus_interconnect is

    -- Sinais internos de decodificação para o lado de DADOS (DMem)
    signal s_dmem_vld_rom  : std_logic;
    signal s_dmem_vld_uart : std_logic;
    signal s_dmem_vld_ram  : std_logic;
    signal s_dmem_vld_gpio : std_logic;
    signal s_dmem_vld_vga  : std_logic;
    signal s_dmem_vld_npu  : std_logic;

    -- Sinais internos de decodificação para o lado de INSTRUÇÕES (IMem)
    signal s_imem_vld_rom  : std_logic;
    signal s_imem_vld_ram  : std_logic;

begin

    -- -------------------------------------------------------------------------
    -- 1. DECODIFICAÇÃO DE ENDEREÇOS (Memory Map)
    -- -------------------------------------------------------------------------
    -- ROM:  0x00000000 (0x0...)
    -- UART: 0x10000000 (0x1...)
    -- GPIO: 0x20000000 (0x2...)
    -- VGA:  0x30000000 (0x3...)
    -- RAM:  0x80000000 (0x8...)
    -- NPU:  0x90000000 (0x9...)

    -- Lado de Dados
    s_dmem_vld_rom  <= '1' when dmem_addr_i(31 downto 28) = x"0" else '0';
    s_dmem_vld_uart <= '1' when dmem_addr_i(31 downto 28) = x"1" else '0';
    s_dmem_vld_gpio <= '1' when dmem_addr_i(31 downto 28) = x"2" else '0';
    s_dmem_vld_vga  <= '1' when dmem_addr_i(31 downto 28) = x"3" else '0';
    s_dmem_vld_ram  <= '1' when dmem_addr_i(31 downto 28) = x"8" else '0';
    s_dmem_vld_npu  <= '1' when dmem_addr_i(31 downto 28) = x"9" else '0';

    -- Lado de Instruções (Baseado no bit 31 para distinguir ROM de RAM)
    s_imem_vld_rom  <= '1' when imem_addr_i(31 downto 28) = x"0" else '0';
    s_imem_vld_ram  <= '1' when imem_addr_i(31 downto 28) = x"8" else '0';

    -- -------------------------------------------------------------------------
    -- 2. ROTEAMENTO PARA COMPONENTES (Saídas)
    -- -------------------------------------------------------------------------

    -- ROM
    rom_addr_a_o <= imem_addr_i;
    rom_addr_b_o <= dmem_addr_i;
    rom_vld_a_o  <= s_imem_vld_rom and imem_vld_i;
    rom_vld_b_o  <= s_dmem_vld_rom and dmem_vld_i;

    -- RAM
    ram_addr_a_o <= imem_addr_i;
    ram_addr_b_o <= dmem_addr_i;
    ram_data_b_o <= dmem_data_i;
    ram_we_b_o   <= dmem_we_i when (s_dmem_vld_ram = '1' and dmem_vld_i = '1') else (others => '0');
    ram_vld_a_o  <= s_imem_vld_ram and imem_vld_i;
    ram_vld_b_o  <= s_dmem_vld_ram and dmem_vld_i;

    -- UART
    uart_addr_o  <= dmem_addr_i(3 downto 0);
    uart_data_o  <= dmem_data_i;
    uart_we_o    <= '1' when (s_dmem_vld_uart = '1' and unsigned(dmem_we_i) > 0) else '0';
    uart_vld_o   <= s_dmem_vld_uart;

    -- GPIO
    gpio_addr_o  <= dmem_addr_i(3 downto 0);
    gpio_data_o  <= dmem_data_i;
    gpio_we_o    <= '1' when (s_dmem_vld_gpio = '1' and unsigned(dmem_we_i) > 0) else '0';
    gpio_vld_o   <= s_dmem_vld_gpio;

    -- VGA
    vga_addr_o  <= dmem_addr_i(16 downto 0); -- Endereço do Pixel
    vga_data_o  <= dmem_data_i;              -- Cor
    vga_we_o    <= '1' when (s_dmem_vld_vga = '1' and unsigned(dmem_we_i) > 0) else '0';
    vga_vld_o   <= s_dmem_vld_vga;

    -- NPU 
    npu_addr_o   <= dmem_addr_i; 
    npu_data_o   <= dmem_data_i;
    npu_we_o     <= '1' when (s_dmem_vld_npu = '1' and unsigned(dmem_we_i) > 0) else '0';
    npu_vld_o    <= s_dmem_vld_npu;

    -- -------------------------------------------------------------------------
    -- 3. MULTIPLEXAÇÃO DE RETORNO AO PROCESSADOR (Leitura)
    -- -------------------------------------------------------------------------

    -- Mux de Instrução (IMem) - DADOS
    process (s_imem_vld_rom, s_imem_vld_ram, rom_data_a_i, ram_data_a_i)
    begin
        if s_imem_vld_rom = '1' then
            imem_data_o <= rom_data_a_i;
        elsif s_imem_vld_ram = '1' then
            imem_data_o <= ram_data_a_i;
        else
            imem_data_o <= (others => '0');
        end if;
    end process;

    -- Mux de Instrução (IMem) - READY (Handshake) 
    process (s_imem_vld_rom, s_imem_vld_ram, rom_rdy_a_i, ram_rdy_a_i)
    begin
        if s_imem_vld_rom = '1' then
            imem_rdy_o <= rom_rdy_a_i;
        elsif s_imem_vld_ram = '1' then
            imem_rdy_o <= ram_rdy_a_i;
        else
            imem_rdy_o <= '1'; -- Endereço inválido retorna Ready=1 para não travar o core
        end if;
    end process;

    -- Mux de Dados (DMem)
    process (s_dmem_vld_rom, s_dmem_vld_uart, s_dmem_vld_ram, s_dmem_vld_gpio, 
             s_dmem_vld_vga, s_dmem_vld_npu, rom_data_b_i, uart_data_i, 
             ram_data_b_i, gpio_data_i, vga_data_i, npu_data_i)
    begin
        if s_dmem_vld_rom = '1' then
            dmem_data_o <= rom_data_b_i;
        elsif s_dmem_vld_uart = '1' then
            dmem_data_o <= uart_data_i;
        elsif s_dmem_vld_ram = '1' then
            dmem_data_o <= ram_data_b_i;
        elsif s_dmem_vld_gpio = '1' then
            dmem_data_o <= gpio_data_i;
        elsif s_dmem_vld_vga = '1' then
            dmem_data_o <= vga_data_i;
        elsif s_dmem_vld_npu = '1' then  
            dmem_data_o <= npu_data_i;
        else
            dmem_data_o <= (others => '0');
        end if;
    end process;

    -- Mux de Dados (DMem) - READY (Handshake)
    -- Retorna o ready do escravo selecionado. Se nenhum selecionado, ready=1 (para não travar CPU).
    process (s_dmem_vld_rom, s_dmem_vld_uart, s_dmem_vld_ram, s_dmem_vld_gpio, 
             s_dmem_vld_vga, s_dmem_vld_npu, rom_rdy_b_i, uart_rdy_i, 
             ram_rdy_b_i, gpio_rdy_i, vga_rdy_i, npu_rdy_i)
    begin
        if s_dmem_vld_rom = '1' then
            dmem_rdy_o <= rom_rdy_b_i;
        elsif s_dmem_vld_uart = '1' then
            dmem_rdy_o <= uart_rdy_i;
        elsif s_dmem_vld_ram = '1' then
            dmem_rdy_o <= ram_rdy_b_i;
        elsif s_dmem_vld_gpio = '1' then
            dmem_rdy_o <= gpio_rdy_i;
        elsif s_dmem_vld_vga = '1' then
            dmem_rdy_o <= vga_rdy_i;
        elsif s_dmem_vld_npu = '1' then  
            dmem_rdy_o <= npu_rdy_i;
        else
            dmem_rdy_o <= '1'; -- Endereço inválido não deve travar a CPU
        end if;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------