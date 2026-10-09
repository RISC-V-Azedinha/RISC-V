------------------------------------------------------------------------------------------------------------------
--
-- File: gpio_port.vhd
--
-- Descrição : Porta de GPIO no estilo de microcontrolador (direção + pino), com interrupção por borda.
--
--             Registradores (offset dentro da porta, palavras de 32 bits):
--               0x00 IN     (RO) estado dos pinos (sincronizado; com filtro nas portas de botões/chaves)
--               0x04 OUT    (RW) valor de saída
--               0x08 DIR    (RW) direção por pino: 1 = saída, 0 = entrada
--               0x0C OUTSET (WO) OUT <= OUT or  valor  (liga os pinos marcados)
--               0x10 OUTCLR (WO) OUT <= OUT and not valor (desliga os pinos marcados)
--               0x14 OUTTGL (WO) OUT <= OUT xor valor  (inverte os pinos marcados)
--               0x18 IE     (RW) habilita a interrupção de cada pino
--               0x1C IES    (RW) borda que dispara: 0 = subida, 1 = descida
--               0x20 IFG    (RW) flags de interrupção (setadas pela borda, mesmo com IE = 0); escrever 1 limpa
--
--             MODE: 0 = bidirecional (Pmod), 1 = só saída (LEDs: DIR fixo em 1, IN lê OUT),
--                   2 = só entrada (chaves e botões: DIR fixo em 0, OUT sem efeito nos pinos).
--
-- Autor     : [André Maiolini]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpio_port is
    generic (
        WIDTH    : integer := 8;
        MODE     : integer := 0;                              -- 0 = inout, 1 = out, 2 = in
        DEBOUNCE : integer := 0                               -- Ciclos entre amostras do filtro (0 = sem filtro)
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        -- Acesso aos registradores (decodificado pelo gpio_controller)
        we_i     : in  std_logic;
        sel_i    : in  std_logic_vector(3 downto 0);          -- Índice do registrador (offset / 4)
        data_i   : in  std_logic_vector(31 downto 0);
        data_o   : out std_logic_vector(31 downto 0);

        -- Pinos
        pin_i    : in  std_logic_vector(WIDTH-1 downto 0);
        pin_o    : out std_logic_vector(WIDTH-1 downto 0);
        pin_oe_o : out std_logic_vector(WIDTH-1 downto 0);    -- 1 = pino dirigido pela porta

        irq_o    : out std_logic
    );
end entity;

architecture rtl of gpio_port is

    constant C_ONES  : std_logic_vector(WIDTH-1 downto 0) := (others => '1');
    constant C_ZEROS : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

    signal r_out, r_dir, r_ie, r_ies, r_ifg : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal r_sync1, r_sync2                 : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal r_sample, r_in, r_in_prev        : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal s_dir, s_in, s_edge              : std_logic_vector(WIDTH-1 downto 0);
    signal r_tick_cnt                       : integer range 0 to DEBOUNCE := 0;

begin

    -- Direção efetiva (fixa nas portas só de saída ou só de entrada) -------------------------------------------
    s_dir    <= C_ONES when MODE = 1 else C_ZEROS when MODE = 2 else r_dir;
    pin_o    <= r_out;
    pin_oe_o <= s_dir;

    -- Valor lido: numa porta só de saída, os pinos não voltam para o FPGA
    s_in     <= r_out when MODE = 1 else r_in;

    -- Bordas (com a polaridade escolhida em IES) -----------------------------------------------------------------
    s_edge   <= ((s_in and not r_in_prev) and not r_ies) or ((not s_in and r_in_prev) and r_ies);

    irq_o    <= '1' when (r_ifg and r_ie) /= C_ZEROS else '0';

    -- Sincronização e filtro dos pinos ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_sync1    <= (others => '0');
                r_sync2    <= (others => '0');
                r_sample   <= (others => '0');
                r_in       <= (others => '0');
                r_tick_cnt <= 0;
            else
                r_sync1 <= pin_i;
                r_sync2 <= r_sync1;
                if DEBOUNCE = 0 then
                    r_in <= r_sync2;
                elsif r_tick_cnt = DEBOUNCE - 1 then
                    -- Um pino só muda quando duas amostras seguidas concordam (ignora o repique)
                    r_tick_cnt <= 0;
                    r_sample   <= r_sync2;
                    for i in 0 to WIDTH-1 loop
                        if r_sync2(i) = r_sample(i) then
                            r_in(i) <= r_sync2(i);
                        end if;
                    end loop;
                else
                    r_tick_cnt <= r_tick_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- Registradores ----------------------------------------------------------------------------------------------
    process(clk)
        variable v_clr : std_logic_vector(WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_out     <= (others => '0');
                r_dir     <= (others => '0');
                r_ie      <= (others => '0');
                r_ies     <= (others => '0');
                r_ifg     <= (others => '0');
                r_in_prev <= (others => '0');
            else
                r_in_prev <= s_in;
                v_clr     := (others => '0');

                if we_i = '1' then
                    case to_integer(unsigned(sel_i)) is
                        when 1 => r_out <= data_i(WIDTH-1 downto 0);
                        when 2 => r_dir <= data_i(WIDTH-1 downto 0);
                        when 3 => r_out <= r_out or data_i(WIDTH-1 downto 0);
                        when 4 => r_out <= r_out and not data_i(WIDTH-1 downto 0);
                        when 5 => r_out <= r_out xor data_i(WIDTH-1 downto 0);
                        when 6 => r_ie  <= data_i(WIDTH-1 downto 0);
                        when 7 => r_ies <= data_i(WIDTH-1 downto 0);
                        when 8 => v_clr := data_i(WIDTH-1 downto 0);
                        when others => null;
                    end case;
                end if;

                -- Uma borda no mesmo ciclo da limpeza prevalece (não se perde o evento)
                r_ifg <= (r_ifg and not v_clr) or s_edge;
            end if;
        end if;
    end process;

    -- Leitura (combinacional; o gpio_controller registra) ------------------------------------------------------
    process(sel_i, s_in, r_out, s_dir, r_ie, r_ies, r_ifg)
    begin
        data_o <= (others => '0');
        case to_integer(unsigned(sel_i)) is
            when 0 => data_o(WIDTH-1 downto 0) <= s_in;
            when 1 => data_o(WIDTH-1 downto 0) <= r_out;
            when 2 => data_o(WIDTH-1 downto 0) <= s_dir;
            when 6 => data_o(WIDTH-1 downto 0) <= r_ie;
            when 7 => data_o(WIDTH-1 downto 0) <= r_ies;
            when 8 => data_o(WIDTH-1 downto 0) <= r_ifg;
            when others => null;
        end case;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------
