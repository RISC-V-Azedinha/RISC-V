library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_wrapper is
    generic (
        INIT_FILE : string := "build/cocotb/boot/bootloader.hex"
    );
    port (
        clk_i           : in  std_logic;
        rst_i           : in  std_logic;

        -- CPU (Instruction)
        cpu_imem_addr_i : in  std_logic_vector(31 downto 0);
        cpu_imem_data_o : out std_logic_vector(31 downto 0);
        cpu_imem_vld_i  : in  std_logic;
        cpu_imem_rdy_o  : out std_logic;

        -- CPU (Data)
        cpu_dmem_addr_i : in  std_logic_vector(31 downto 0);
        cpu_dmem_wdata_i: in  std_logic_vector(31 downto 0);
        cpu_dmem_we_i   : in  std_logic_vector(3 downto 0);
        cpu_dmem_data_o : out std_logic_vector(31 downto 0);
        cpu_dmem_vld_i  : in  std_logic;
        cpu_dmem_rdy_o  : out std_logic;

        -- DMA Master
        dma_m_addr_i    : in  std_logic_vector(31 downto 0);
        dma_m_wdata_i   : in  std_logic_vector(31 downto 0);
        dma_m_we_i      : in  std_logic; 
        dma_m_data_o    : out std_logic_vector(31 downto 0);
        dma_m_vld_i     : in  std_logic;
        dma_m_rdy_o     : out std_logic;

        -- DMA Config Slave
        dma_s_addr_o    : out std_logic_vector(3 downto 0);
        dma_s_wdata_o   : out std_logic_vector(31 downto 0);
        dma_s_we_o      : out std_logic;
        dma_s_vld_o     : out std_logic;
        dma_s_rdata_i   : in  std_logic_vector(31 downto 0);
        dma_s_rdy_i     : in  std_logic
    );
end entity;

architecture struct of memory_wrapper is

    -- Sinais Internos
    signal arb_addr     : std_logic_vector(31 downto 0);
    signal arb_wdata    : std_logic_vector(31 downto 0);
    signal arb_we_bit   : std_logic;
    signal arb_we_vec   : std_logic_vector(3 downto 0); 
    signal arb_vld      : std_logic;
    signal arb_rdata    : std_logic_vector(31 downto 0);
    signal arb_rdy      : std_logic;

    -- Adaptação WE do DMA (1 bit -> 4 bits)
    signal dma_we_vec   : std_logic_vector(3 downto 0);

    -- Sinais ROM
    signal rom_rdata_a  : std_logic_vector(31 downto 0);
    signal rom_rdata_b  : std_logic_vector(31 downto 0);
    signal rom_vld_b    : std_logic; 
    signal rom_rdy_a    : std_logic;
    signal rom_rdy_b    : std_logic;
    
    -- Sinais RAM Port B
    signal ram_addr_b   : std_logic_vector(31 downto 0);
    signal ram_wdata_b  : std_logic_vector(31 downto 0);
    signal ram_rdata_b  : std_logic_vector(31 downto 0);
    signal ram_we_b     : std_logic_vector(3 downto 0);
    signal ram_vld_b    : std_logic;
    signal ram_rdy_b    : std_logic; 
    signal ram_rdy_a    : std_logic; -- Dummy

begin

    -- Expansão do Write Enable do DMA
    dma_we_vec <= (others => dma_m_we_i);
    
    U_ARBITER : entity work.bus_arbiter
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            -- Master 0: CPU
            m0_addr_i   => cpu_dmem_addr_i,
            m0_wdata_i  => cpu_dmem_wdata_i,
            m0_we_i     => cpu_dmem_we_i,
            m0_vld_i    => cpu_dmem_vld_i,
            m0_rdata_o  => cpu_dmem_data_o,
            m0_rdy_o    => cpu_dmem_rdy_o,
            -- Master 1: DMA
            m1_addr_i   => dma_m_addr_i,
            m1_wdata_i  => dma_m_wdata_i,
            m1_we_i     => dma_we_vec,
            m1_vld_i    => dma_m_vld_i,
            m1_rdata_o  => dma_m_data_o,
            m1_rdy_o    => dma_m_rdy_o,
            -- Slave (Interconnect)
            s_addr_o    => arb_addr,
            s_wdata_o   => arb_wdata,
            s_we_o      => arb_we_vec,
            s_vld_o     => arb_vld,
            s_rdata_i   => arb_rdata, 
            s_rdy_i     => arb_rdy
        );

    U_BUS : entity work.bus_interconnect
        port map (
            imem_addr_i => cpu_imem_addr_i,
            imem_data_o => cpu_imem_data_o,
            imem_vld_i  => cpu_imem_vld_i,
            imem_rdy_o  => cpu_imem_rdy_o,
            
            dmem_addr_i => arb_addr,
            dmem_data_i => arb_wdata,
            dmem_we_i   => arb_we_vec,
            dmem_data_o => arb_rdata, 
            dmem_vld_i  => arb_vld,
            dmem_rdy_o  => arb_rdy,
            
            -- ROM
            rom_addr_a_o => open, rom_data_a_i => rom_rdata_a,
            rom_addr_b_o => open, rom_data_b_i => rom_rdata_b,
            rom_vld_a_o  => open, rom_rdy_a_i => rom_rdy_a,
            rom_vld_b_o  => rom_vld_b, rom_rdy_b_i => rom_rdy_b,

            -- RAM
            ram_addr_a_o => open, ram_data_a_i => (others=>'0'),
            ram_addr_b_o => ram_addr_b, ram_data_b_i => ram_rdata_b,
            ram_data_b_o => ram_wdata_b, ram_we_b_o => ram_we_b,
            ram_vld_a_o  => open, ram_rdy_a_i => ram_rdy_a,
            ram_vld_b_o  => ram_vld_b, ram_rdy_b_i => ram_rdy_b,

            -- Periféricos
            dma_addr_o   => dma_s_addr_o,
            dma_data_o   => dma_s_wdata_o,
            dma_we_o     => dma_s_we_o,
            dma_vld_o    => dma_s_vld_o,
            dma_data_i   => dma_s_rdata_i,
            dma_rdy_i    => dma_s_rdy_i,

            uart_addr_o => open, uart_data_i => (others=>'0'), uart_rdy_i => '1',
            gpio_addr_o => open, gpio_data_i => (others=>'0'), gpio_rdy_i => '1',
            vga_addr_o => open, vga_data_i => (others=>'0'), vga_rdy_i => '1',
            npu_addr_o => open, npu_data_i => (others=>'0'), npu_rdy_i => '1'
        );

    -- 3. Boot ROM
    U_ROM : entity work.boot_rom
        generic map ( INIT_FILE => INIT_FILE )
        port map (
            clk      => clk_i,
            vld_a_i  => cpu_imem_vld_i,
            addr_a_i => cpu_imem_addr_i,
            data_a_o => rom_rdata_a,
            rdy_a_o  => rom_rdy_a,
            vld_b_i  => rom_vld_b,
            addr_b_i => arb_addr,
            data_b_o => rom_rdata_b,
            rdy_b_o  => rom_rdy_b
        );

    -- 4. Dual Port RAM
    U_RAM : entity work.dual_port_ram
        generic map (ADDR_WIDTH => 12)
        port map (
            clk => clk_i,
            vld_a_i    => '0',
            we_a       => (others=>'0'),
            addr_a     => (others=>'0'),
            data_a_i   => (others=>'0'),
            rdy_a_o    => ram_rdy_a,
            vld_b_i    => ram_vld_b,
            we_b       => ram_we_b,
            addr_b     => ram_addr_b(13 downto 2), 
            data_b_i   => ram_wdata_b,
            data_b_o   => ram_rdata_b,
            rdy_b_o    => ram_rdy_b
        );

end architecture;