------------------------------------------------------------------------------------------------------------------
--
-- File: rgb_pwm.vhd
--
-- Descrição : PWM de 8 bits para os dois LEDs RGB (LD16 e LD17).
--
--             Registradores (offset dentro do bloco):
--               0x00 RGB0 (RW) LD16: 0x00RRGGBB (brilho 0..255 de cada cor)
--               0x04 RGB1 (RW) LD17: 0x00RRGGBB
--
--             Os LEDs RGB da placa são muito fortes: o PWM tem 2^(8+DIM) passos e o brilho (0..255) só cobre
--             os 256 primeiros, então o brilho máximo é 1/2^DIM do LED ligado direto (1/8 com DIM = 3).
--             Período: 2^(8+DIM) passos de 2^PRESCALE ciclos (12 kHz a 100 MHz com DIM = 3 e PRESCALE = 2).
--
-- Autor     : [André Maiolini]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgb_pwm is
    generic (
        PRESCALE : integer := 2;
        DIM      : integer := 3
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        we_i     : in  std_logic;
        sel_i    : in  std_logic_vector(3 downto 0);
        data_i   : in  std_logic_vector(31 downto 0);
        data_o   : out std_logic_vector(31 downto 0);

        rgb0_o   : out std_logic_vector(2 downto 0);          -- LD16: bit 0 = R, bit 1 = G, bit 2 = B
        rgb1_o   : out std_logic_vector(2 downto 0)           -- LD17
    );
end entity;

architecture rtl of rgb_pwm is

    signal r_rgb0, r_rgb1 : std_logic_vector(23 downto 0) := (others => '0');
    signal r_cnt          : unsigned(PRESCALE+DIM+7 downto 0) := (others => '0');
    signal s_phase        : unsigned(DIM+7 downto 0);

begin

    s_phase <= r_cnt(PRESCALE+DIM+7 downto PRESCALE);

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_cnt  <= (others => '0');
                r_rgb0 <= (others => '0');
                r_rgb1 <= (others => '0');
                rgb0_o <= (others => '0');
                rgb1_o <= (others => '0');
            else
                r_cnt <= r_cnt + 1;

                -- Cada cor fica acesa enquanto a fase for menor que o seu brilho (0 = sempre apagada)
                for c in 0 to 2 loop
                    if s_phase < resize(unsigned(r_rgb0(23-8*c downto 16-8*c)), DIM+8) then rgb0_o(c) <= '1'; else rgb0_o(c) <= '0'; end if;
                    if s_phase < resize(unsigned(r_rgb1(23-8*c downto 16-8*c)), DIM+8) then rgb1_o(c) <= '1'; else rgb1_o(c) <= '0'; end if;
                end loop;

                if we_i = '1' then
                    case to_integer(unsigned(sel_i)) is
                        when 0 => r_rgb0 <= data_i(23 downto 0);
                        when 1 => r_rgb1 <= data_i(23 downto 0);
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    process(sel_i, r_rgb0, r_rgb1)
    begin
        data_o <= (others => '0');
        case to_integer(unsigned(sel_i)) is
            when 0 => data_o(23 downto 0) <= r_rgb0;
            when 1 => data_o(23 downto 0) <= r_rgb1;
            when others => null;
        end case;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------
