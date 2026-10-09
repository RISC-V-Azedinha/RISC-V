----------------------------------------------------------------------------------
--
-- File: gpio_controller.vhd
--
--  ██████╗ ██████╗ ██╗ ██████╗
-- ██╔════╝ ██╔══██╗██║██╔═══██╗
-- ██║  ███╗██████╔╝██║██║   ██║
-- ██║   ██║██╔═══╝ ██║██║   ██║
-- ╚██████╔╝██║     ██║╚██████╔╝
--  ╚═════╝ ╚═╝     ╚═╝ ╚═════╝
--
-- Descrição : Controlador de GPIO da placa: portas no estilo de microcontrolador (Pmods, LEDs, chaves e
--             botões), displays de 7 segmentos com varredura em hardware e PWM dos LEDs RGB.
--
--             Mapa (offset a partir de 0x2000_0000):
--               0x000 Porta JA   (Pmod JA, 8 pinos, bidirecional)
--               0x040 Porta JB   (Pmod JB)
--               0x080 Porta JC   (Pmod JC)
--               0x0C0 Porta JD   (Pmod JD)
--               0x100 Porta LED  (LD0..LD15, só saída)
--               0x140 Porta SW   (SW0..SW15, só entrada, com filtro)
--               0x180 Porta BTN  (BTNU, BTND, BTNL, BTNR, só entrada, com filtro)
--               0x200 Displays de 7 segmentos (ver seg7_controller.vhd)
--               0x280 LEDs RGB (ver rgb_pwm.vhd)
--
--             Registradores de cada porta: ver gpio_port.vhd. A interrupção (PLIC fonte 4) é o OU das
--             interrupções habilitadas de todas as portas.
--
-- Autor     : [André Maiolini]
-- Data      : [31/12/2025]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Controlador de GPIO
-------------------------------------------------------------------------------------------------------------------

entity gpio_controller is
    generic (
        DEBOUNCE_CYCLES : integer := 100_000;             -- Filtro das chaves e botões (1 ms a 100 MHz)
        SEG_SCAN_BITS   : integer := 17;                  -- Varredura dos displays (~760 Hz por quadro)
        PWM_PRESCALE    : integer := 2;                   -- PWM dos LEDs RGB (~12 kHz)
        PWM_DIM         : integer := 3                    -- Brilho máximo dos LEDs RGB: 1/2^DIM (1/8)
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Interface do Barramento
        vld_i       : in  std_logic;                      -- Chip Select (Ativo quando endereço é 0x2...)
        we_i        : in  std_logic;                      -- Write Enable
        addr_i      : in  std_logic_vector( 9 downto 0);  -- Offset do endereço
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        rdy_o       : out std_logic;
        irq_o       : out std_logic;

        -- Pmods (bit i = pino i da porta: pinos 1-4 e 7-10 do conector)
        ja_i, jb_i, jc_i, jd_i         : in  std_logic_vector(7 downto 0);
        ja_o, jb_o, jc_o, jd_o         : out std_logic_vector(7 downto 0);
        ja_oe_o, jb_oe_o, jc_oe_o, jd_oe_o : out std_logic_vector(7 downto 0);

        -- LEDs, chaves e botões
        gpio_leds   : out std_logic_vector(15 downto 0);
        gpio_sw     : in  std_logic_vector(15 downto 0);
        gpio_btn    : in  std_logic_vector( 3 downto 0);  -- 0 = BTNU, 1 = BTND, 2 = BTNL, 3 = BTNR

        -- Displays de 7 segmentos
        seg_n_o     : out std_logic_vector(6 downto 0);
        dp_n_o      : out std_logic;
        an_n_o      : out std_logic_vector(7 downto 0);

        -- LEDs RGB (bit 0 = R, 1 = G, 2 = B)
        rgb0_o      : out std_logic_vector(2 downto 0);
        rgb1_o      : out std_logic_vector(2 downto 0)
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do Controlador de GPIO
-------------------------------------------------------------------------------------------------------------------

architecture rtl of gpio_controller is

    constant N_BLOCKS : integer := 9;                     -- 7 portas + displays + RGB

    type data_arr_t is array (0 to N_BLOCKS-1) of std_logic_vector(31 downto 0);

    signal s_blk     : integer range 0 to 15;
    signal s_sel     : std_logic_vector(3 downto 0);
    signal s_we      : std_logic_vector(N_BLOCKS-1 downto 0);
    signal s_rdata   : data_arr_t;
    signal s_irq     : std_logic_vector(6 downto 0);

    signal s_led_dummy_in : std_logic_vector(15 downto 0) := (others => '0');
    signal s_sw_o, s_sw_oe, s_led_oe : std_logic_vector(15 downto 0);
    signal s_btn_o, s_btn_oe         : std_logic_vector(3 downto 0);

    signal r_rdy  : std_logic := '0';

begin

    -- Decodificação: bloco = addr[9:6] (64 bytes cada), registrador = addr[5:2] --------------------------------
    s_blk <= to_integer(unsigned(addr_i(9 downto 6)));
    s_sel <= addr_i(5 downto 2);

    process(s_blk, vld_i, we_i, r_rdy)
    begin
        s_we <= (others => '0');
        if vld_i = '1' and we_i = '1' and r_rdy = '0' then
            case s_blk is
                when 0 to 6 => s_we(s_blk) <= '1';
                when 8      => s_we(7)     <= '1';         -- 0x200: displays
                when 10     => s_we(8)     <= '1';         -- 0x280: RGB
                when others => null;
            end case;
        end if;
    end process;

    -- Portas -----------------------------------------------------------------------------------------------------
    U_JA: entity work.gpio_port generic map (WIDTH => 8, MODE => 0)
        port map (clk, rst, s_we(0), s_sel, data_i, s_rdata(0), ja_i, ja_o, ja_oe_o, s_irq(0));
    U_JB: entity work.gpio_port generic map (WIDTH => 8, MODE => 0)
        port map (clk, rst, s_we(1), s_sel, data_i, s_rdata(1), jb_i, jb_o, jb_oe_o, s_irq(1));
    U_JC: entity work.gpio_port generic map (WIDTH => 8, MODE => 0)
        port map (clk, rst, s_we(2), s_sel, data_i, s_rdata(2), jc_i, jc_o, jc_oe_o, s_irq(2));
    U_JD: entity work.gpio_port generic map (WIDTH => 8, MODE => 0)
        port map (clk, rst, s_we(3), s_sel, data_i, s_rdata(3), jd_i, jd_o, jd_oe_o, s_irq(3));

    U_LED: entity work.gpio_port generic map (WIDTH => 16, MODE => 1)
        port map (clk, rst, s_we(4), s_sel, data_i, s_rdata(4), s_led_dummy_in, gpio_leds, s_led_oe, s_irq(4));
    U_SW: entity work.gpio_port generic map (WIDTH => 16, MODE => 2, DEBOUNCE => DEBOUNCE_CYCLES)
        port map (clk, rst, s_we(5), s_sel, data_i, s_rdata(5), gpio_sw, s_sw_o, s_sw_oe, s_irq(5));
    U_BTN: entity work.gpio_port generic map (WIDTH => 4, MODE => 2, DEBOUNCE => DEBOUNCE_CYCLES)
        port map (clk, rst, s_we(6), s_sel, data_i, s_rdata(6), gpio_btn, s_btn_o, s_btn_oe, s_irq(6));

    -- Displays de 7 segmentos e LEDs RGB -------------------------------------------------------------------------
    U_SEG: entity work.seg7_controller generic map (SCAN_BITS => SEG_SCAN_BITS)
        port map (clk, rst, s_we(7), s_sel, data_i, s_rdata(7), seg_n_o, dp_n_o, an_n_o);
    U_RGB: entity work.rgb_pwm generic map (PRESCALE => PWM_PRESCALE, DIM => PWM_DIM)
        port map (clk, rst, s_we(8), s_sel, data_i, s_rdata(8), rgb0_o, rgb1_o);

    irq_o <= '1' when s_irq /= "0000000" else '0';
    rdy_o <= r_rdy;

    -- Handshake e leitura (latência 1) ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_rdy  <= '0';
                data_o <= (others => '0');
            else
                -- Default: Ready baixa no ciclo seguinte garantindo pulso de 1 clock
                r_rdy  <= '0';
                data_o <= (others => '0');

                -- EDGE GUARD: Só aceita transação se o vld estiver alto e AINDA não tivermos respondido
                if vld_i = '1' and r_rdy = '0' then
                    r_rdy <= '1';
                    if we_i = '0' then
                        case s_blk is
                            when 0 to 6 => data_o <= s_rdata(s_blk);
                            when 8      => data_o <= s_rdata(7);
                            when 10     => data_o <= s_rdata(8);
                            when others => null;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------
