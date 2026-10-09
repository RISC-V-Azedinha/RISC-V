------------------------------------------------------------------------------------------------------------------
--
-- File: seg7_controller.vhd
--
-- Descrição : Controlador dos 8 displays de 7 segmentos, com varredura em hardware.
--
--             Os 8 dígitos compartilham os catodos (CA..CG, DP); o controlador acende um dígito por vez
--             (ânodo ativo em nível baixo), rápido o bastante para o olho ver todos acesos.
--
--             Registradores (offset dentro do bloco):
--               0x00 CTRL   (RW) bit 0 RAW: 0 = cada dígito mostra o seu nibble de HEX; 1 = segmentos crus
--               0x04 HEX    (RW) 8 nibbles; o nibble i (bits 4i+3..4i) vai para o dígito i (dígito 0 à direita)
--               0x08 RAW_LO (RW) segmentos crus dos dígitos 0..3 (byte i = dígito i)
--               0x0C RAW_HI (RW) segmentos crus dos dígitos 4..7 (byte i = dígito 4 + i)
--               0x10 DP     (RW) ponto decimal de cada dígito (bit i = dígito i), no modo HEX
--               0x14 EN     (RW) dígitos ligados (bit i = dígito i); 0 após o reset = displays apagados
--
--             Segmentos crus: bit 0 = a, ..., bit 6 = g, bit 7 = dp; 1 = aceso.
--
-- Autor     : [André Maiolini]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_controller is
    generic (
        SCAN_BITS : integer := 17                             -- Cada dígito fica aceso 2^(SCAN_BITS-3) ciclos
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        we_i     : in  std_logic;
        sel_i    : in  std_logic_vector(3 downto 0);
        data_i   : in  std_logic_vector(31 downto 0);
        data_o   : out std_logic_vector(31 downto 0);

        seg_n_o  : out std_logic_vector(6 downto 0);          -- CA..CG, ativos em nível baixo
        dp_n_o   : out std_logic;                             -- DP, ativo em nível baixo
        an_n_o   : out std_logic_vector(7 downto 0)           -- Ânodos AN0..AN7, ativos em nível baixo
    );
end entity;

architecture rtl of seg7_controller is

    signal r_ctrl  : std_logic := '0';
    signal r_hex   : std_logic_vector(31 downto 0) := (others => '0');
    signal r_raw   : std_logic_vector(63 downto 0) := (others => '0');
    signal r_dp    : std_logic_vector(7 downto 0)  := (others => '0');
    signal r_en    : std_logic_vector(7 downto 0)  := (others => '0');
    signal r_scan  : unsigned(SCAN_BITS-1 downto 0) := (others => '0');

    signal s_digit : integer range 0 to 7;
    signal s_segs  : std_logic_vector(7 downto 0);            -- dp & g..a, 1 = aceso

    -- Decodificador hexadecimal: bit 0 = a ... bit 6 = g
    function hex7(n : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case n is
            when x"0" => return "0111111";
            when x"1" => return "0000110";
            when x"2" => return "1011011";
            when x"3" => return "1001111";
            when x"4" => return "1100110";
            when x"5" => return "1101101";
            when x"6" => return "1111101";
            when x"7" => return "0000111";
            when x"8" => return "1111111";
            when x"9" => return "1101111";
            when x"A" => return "1110111";
            when x"B" => return "1111100";
            when x"C" => return "0111001";
            when x"D" => return "1011110";
            when x"E" => return "1111001";
            when others => return "1110001";                  -- F
        end case;
    end function;

begin

    s_digit <= to_integer(r_scan(SCAN_BITS-1 downto SCAN_BITS-3));

    s_segs  <= r_raw(8*s_digit+7 downto 8*s_digit) when r_ctrl = '1' else
               r_dp(s_digit) & hex7(r_hex(4*s_digit+3 downto 4*s_digit));

    -- Saídas registradas (sem glitches nos pinos) ---------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_scan  <= (others => '0');
                seg_n_o <= (others => '1');
                dp_n_o  <= '1';
                an_n_o  <= (others => '1');
            else
                r_scan  <= r_scan + 1;
                seg_n_o <= not s_segs(6 downto 0);
                dp_n_o  <= not s_segs(7);
                an_n_o  <= (others => '1');
                if r_en(s_digit) = '1' then
                    an_n_o(s_digit) <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Registradores ----------------------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_ctrl <= '0';
                r_hex  <= (others => '0');
                r_raw  <= (others => '0');
                r_dp   <= (others => '0');
                r_en   <= (others => '0');
            elsif we_i = '1' then
                case to_integer(unsigned(sel_i)) is
                    when 0 => r_ctrl <= data_i(0);
                    when 1 => r_hex  <= data_i;
                    when 2 => r_raw(31 downto 0)  <= data_i;
                    when 3 => r_raw(63 downto 32) <= data_i;
                    when 4 => r_dp   <= data_i(7 downto 0);
                    when 5 => r_en   <= data_i(7 downto 0);
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    process(sel_i, r_ctrl, r_hex, r_raw, r_dp, r_en)
    begin
        data_o <= (others => '0');
        case to_integer(unsigned(sel_i)) is
            when 0 => data_o(0) <= r_ctrl;
            when 1 => data_o <= r_hex;
            when 2 => data_o <= r_raw(31 downto 0);
            when 3 => data_o <= r_raw(63 downto 32);
            when 4 => data_o(7 downto 0) <= r_dp;
            when 5 => data_o(7 downto 0) <= r_en;
            when others => null;
        end case;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------
