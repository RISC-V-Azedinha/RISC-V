------------------------------------------------------------------------------------------------------------------
--
-- File: gpio_controller_wrapper.vhd
--
-- Descrição : Wrapper de simulação do gpio_controller com tempos curtos (filtro de 4 ciclos, varredura dos
--             displays de 8 ciclos por dígito e PWM sem prescaler), para o testbench não esperar milissegundos.
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity gpio_controller_wrapper is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        vld_i       : in  std_logic;
        we_i        : in  std_logic;
        addr_i      : in  std_logic_vector( 9 downto 0);
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        rdy_o       : out std_logic;
        irq_o       : out std_logic;
        ja_i        : in  std_logic_vector(7 downto 0);
        jb_i        : in  std_logic_vector(7 downto 0);
        jc_i        : in  std_logic_vector(7 downto 0);
        jd_i        : in  std_logic_vector(7 downto 0);
        ja_o        : out std_logic_vector(7 downto 0);
        jb_o        : out std_logic_vector(7 downto 0);
        jc_o        : out std_logic_vector(7 downto 0);
        jd_o        : out std_logic_vector(7 downto 0);
        ja_oe_o     : out std_logic_vector(7 downto 0);
        jb_oe_o     : out std_logic_vector(7 downto 0);
        jc_oe_o     : out std_logic_vector(7 downto 0);
        jd_oe_o     : out std_logic_vector(7 downto 0);
        gpio_leds   : out std_logic_vector(15 downto 0);
        gpio_sw     : in  std_logic_vector(15 downto 0);
        gpio_btn    : in  std_logic_vector( 3 downto 0);
        seg_n_o     : out std_logic_vector(6 downto 0);
        dp_n_o      : out std_logic;
        an_n_o      : out std_logic_vector(7 downto 0);
        rgb0_o      : out std_logic_vector(2 downto 0);
        rgb1_o      : out std_logic_vector(2 downto 0)
    );
end entity;

architecture sim of gpio_controller_wrapper is
begin
    U_DUT: entity work.gpio_controller
        generic map (DEBOUNCE_CYCLES => 4, SEG_SCAN_BITS => 6, PWM_PRESCALE => 0)
        port map (
            clk => clk, rst => rst, vld_i => vld_i, we_i => we_i, addr_i => addr_i, data_i => data_i,
            data_o => data_o, rdy_o => rdy_o, irq_o => irq_o,
            ja_i => ja_i, jb_i => jb_i, jc_i => jc_i, jd_i => jd_i,
            ja_o => ja_o, jb_o => jb_o, jc_o => jc_o, jd_o => jd_o,
            ja_oe_o => ja_oe_o, jb_oe_o => jb_oe_o, jc_oe_o => jc_oe_o, jd_oe_o => jd_oe_o,
            gpio_leds => gpio_leds, gpio_sw => gpio_sw, gpio_btn => gpio_btn,
            seg_n_o => seg_n_o, dp_n_o => dp_n_o, an_n_o => an_n_o, rgb0_o => rgb0_o, rgb1_o => rgb1_o
        );
end architecture;
