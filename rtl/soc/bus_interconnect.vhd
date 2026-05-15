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
-- Descrição : Interconectador de Barramento (Crossbar) para o SoC RISC-V.
--             Arquitetura Dual-Master + Sticky Arbitration para periféricos
--             multiciclo de latência variável. Proteção contra Bus Fault incluída.
-- 
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_interconnect is
    port (
        -- ========================================================================================
        -- SINAIS GERAIS DO SISTEMA
        -- ========================================================================================
        clk_i               : in  std_logic;
        rst_i               : in  std_logic;

        -- ========================================================================================
        -- INTERFACE CORE: IMem (Instruções - Porta A)
        -- ========================================================================================
        imem_addr_i         : in  std_logic_vector(31 downto 0);
        imem_data_o         : out std_logic_vector(31 downto 0);
        imem_vld_i          : in  std_logic; 
        imem_rdy_o          : out std_logic;

        -- ========================================================================================
        -- INTERFACE CROSSBAR: MESTRES DE DADOS (Portas B)
        -- ========================================================================================
        
        -- Master 0: CPU
        cpu_addr_i          : in  std_logic_vector(31 downto 0);
        cpu_data_i          : in  std_logic_vector(31 downto 0);
        cpu_we_i            : in  std_logic_vector( 3 downto 0);
        cpu_vld_i           : in  std_logic;
        cpu_data_o          : out std_logic_vector(31 downto 0);
        cpu_rdy_o           : out std_logic;

        -- Master 1: DMA Read (Apenas Leitura)
        dma_rd_addr_i       : in  std_logic_vector(31 downto 0);
        dma_rd_vld_i        : in  std_logic;
        dma_rd_data_o       : out std_logic_vector(31 downto 0);
        dma_rd_rdy_o        : out std_logic;

        -- Master 2: DMA Write (Apenas Escrita)
        dma_wr_addr_i       : in  std_logic_vector(31 downto 0);
        dma_wr_data_i       : in  std_logic_vector(31 downto 0);
        dma_wr_we_i         : in  std_logic;
        dma_wr_vld_i        : in  std_logic;
        dma_wr_rdy_o        : out std_logic;

        -- ========================================================================================
        -- INTERFACES DOS ESCRAVOS
        -- ========================================================================================

        -- Boot ROM
        rom_addr_a_o        : out std_logic_vector(31 downto 0);
        rom_data_a_i        : in  std_logic_vector(31 downto 0);
        rom_addr_b_o        : out std_logic_vector(31 downto 0);
        rom_data_b_i        : in  std_logic_vector(31 downto 0);
        rom_vld_a_o         : out std_logic;
        rom_rdy_a_i         : in  std_logic;
        rom_vld_b_o         : out std_logic;
        rom_rdy_b_i         : in  std_logic;

        -- RAM
        ram_addr_a_o        : out std_logic_vector(31 downto 0);
        ram_data_a_i        : in  std_logic_vector(31 downto 0);
        ram_addr_b_o        : out std_logic_vector(31 downto 0);
        ram_data_b_i        : in  std_logic_vector(31 downto 0);
        ram_data_b_o        : out std_logic_vector(31 downto 0);
        ram_we_b_o          : out std_logic_vector( 3 downto 0);
        ram_vld_a_o         : out std_logic;
        ram_rdy_a_i         : in  std_logic;
        ram_vld_b_o         : out std_logic;
        ram_rdy_b_i         : in  std_logic;

        -- UART
        uart_addr_o         : out std_logic_vector(3 downto 0);
        uart_data_i         : in  std_logic_vector(31 downto 0);
        uart_data_o         : out std_logic_vector(31 downto 0);
        uart_we_o           : out std_logic;
        uart_vld_o          : out std_logic;
        uart_rdy_i          : in  std_logic;

        -- GPIO
        gpio_addr_o         : out std_logic_vector(3 downto 0);
        gpio_data_i         : in  std_logic_vector(31 downto 0);
        gpio_data_o         : out std_logic_vector(31 downto 0);
        gpio_we_o           : out std_logic;
        gpio_vld_o          : out std_logic;
        gpio_rdy_i          : in  std_logic;

        -- VGA
        vga_addr_o          : out std_logic_vector(16 downto 0);
        vga_data_i          : in  std_logic_vector(31 downto 0);
        vga_data_o          : out std_logic_vector(31 downto 0);
        vga_we_o            : out std_logic;
        vga_vld_o           : out std_logic;
        vga_rdy_i           : in  std_logic;

        -- NPU
        npu_addr_o          : out std_logic_vector(31 downto 0);
        npu_data_i          : in  std_logic_vector(31 downto 0);
        npu_data_o          : out std_logic_vector(31 downto 0);
        npu_we_o            : out std_logic;
        npu_vld_o           : out std_logic;
        npu_rdy_i           : in  std_logic;

        -- DMA Config (Slave Interface)
        dma_addr_o          : out std_logic_vector(3 downto 0);
        dma_data_i          : in  std_logic_vector(31 downto 0);
        dma_data_o          : out std_logic_vector(31 downto 0);
        dma_we_o            : out std_logic;
        dma_vld_o           : out std_logic;
        dma_rdy_i           : in  std_logic;

        -- CLINT
        clint_addr_o        : out std_logic_vector(4 downto 0);
        clint_data_i        : in  std_logic_vector(31 downto 0);
        clint_data_o        : out std_logic_vector(31 downto 0);
        clint_we_o          : out std_logic;
        clint_vld_o         : out std_logic;
        clint_rdy_i         : in  std_logic;

        -- PLIC
        plic_addr_o         : out std_logic_vector(23 downto 0);
        plic_data_i         : in  std_logic_vector(31 downto 0);
        plic_data_o         : out std_logic_vector(31 downto 0);
        plic_we_o           : out std_logic;
        plic_vld_o          : out std_logic;
        plic_rdy_i          : in  std_logic
    );
end entity;

architecture rtl of bus_interconnect is

    type slave_t is (SLV_NONE, SLV_ROM, SLV_RAM, SLV_UART, SLV_GPIO, SLV_VGA, SLV_NPU, SLV_DMA, SLV_CLINT, SLV_PLIC);
    type master_id_t is (MST_NONE, MST_CPU, MST_DMA_RD, MST_DMA_WR);

    -- Sinais de Decodificação Alvo
    signal imem_slv   : slave_t;
    signal cpu_slv    : slave_t;
    signal dma_rd_slv : slave_t;
    signal dma_wr_slv : slave_t;
    signal cpu_we_bit : std_logic;

    -- Trava Sequencial (Locks)
    signal rom_owner_reg,   rom_owner_comb   : master_id_t;
    signal ram_owner_reg,   ram_owner_comb   : master_id_t;
    signal uart_owner_reg,  uart_owner_comb  : master_id_t;
    signal gpio_owner_reg,  gpio_owner_comb  : master_id_t;
    signal vga_owner_reg,   vga_owner_comb   : master_id_t;
    signal npu_owner_reg,   npu_owner_comb   : master_id_t;
    signal dma_owner_reg,   dma_owner_comb   : master_id_t;
    signal clint_owner_reg, clint_owner_comb : master_id_t;
    signal plic_owner_reg,  plic_owner_comb  : master_id_t;

    -- Função de decodificação de memória
    function decodifica(addr : std_logic_vector(31 downto 0)) return slave_t is
        variable nibble : std_logic_vector(3 downto 0);
    begin
        nibble := addr(31 downto 28);
        case nibble is
            when x"0" => return SLV_ROM;
            when x"1" => return SLV_UART;
            when x"2" => return SLV_GPIO;
            when x"3" => return SLV_VGA;
            when x"4" => return SLV_DMA;
            when x"5" => return SLV_CLINT;
            when x"6" => return SLV_PLIC;
            when x"8" => return SLV_RAM;
            when x"9" => return SLV_NPU;
            when others => return SLV_NONE;
        end case;
    end function;

begin

    -- ============================================================================================================
    -- DECODIFICAÇÃO DE ENDEREÇOS (CROSSBAR IN)
    -- ============================================================================================================
    imem_slv   <= decodifica(imem_addr_i)  when imem_vld_i = '1'   else SLV_NONE;
    cpu_slv    <= decodifica(cpu_addr_i)   when cpu_vld_i = '1'    else SLV_NONE;
    dma_rd_slv <= decodifica(dma_rd_addr_i) when dma_rd_vld_i = '1' else SLV_NONE;
    dma_wr_slv <= decodifica(dma_wr_addr_i) when dma_wr_vld_i = '1' else SLV_NONE;
    cpu_we_bit <= '1' when cpu_we_i /= "0000" else '0';

    -- ============================================================================================================
    -- IMEM (FETCH) - Caminho Exclusivo e Isolado
    -- ============================================================================================================
    rom_addr_a_o <= imem_addr_i;
    ram_addr_a_o <= imem_addr_i;
    rom_vld_a_o  <= imem_vld_i when imem_slv = SLV_ROM else '0';
    ram_vld_a_o  <= imem_vld_i when imem_slv = SLV_RAM else '0';
    
    imem_data_o  <= rom_data_a_i when imem_slv = SLV_ROM else
                    ram_data_a_i when imem_slv = SLV_RAM else (others => '0');
                    
    imem_rdy_o   <= rom_rdy_a_i  when imem_slv = SLV_ROM else
                    ram_rdy_a_i  when imem_slv = SLV_RAM else '0';

    -- ============================================================================================================
    -- RESOLUÇÃO DE ARBITRAGEM (COMBINACIONAL)
    -- ============================================================================================================
    rom_owner_comb <= rom_owner_reg when rom_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_ROM) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_ROM) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_ROM) else MST_NONE;
    ram_owner_comb <= ram_owner_reg when ram_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_RAM) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_RAM) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_RAM) else MST_NONE;
    uart_owner_comb <= uart_owner_reg when uart_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_UART) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_UART) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_UART) else MST_NONE;
    gpio_owner_comb <= gpio_owner_reg when gpio_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_GPIO) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_GPIO) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_GPIO) else MST_NONE;
    vga_owner_comb <= vga_owner_reg when vga_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_VGA) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_VGA) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_VGA) else MST_NONE;
    npu_owner_comb <= npu_owner_reg when npu_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_NPU) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_NPU) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_NPU) else MST_NONE;
    dma_owner_comb <= dma_owner_reg when dma_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_DMA) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_DMA) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_DMA) else MST_NONE;
    clint_owner_comb<= clint_owner_reg when clint_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_CLINT) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_CLINT) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_CLINT) else MST_NONE;
    plic_owner_comb <= plic_owner_reg when plic_owner_reg /= MST_NONE else MST_CPU when (cpu_vld_i='1' and cpu_slv=SLV_PLIC) else MST_DMA_RD when (dma_rd_vld_i='1' and dma_rd_slv=SLV_PLIC) else MST_DMA_WR when (dma_wr_vld_i='1' and dma_wr_slv=SLV_PLIC) else MST_NONE;

    -- ============================================================================================================
    -- REGISTRO DE TRAVA DE TRANSAÇÃO (SEQUENCIAL)
    -- ============================================================================================================
    process(clk_i, rst_i)
    begin
        if rst_i = '1' then
            rom_owner_reg <= MST_NONE; ram_owner_reg <= MST_NONE; uart_owner_reg <= MST_NONE;
            gpio_owner_reg <= MST_NONE; vga_owner_reg <= MST_NONE; npu_owner_reg <= MST_NONE;
            dma_owner_reg <= MST_NONE; clint_owner_reg <= MST_NONE; plic_owner_reg <= MST_NONE;
        elsif rising_edge(clk_i) then
            if rom_owner_comb /= MST_NONE then   if rom_rdy_b_i = '0' then rom_owner_reg <= rom_owner_comb;     else rom_owner_reg <= MST_NONE; end if; else rom_owner_reg <= MST_NONE; end if;
            if ram_owner_comb /= MST_NONE then   if ram_rdy_b_i = '0' then ram_owner_reg <= ram_owner_comb;     else ram_owner_reg <= MST_NONE; end if; else ram_owner_reg <= MST_NONE; end if;
            if uart_owner_comb /= MST_NONE then  if uart_rdy_i = '0' then uart_owner_reg <= uart_owner_comb;   else uart_owner_reg <= MST_NONE; end if; else uart_owner_reg <= MST_NONE; end if;
            if gpio_owner_comb /= MST_NONE then  if gpio_rdy_i = '0' then gpio_owner_reg <= gpio_owner_comb;   else gpio_owner_reg <= MST_NONE; end if; else gpio_owner_reg <= MST_NONE; end if;
            if vga_owner_comb /= MST_NONE then   if vga_rdy_i = '0' then vga_owner_reg <= vga_owner_comb;     else vga_owner_reg <= MST_NONE; end if; else vga_owner_reg <= MST_NONE; end if;
            if npu_owner_comb /= MST_NONE then   if npu_rdy_i = '0' then npu_owner_reg <= npu_owner_comb;     else npu_owner_reg <= MST_NONE; end if; else npu_owner_reg <= MST_NONE; end if;
            if dma_owner_comb /= MST_NONE then   if dma_rdy_i = '0' then dma_owner_reg <= dma_owner_comb;     else dma_owner_reg <= MST_NONE; end if; else dma_owner_reg <= MST_NONE; end if;
            if clint_owner_comb /= MST_NONE then if clint_rdy_i = '0' then clint_owner_reg <= clint_owner_comb; else clint_owner_reg <= MST_NONE; end if; else clint_owner_reg <= MST_NONE; end if;
            if plic_owner_comb /= MST_NONE then  if plic_rdy_i = '0' then plic_owner_reg <= plic_owner_comb;   else plic_owner_reg <= MST_NONE; end if; else plic_owner_reg <= MST_NONE; end if;
        end if;
    end process;

    -- ============================================================================================================
    -- ROTEAMENTO PARA OS ESCRAVOS
    -- ============================================================================================================

    -- RAM
    process(ram_owner_comb, cpu_addr_i, cpu_we_i, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        ram_vld_b_o <= '0'; ram_addr_b_o <= (others => '0'); ram_we_b_o <= "0000"; ram_data_b_o <= (others => '0');
        if ram_owner_comb = MST_CPU then
            ram_vld_b_o <= '1'; ram_addr_b_o <= cpu_addr_i; ram_we_b_o <= cpu_we_i; ram_data_b_o <= cpu_data_i;
        elsif ram_owner_comb = MST_DMA_RD then
            ram_vld_b_o <= '1'; ram_addr_b_o <= dma_rd_addr_i; ram_we_b_o <= "0000"; ram_data_b_o <= (others => '0');
        elsif ram_owner_comb = MST_DMA_WR then
            ram_vld_b_o <= '1'; ram_addr_b_o <= dma_wr_addr_i; ram_we_b_o <= (others => dma_wr_we_i); ram_data_b_o <= dma_wr_data_i;
        end if;
    end process;

    -- ROM
    process(rom_owner_comb, cpu_addr_i, dma_rd_addr_i, dma_wr_addr_i)
    begin
        rom_vld_b_o <= '0'; rom_addr_b_o <= (others => '0');
        if rom_owner_comb = MST_CPU then rom_vld_b_o <= '1'; rom_addr_b_o <= cpu_addr_i;
        elsif rom_owner_comb = MST_DMA_RD then rom_vld_b_o <= '1'; rom_addr_b_o <= dma_rd_addr_i;
        elsif rom_owner_comb = MST_DMA_WR then rom_vld_b_o <= '1'; rom_addr_b_o <= dma_wr_addr_i; end if;
    end process;

    -- NPU
    process(npu_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        npu_vld_o <= '0'; npu_addr_o <= (others => '0'); npu_we_o <= '0'; npu_data_o <= (others => '0');
        if npu_owner_comb = MST_CPU then
            npu_vld_o <= '1'; npu_addr_o <= cpu_addr_i; npu_we_o <= cpu_we_bit; npu_data_o <= cpu_data_i;
        elsif npu_owner_comb = MST_DMA_RD then
            npu_vld_o <= '1'; npu_addr_o <= dma_rd_addr_i; npu_we_o <= '0'; npu_data_o <= (others => '0');
        elsif npu_owner_comb = MST_DMA_WR then
            npu_vld_o <= '1'; npu_addr_o <= dma_wr_addr_i; npu_we_o <= dma_wr_we_i; npu_data_o <= dma_wr_data_i;
        end if;
    end process;

    -- UART
    process(uart_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        uart_vld_o <= '0'; uart_addr_o <= (others => '0'); uart_we_o <= '0'; uart_data_o <= (others => '0');
        if uart_owner_comb = MST_CPU then uart_vld_o <= '1'; uart_addr_o <= cpu_addr_i(3 downto 0); uart_we_o <= cpu_we_bit; uart_data_o <= cpu_data_i;
        elsif uart_owner_comb = MST_DMA_RD then uart_vld_o <= '1'; uart_addr_o <= dma_rd_addr_i(3 downto 0); uart_we_o <= '0'; uart_data_o <= (others => '0');
        elsif uart_owner_comb = MST_DMA_WR then uart_vld_o <= '1'; uart_addr_o <= dma_wr_addr_i(3 downto 0); uart_we_o <= dma_wr_we_i; uart_data_o <= dma_wr_data_i; end if;
    end process;

    -- GPIO
    process(gpio_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        gpio_vld_o <= '0'; gpio_addr_o <= (others => '0'); gpio_we_o <= '0'; gpio_data_o <= (others => '0');
        if gpio_owner_comb = MST_CPU then gpio_vld_o <= '1'; gpio_addr_o <= cpu_addr_i(3 downto 0); gpio_we_o <= cpu_we_bit; gpio_data_o <= cpu_data_i;
        elsif gpio_owner_comb = MST_DMA_RD then gpio_vld_o <= '1'; gpio_addr_o <= dma_rd_addr_i(3 downto 0); gpio_we_o <= '0'; gpio_data_o <= (others => '0');
        elsif gpio_owner_comb = MST_DMA_WR then gpio_vld_o <= '1'; gpio_addr_o <= dma_wr_addr_i(3 downto 0); gpio_we_o <= dma_wr_we_i; gpio_data_o <= dma_wr_data_i; end if;
    end process;

    -- VGA
    process(vga_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        vga_vld_o <= '0'; vga_addr_o <= (others => '0'); vga_we_o <= '0'; vga_data_o <= (others => '0');
        if vga_owner_comb = MST_CPU then vga_vld_o <= '1'; vga_addr_o <= cpu_addr_i(16 downto 0); vga_we_o <= cpu_we_bit; vga_data_o <= cpu_data_i;
        elsif vga_owner_comb = MST_DMA_RD then vga_vld_o <= '1'; vga_addr_o <= dma_rd_addr_i(16 downto 0); vga_we_o <= '0'; vga_data_o <= (others => '0');
        elsif vga_owner_comb = MST_DMA_WR then vga_vld_o <= '1'; vga_addr_o <= dma_wr_addr_i(16 downto 0); vga_we_o <= dma_wr_we_i; vga_data_o <= dma_wr_data_i; end if;
    end process;

    -- DMA CONFIG
    process(dma_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        dma_vld_o <= '0'; dma_addr_o <= (others => '0'); dma_we_o <= '0'; dma_data_o <= (others => '0');
        if dma_owner_comb = MST_CPU then dma_vld_o <= '1'; dma_addr_o <= cpu_addr_i(3 downto 0); dma_we_o <= cpu_we_bit; dma_data_o <= cpu_data_i;
        elsif dma_owner_comb = MST_DMA_RD then dma_vld_o <= '1'; dma_addr_o <= dma_rd_addr_i(3 downto 0); dma_we_o <= '0'; dma_data_o <= (others => '0');
        elsif dma_owner_comb = MST_DMA_WR then dma_vld_o <= '1'; dma_addr_o <= dma_wr_addr_i(3 downto 0); dma_we_o <= dma_wr_we_i; dma_data_o <= dma_wr_data_i; end if;
    end process;

    -- CLINT
    process(clint_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        clint_vld_o <= '0'; clint_addr_o <= (others => '0'); clint_we_o <= '0'; clint_data_o <= (others => '0');
        if clint_owner_comb = MST_CPU then clint_vld_o <= '1'; clint_addr_o <= cpu_addr_i(4 downto 0); clint_we_o <= cpu_we_bit; clint_data_o <= cpu_data_i;
        elsif clint_owner_comb = MST_DMA_RD then clint_vld_o <= '1'; clint_addr_o <= dma_rd_addr_i(4 downto 0); clint_we_o <= '0'; clint_data_o <= (others => '0');
        elsif clint_owner_comb = MST_DMA_WR then clint_vld_o <= '1'; clint_addr_o <= dma_wr_addr_i(4 downto 0); clint_we_o <= dma_wr_we_i; clint_data_o <= dma_wr_data_i; end if;
    end process;

    -- PLIC
    process(plic_owner_comb, cpu_addr_i, cpu_we_bit, cpu_data_i, dma_rd_addr_i, dma_wr_addr_i, dma_wr_we_i, dma_wr_data_i)
    begin
        plic_vld_o <= '0'; plic_addr_o <= (others => '0'); plic_we_o <= '0'; plic_data_o <= (others => '0');
        if plic_owner_comb = MST_CPU then plic_vld_o <= '1'; plic_addr_o <= cpu_addr_i(23 downto 0); plic_we_o <= cpu_we_bit; plic_data_o <= cpu_data_i;
        elsif plic_owner_comb = MST_DMA_RD then plic_vld_o <= '1'; plic_addr_o <= dma_rd_addr_i(23 downto 0); plic_we_o <= '0'; plic_data_o <= (others => '0');
        elsif plic_owner_comb = MST_DMA_WR then plic_vld_o <= '1'; plic_addr_o <= dma_wr_addr_i(23 downto 0); plic_we_o <= dma_wr_we_i; plic_data_o <= dma_wr_data_i; end if;
    end process;

    -- ============================================================================================================
    -- SINAIS DE RETORNO (DATA E READY) PARA OS MESTRES
    -- ============================================================================================================

    -- Retorno CPU
    cpu_data_o <= rom_data_b_i   when cpu_slv = SLV_ROM and rom_owner_comb = MST_CPU else
                  ram_data_b_i   when cpu_slv = SLV_RAM and ram_owner_comb = MST_CPU else
                  uart_data_i    when cpu_slv = SLV_UART and uart_owner_comb = MST_CPU else
                  gpio_data_i    when cpu_slv = SLV_GPIO and gpio_owner_comb = MST_CPU else
                  vga_data_i     when cpu_slv = SLV_VGA and vga_owner_comb = MST_CPU else
                  npu_data_i     when cpu_slv = SLV_NPU and npu_owner_comb = MST_CPU else
                  dma_data_i     when cpu_slv = SLV_DMA and dma_owner_comb = MST_CPU else
                  clint_data_i   when cpu_slv = SLV_CLINT and clint_owner_comb = MST_CPU else
                  plic_data_i    when cpu_slv = SLV_PLIC and plic_owner_comb = MST_CPU else
                  (others => '0');
                  
    cpu_rdy_o  <= rom_rdy_b_i    when cpu_slv = SLV_ROM and rom_owner_comb = MST_CPU else
                  ram_rdy_b_i    when cpu_slv = SLV_RAM and ram_owner_comb = MST_CPU else
                  uart_rdy_i     when cpu_slv = SLV_UART and uart_owner_comb = MST_CPU else
                  gpio_rdy_i     when cpu_slv = SLV_GPIO and gpio_owner_comb = MST_CPU else
                  vga_rdy_i      when cpu_slv = SLV_VGA and vga_owner_comb = MST_CPU else
                  npu_rdy_i      when cpu_slv = SLV_NPU and npu_owner_comb = MST_CPU else
                  dma_rdy_i      when cpu_slv = SLV_DMA and dma_owner_comb = MST_CPU else
                  clint_rdy_i    when cpu_slv = SLV_CLINT and clint_owner_comb = MST_CPU else
                  plic_rdy_i     when cpu_slv = SLV_PLIC and plic_owner_comb = MST_CPU else
                  '1'            when cpu_vld_i = '1' and cpu_slv = SLV_NONE else -- EVITA DEADLOCK (Bus Fault Virtual)
                  '0'            when cpu_vld_i = '1' else 
                  '1';

    -- Retorno DMA Read
    dma_rd_data_o <= rom_data_b_i when dma_rd_slv = SLV_ROM and rom_owner_comb = MST_DMA_RD else
                     ram_data_b_i when dma_rd_slv = SLV_RAM and ram_owner_comb = MST_DMA_RD else
                     uart_data_i  when dma_rd_slv = SLV_UART and uart_owner_comb = MST_DMA_RD else
                     gpio_data_i  when dma_rd_slv = SLV_GPIO and gpio_owner_comb = MST_DMA_RD else
                     vga_data_i   when dma_rd_slv = SLV_VGA and vga_owner_comb = MST_DMA_RD else
                     npu_data_i   when dma_rd_slv = SLV_NPU and npu_owner_comb = MST_DMA_RD else
                     dma_data_i   when dma_rd_slv = SLV_DMA and dma_owner_comb = MST_DMA_RD else
                     clint_data_i when dma_rd_slv = SLV_CLINT and clint_owner_comb = MST_DMA_RD else
                     plic_data_i  when dma_rd_slv = SLV_PLIC and plic_owner_comb = MST_DMA_RD else
                     (others => '0');
                     
    dma_rd_rdy_o  <= rom_rdy_b_i  when dma_rd_slv = SLV_ROM and rom_owner_comb = MST_DMA_RD else
                     ram_rdy_b_i  when dma_rd_slv = SLV_RAM and ram_owner_comb = MST_DMA_RD else
                     uart_rdy_i   when dma_rd_slv = SLV_UART and uart_owner_comb = MST_DMA_RD else
                     gpio_rdy_i   when dma_rd_slv = SLV_GPIO and gpio_owner_comb = MST_DMA_RD else
                     vga_rdy_i    when dma_rd_slv = SLV_VGA and vga_owner_comb = MST_DMA_RD else
                     npu_rdy_i    when dma_rd_slv = SLV_NPU and npu_owner_comb = MST_DMA_RD else
                     dma_rdy_i    when dma_rd_slv = SLV_DMA and dma_owner_comb = MST_DMA_RD else
                     clint_rdy_i  when dma_rd_slv = SLV_CLINT and clint_owner_comb = MST_DMA_RD else
                     plic_rdy_i   when dma_rd_slv = SLV_PLIC and plic_owner_comb = MST_DMA_RD else
                     '1'          when dma_rd_vld_i = '1' and dma_rd_slv = SLV_NONE else
                     '0'          when dma_rd_vld_i = '1' else 
                     '1';

    -- Retorno DMA Write
    dma_wr_rdy_o  <= rom_rdy_b_i  when dma_wr_slv = SLV_ROM and rom_owner_comb = MST_DMA_WR else
                     ram_rdy_b_i  when dma_wr_slv = SLV_RAM and ram_owner_comb = MST_DMA_WR else
                     uart_rdy_i   when dma_wr_slv = SLV_UART and uart_owner_comb = MST_DMA_WR else
                     gpio_rdy_i   when dma_wr_slv = SLV_GPIO and gpio_owner_comb = MST_DMA_WR else
                     vga_rdy_i    when dma_wr_slv = SLV_VGA and vga_owner_comb = MST_DMA_WR else
                     npu_rdy_i    when dma_wr_slv = SLV_NPU and npu_owner_comb = MST_DMA_WR else
                     dma_rdy_i    when dma_wr_slv = SLV_DMA and dma_owner_comb = MST_DMA_WR else
                     clint_rdy_i  when dma_wr_slv = SLV_CLINT and clint_owner_comb = MST_DMA_WR else
                     plic_rdy_i   when dma_wr_slv = SLV_PLIC and plic_owner_comb = MST_DMA_WR else
                     '1'          when dma_wr_vld_i = '1' and dma_wr_slv = SLV_NONE else
                     '0'          when dma_wr_vld_i = '1' else 
                     '1';

end architecture; -- rtl

------------------------------------------------------------------------------------------------------