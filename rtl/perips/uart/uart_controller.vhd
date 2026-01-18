------------------------------------------------------------------------------------------------------------------
-- 
-- File: uart_controller.vhd
-- 
-- ██╗   ██╗ █████╗ ██████╗ ████████╗
-- ██║   ██║██╔══██╗██╔══██╗╚══██╔══╝
-- ██║   ██║███████║██████╔╝   ██║   
-- ██║   ██║██╔══██║██╔══██╗   ██║   
-- ╚██████╔╝██║  ██║██║  ██║   ██║   
--  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
-- 
-- Descrição : Módulo Controlador UART (TX + RX)
-- 
-- Autor     : [André Maiolini]
-- Data      : [01/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Controlador UART
-------------------------------------------------------------------------------------------------------------------

entity uart_controller is
    generic (
        CLK_FREQ    : integer := 100_000_000;                -- Configurado para 100 MHz
        BAUD_RATE   : integer := 115_200;                    -- 115200 bps
        FIFO_DEPTH  : integer := 64                          -- Buffer para 64 caracteres
    );
    port (

        -- Sinais de controle (sincronismo)

        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Interface de Barramento

        vld_i       : in  std_logic; 
        we_i        : in  std_logic;                         -- 1=Write, 0=Read
        addr_i      : in  std_logic_vector( 3 downto 0);     -- Apenas o Offset (0x0, 0x4...)
        data_i      : in  std_logic_vector(31 downto 0);     -- Dado vindo da CPU
        data_o      : out std_logic_vector(31 downto 0);     -- Dado indo para CPU
        rdy_o       : out std_logic;

        -- Pinos Físicos

        uart_tx_pin : out std_logic;
        uart_rx_pin : in  std_logic
    
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Implementação comportamental da interface do Controlador UART
-------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------
-- MAPA DE REGISTRADORES (Memory Map)
-------------------------------------------------------------------------------------------------------------------
--
-- 0x00: DATA REGISTER (R/W)
--
--       [31:8] Ignorado
--       [7:0]  Dados (Byte)
--
--       -> WRITE (TX): Escreve um byte no buffer de transmissão. 
--                      A transmissão inicia automaticamente se TX_BUSY = '0'.
--                      Requisito: Verificar TX_BUSY antes de escrever.
--
--       -> READ  (RX): Lê o byte atual na saída da FIFO (Head of Queue).
--                      IMPORTANTE: A leitura NÃO remove o dado da FIFO (Operação Peek).
--                      Para avançar para o próximo byte, use o Command Register.
-- 
-- 0x04: STATUS & CONTROL REGISTER (R/W)
--       
--       -> READ (Status Flags):
--            Bit 0: TX_BUSY (1 = Transmissor ocupado, 0 = Livre/Pronto)
--            Bit 1: RX_VALID (1 = FIFO tem dados, 0 = FIFO vazia)
--            Bit 31-2: Reservado (0)
--
--       -> WRITE (Commands):
--            Bit 0: RX_POP / ACK (Escrever '1' remove o byte lido da FIFO)
--            Bit 31-1: Ignorado
--
-------------------------------------------------------------------------------------------------------------------
-- FLUXO DE OPERAÇÃO SUGERIDO (DRIVER)
-------------------------------------------------------------------------------------------------------------------
--
-- 1. TRANSMISSÃO (TX):
--    a. Ler endereço 0x04 e verificar Bit 0 (TX_BUSY).
--    b. Se '0', escrever char no endereço 0x00. Se '1', aguardar.
--
-- 2. RECEPÇÃO (RX):
--    a. Ler endereço 0x04 e verificar Bit 1 (RX_VALID).
--    b. Se '1', ler dado do endereço 0x00 (Armazenar em variável).
--    c. Escrever '1' no endereço 0x04 (Bit 0) para descartar o dado lido e avançar a fila.
--
-------------------------------------------------------------------------------------------------------------------

architecture rtl of uart_controller is

    -- Cálculo do período de um bit em ciclos de clock

    constant c_bit_period : integer := CLK_FREQ / BAUD_RATE;
    
    -- DEFINIÇÃO DA FIFO (Buffer First-In First-Out)

    type t_fifo_mem is array (0 to FIFO_DEPTH-1) of std_logic_vector(7 downto 0);

    signal r_fifo         : t_fifo_mem;                      -- Memória da FIFO
    signal r_head         : integer range 0 to FIFO_DEPTH-1; -- Onde RX escreve
    signal r_tail         : integer range 0 to FIFO_DEPTH-1; -- Onde CPU lê
    signal r_count        : integer range 0 to FIFO_DEPTH;   -- Quantos itens tem
    
    signal w_fifo_full    : std_logic;                       -- Flag de FIFO cheia
    signal w_fifo_empty   : std_logic;                       -- Flag de FIFO vazia
    signal w_wr_en        : std_logic;                       -- Enable de escrita na FIFO (pelo RX)
    signal w_rd_en        : std_logic;                       -- Enable de leitura na FIFO (pelo CPU)

    -- Sinais TX

    type t_tx_state is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state       : t_tx_state;
    signal tx_timer       : integer range 0 to c_bit_period;
    signal tx_bit_idx     : integer range 0 to 7;
    signal tx_shifter     : std_logic_vector(7 downto 0);
    signal tx_busy_flag   : std_logic;
    signal tx_start_pulse : std_logic;
    signal r_tx_data_latch: std_logic_vector(7 downto 0);

    -- Sinais RX

    type t_rx_state is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state       : t_rx_state;
    signal rx_timer       : integer range 0 to c_bit_period;
    signal rx_bit_idx     : integer range 0 to 7;
    signal rx_shifter     : std_logic_vector(7 downto 0);
    signal rx_pin_sync    : std_logic_vector(1 downto 0);
    signal rx_bit_val     : std_logic;

begin

    -- Status da FIFO ---------------------------------------------------------------------------------------------

    w_fifo_full  <= '1' when r_count = FIFO_DEPTH else '0';
    w_fifo_empty <= '1' when r_count = 0 else '0';

    -- Sincronizador RX -------------------------------------------------------------------------------------------

    rx_bit_val <= rx_pin_sync(1);
    process(clk)
    begin
        if rising_edge(clk) then
            rx_pin_sync <= rx_pin_sync(0) & uart_rx_pin;
        end if;
    end process;

    -- Gerenciamento da FIFO --------------------------------------------------------------------------------------

    process(clk)
    begin

        if rising_edge(clk) then

            if rst = '1' then
                r_head  <= 0;
                r_tail  <= 0;
                r_count <= 0;
            else

                -- ESCRITA (RX Hardware inserindo dados)
                if w_wr_en = '1' and w_fifo_full = '0' then
                    r_fifo(r_head) <= rx_shifter; -- Grava o byte que acabou de chegar
                    if r_head = FIFO_DEPTH - 1 then
                        r_head <= 0;
                    else
                        r_head <= r_head + 1;
                    end if;
                end if;

                -- LEITURA (CPU removendo dados via comando)
                if w_rd_en = '1' and w_fifo_empty = '0' then
                    if r_tail = FIFO_DEPTH - 1 then
                        r_tail <= 0;
                    else
                        r_tail <= r_tail + 1;
                    end if;
                end if;

                -- CONTADOR DE ITENS
                if w_wr_en = '1' and w_rd_en = '0' and w_fifo_full = '0' then
                    r_count <= r_count + 1;
                elsif w_wr_en = '0' and w_rd_en = '1' and w_fifo_empty = '0' then
                    r_count <= r_count - 1;
                end if;
                -- Se ambos acontecem ao mesmo tempo, count não muda
            end if;
        end if;

    end process;

    -- 1. TX STATE MACHINE ----------------------------------------------------------------------------------------

    process(clk)
    begin

        if rising_edge(clk) then
            if rst = '1' then
                tx_state <= TX_IDLE;
                uart_tx_pin <= '1';
                tx_busy_flag <= '0';
                tx_timer <= 0;
                tx_bit_idx <= 0;
                tx_shifter <= (others => '0');
            else
                case tx_state is
                    when TX_IDLE =>
                        uart_tx_pin <= '1';
                        if tx_start_pulse = '1' then
                            tx_shifter   <= r_tx_data_latch;
                            tx_state     <= TX_START;
                            tx_busy_flag <= '1';
                        else
                            tx_busy_flag <= '0';
                        end if;
                        tx_timer <= 0;

                    when TX_START =>
                        uart_tx_pin <= '0';
                        tx_busy_flag <= '1';
                        if tx_timer < c_bit_period - 1 then
                            tx_timer <= tx_timer + 1;
                        else
                            tx_timer <= 0;
                            tx_state <= TX_DATA;
                            tx_bit_idx <= 0;
                        end if;

                    when TX_DATA =>
                        uart_tx_pin <= tx_shifter(tx_bit_idx);
                        if tx_timer < c_bit_period - 1 then
                            tx_timer <= tx_timer + 1;
                        else
                            tx_timer <= 0;
                            if tx_bit_idx < 7 then
                                tx_bit_idx <= tx_bit_idx + 1;
                            else
                                tx_state <= TX_STOP;
                            end if;
                        end if;

                    when TX_STOP =>
                        uart_tx_pin <= '1';
                        if tx_timer < c_bit_period - 1 then
                            tx_timer <= tx_timer + 1;
                        else
                            tx_state <= TX_IDLE;
                        end if;
                end case;
            end if;
        end if;

    end process;

    -- 2. RX STATE MACHINE ----------------------------------------------------------------------------------------

    process(clk)
    begin

        if rising_edge(clk) then
            if rst = '1' then
                rx_state <= RX_IDLE;
                rx_timer <= 0;
                rx_bit_idx <= 0;
                rx_shifter <= (others => '0');
                w_wr_en    <= '0';
            else
                w_wr_en <= '0';

                case rx_state is
                    when RX_IDLE =>
                        rx_timer <= 0;
                        rx_bit_idx <= 0;
                        if rx_bit_val = '0' then rx_state <= RX_START; end if;

                    when RX_START =>
                        if rx_timer < (c_bit_period / 2) - 1 then
                            rx_timer <= rx_timer + 1;
                        else
                            rx_timer <= 0;
                            if rx_bit_val = '0' then rx_state <= RX_DATA;
                            else rx_state <= RX_IDLE; end if;
                        end if;

                    when RX_DATA =>
                        if rx_timer < c_bit_period - 1 then
                            rx_timer <= rx_timer + 1;
                        else
                            rx_timer <= 0;
                            rx_shifter(rx_bit_idx) <= rx_bit_val;
                            if rx_bit_idx < 7 then rx_bit_idx <= rx_bit_idx + 1;
                            else rx_state <= RX_STOP; end if;
                        end if;

                    when RX_STOP =>
                        if rx_timer < c_bit_period - 1 then
                            rx_timer <= rx_timer + 1;
                        else
                            -- SUCESSO! Manda escrever na FIFO
                            w_wr_en  <= '1'; 
                            rx_state <= RX_IDLE;
                        end if;
                end case;
            end if;
        end if;

    end process;

    -- 3. INTERFACE DE CONTROLE -----------------------------------------------------------------------------------

    process(clk)
    begin

        if rising_edge(clk) then
            if rst = '1' then
                rdy_o           <= '0';
                data_o          <= (others => '0');
                tx_start_pulse  <= '0';
                w_rd_en         <= '0';
                r_tx_data_latch <= (others => '0');
            else
                
                -- Defaults (Pulsos de 1 ciclo e limpeza de barramento)
                rdy_o           <= '0';
                tx_start_pulse  <= '0';
                w_rd_en         <= '0';
                data_o          <= (others => '0'); 

                -- Se há uma requisição válida do Mestre
                if vld_i = '1' then
                    
                    -- Handshake: Resposta no ciclo T+1
                    rdy_o <= '1'; 

                    -- LOGICA DE ESCRITA (CPU -> Periférico)
                    if we_i = '1' then
                        if unsigned(addr_i) = 0 then
                            -- Transmitir (TX)
                            if tx_busy_flag = '0' then
                                tx_start_pulse  <= '1';
                                r_tx_data_latch <= data_i(7 downto 0); -- Latch do dado
                            end if;
                        
                        elsif unsigned(addr_i) = 4 then
                            -- Comando de Controle: Avançar FIFO (Pop)
                            if data_i(0) = '1' then
                                w_rd_en <= '1';      -- Move o ponteiro 'tail'
                            end if;
                        end if;

                    -- LOGICA DE LEITURA (Periférico -> CPU)
                    else
                        case to_integer(unsigned(addr_i)) is
                            when 0 => 
                                -- Lê o dado que está na ponta da FIFO (Tail)
                                data_o(7 downto 0) <= r_fifo(r_tail);
                            when 4 => 
                                -- Status Register
                                data_o(0) <= tx_busy_flag;
                                data_o(1) <= not w_fifo_empty; 
                            when others => null;
                        end case;
                    end if;
                end if;
            end if;
        end if;

    end process;

    ---------------------------------------------------------------------------------------------------------------

end architecture; -- rtl 

------------------------------------------------------------------------------------------------------------------