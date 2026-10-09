------------------------------------------------------------------------------------------------------------------
--
-- File: sd_spi.vhd
--
-- Descrição : Mestre SPI para o slot de microSD da placa (modo SPI do cartão, SPI modo 0).
--
--             O controlador só transfere bytes: a CPU escreve um byte em DATA, espera BUSY baixar e lê o byte
--             que o cartão devolveu. Os comandos do cartão (CMD0, CMD17, ...) ficam no software.
--
--             Registradores (offset):
--               0x00 DATA   (RW) escrita: envia o byte (ignorada com BUSY = 1); leitura: último byte recebido
--               0x04 CTRL   (RW) bit 0 CS: 1 = cartão selecionado (pino CS em nível baixo)
--                                bit 1 PWR: 1 = cartão alimentado (SD_RESET em nível baixo)
--               0x08 DIV    (RW) meio período do SCK em ciclos de clock, menos 1: f_SCK = f_clk / (2 (DIV + 1))
--                                (após o reset: 124, ou seja, 400 kHz a 100 MHz, a velocidade da inicialização;
--                                mínimo 1, porque o MISO passa por um registrador antes de ser amostrado)
--               0x0C STATUS (RO) bit 0 BUSY: transferência em curso; bit 1 CD: cartão presente no slot
--
-- Autor     : [André Maiolini]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_spi is
    generic (
        DIV_RESET : integer := 124                            -- 400 kHz a 100 MHz
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;

        -- Barramento
        vld_i      : in  std_logic;
        we_i       : in  std_logic;
        addr_i     : in  std_logic_vector(3 downto 0);
        data_i     : in  std_logic_vector(31 downto 0);
        data_o     : out std_logic_vector(31 downto 0);
        rdy_o      : out std_logic;

        -- Cartão
        sd_sck_o   : out std_logic;
        sd_mosi_o  : out std_logic;                           -- SD_CMD
        sd_miso_i  : in  std_logic;                           -- SD_DAT0
        sd_cs_n_o  : out std_logic;                           -- SD_DAT3
        sd_reset_o : out std_logic;                           -- 1 = cartão sem alimentação
        sd_cd_n_i  : in  std_logic                            -- 0 = cartão no slot
    );
end entity;

architecture rtl of sd_spi is

    signal r_div     : unsigned(7 downto 0) := to_unsigned(DIV_RESET, 8);
    signal r_cs      : std_logic := '0';
    signal r_pwr     : std_logic := '0';

    signal r_busy    : std_logic := '0';
    signal r_sck     : std_logic := '0';
    signal r_cnt     : unsigned(7 downto 0) := (others => '0');
    signal r_bits    : integer range 0 to 7 := 0;
    signal r_tx      : std_logic_vector(7 downto 0) := (others => '1');
    signal r_rx      : std_logic_vector(7 downto 0) := (others => '1');

    signal r_miso           : std_logic := '1';
    signal r_cd1, r_cd2     : std_logic := '1';

    signal r_rdy     : std_logic := '0';

begin

    sd_sck_o   <= r_sck;
    sd_mosi_o  <= r_tx(7);                                    -- MSB primeiro
    sd_cs_n_o  <= not r_cs;
    sd_reset_o <= not r_pwr;

    rdy_o      <= r_rdy;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_div   <= to_unsigned(DIV_RESET, 8);
                r_cs    <= '0';
                r_pwr   <= '0';
                r_busy  <= '0';
                r_sck   <= '0';
                r_cnt   <= (others => '0');
                r_bits  <= 0;
                r_tx    <= (others => '1');
                r_rx    <= (others => '1');
                r_rdy   <= '0';
                data_o  <= (others => '0');
                r_miso  <= '1';
                r_cd1   <= '1';
                r_cd2   <= '1';
            else
                r_miso  <= sd_miso_i;                          -- O dado do cartão já é síncrono ao SCK
                r_cd1   <= sd_cd_n_i;
                r_cd2   <= r_cd1;

                -- Transferência de um byte (SPI modo 0: o cartão amostra na subida, muda o dado na descida) -----
                if r_busy = '1' then
                    if r_cnt = r_div then
                        r_cnt <= (others => '0');
                        r_sck <= not r_sck;
                        if r_sck = '0' then
                            r_rx <= r_rx(6 downto 0) & r_miso;        -- subida: amostra o bit do cartão
                        else
                            r_tx <= r_tx(6 downto 0) & '1';           -- descida: próximo bit (MOSI em 1 no fim)
                            if r_bits = 7 then
                                r_busy <= '0';
                                r_bits <= 0;
                            else
                                r_bits <= r_bits + 1;
                            end if;
                        end if;
                    else
                        r_cnt <= r_cnt + 1;
                    end if;
                end if;

                -- Barramento (latência 1, mesmo handshake dos outros periféricos) --------------------------------
                r_rdy  <= '0';
                data_o <= (others => '0');

                if vld_i = '1' and r_rdy = '0' then
                    r_rdy <= '1';
                    if we_i = '1' then
                        case addr_i(3 downto 2) is
                            when "00" =>
                                if r_busy = '0' then
                                    r_tx   <= data_i(7 downto 0);
                                    r_busy <= '1';
                                    r_cnt  <= (others => '0');
                                end if;
                            when "01" =>
                                r_cs  <= data_i(0);
                                r_pwr <= data_i(1);
                            when "10" =>
                                r_div <= unsigned(data_i(7 downto 0));
                            when others => null;
                        end case;
                    else
                        case addr_i(3 downto 2) is
                            when "00"   => data_o(7 downto 0) <= r_rx;
                            when "01"   => data_o(1 downto 0) <= r_pwr & r_cs;
                            when "10"   => data_o(7 downto 0) <= std_logic_vector(r_div);
                            when others => data_o(1 downto 0) <= (not r_cd2) & r_busy;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------
