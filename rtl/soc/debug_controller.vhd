------------------------------------------------------------------------------------------------------------------
-- File: debug_controller.vhd
-- 
-- ██████╗ ███████╗██████╗ ██╗   ██╗ ██████╗ 
-- ██╔══██╗██╔════╝██╔══██╗██║   ██║██╔════╝ 
-- ██║  ██║█████╗  ██████╔╝██║   ██║██║  ███╗
-- ██║  ██║██╔══╝  ██╔══██╗██║   ██║██║   ██║
-- ██████╔╝███████╗██████╔╝╚██████╔╝╚██████╔╝
-- ╚═════╝ ╚══════╝╚═════╝  ╚═════╝  ╚═════╝ 
--     
-- Descrição : Controlador de Debug Out-of-Band (Multiplexado).
--      Possui TX/RX independentes. Controlado pela multiplexação de RTS.
--
-- Autor     : [André Maiolini]
-- Data      : [27/02/2026]
-- 
------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do controlador de debug
-------------------------------------------------------------------------------------------------------------------

entity debug_controller is

    generic (

        CLK_FREQ    : integer := 100_000_000;
        BAUD_RATE   : integer := 115_200

    );

    port (

        -- Sinais de Controle e Sincronismo Global
        clk_i            : in  std_logic;
        rst_i            : in  std_logic;
        
        -- Interface Física UART (Isolada via soc_top)
        uart_rx_i        : in  std_logic;
        uart_tx_o        : out std_logic;
        uart_rts_i       : in  std_logic;
        
        -- Controle de Estado da CPU
        is_fetch_stage_i : in  std_logic;
        soc_en_o         : out std_logic;
        debug_rst_o      : out std_logic;
        
        -- Interface de Leitura de Registradores (Ligar na porta dedicada do reg_file)
        reg_addr_o       : out std_logic_vector(4 downto 0);
        reg_data_i       : in  std_logic_vector(31 downto 0);
        pc_i             : in  std_logic_vector(31 downto 0) 

    );
    
end entity debug_controller;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do controlador de debug
-------------------------------------------------------------------------------------------------------------------

architecture rtl of debug_controller is

    constant c_BIT_PERIOD : integer := CLK_FREQ / BAUD_RATE;
    
    -- Opcodes do Protocolo

    constant CMD_HALT     : std_logic_vector(7 downto 0) := x"01";
    constant CMD_RESUME   : std_logic_vector(7 downto 0) := x"02";
    constant CMD_STEP     : std_logic_vector(7 downto 0) := x"03";
    constant CMD_RESET    : std_logic_vector(7 downto 0) := x"04";
    constant CMD_SET_BKP  : std_logic_vector(7 downto 0) := x"05";
    constant CMD_CLR_BKP  : std_logic_vector(7 downto 0) := x"06";
    constant CMD_READ_REG : std_logic_vector(7 downto 0) := x"10";

    -- ========================================================================
    -- Sinais do Controlador-RX
    -- ========================================================================

    type t_rx_state is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state   : t_rx_state;
    signal rx_timer   : integer range 0 to c_BIT_PERIOD;
    signal rx_bit_idx : integer range 0 to 7;
    signal rx_shifter : std_logic_vector(7 downto 0);
    signal rx_sync    : std_logic_vector(1 downto 0);
    
    signal s_rx_data  : std_logic_vector(7 downto 0);
    signal s_rx_valid : std_logic;

    -- ========================================================================
    -- Sinais do Controlador-TX
    -- ========================================================================

    type t_tx_state is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state       : t_tx_state;
    signal tx_timer       : integer range 0 to c_BIT_PERIOD;
    signal tx_bit_idx     : integer range 0 to 7;
    signal tx_shifter     : std_logic_vector(7 downto 0);
    
    signal r_tx_start     : std_logic;
    signal r_tx_data      : std_logic_vector(7 downto 0);
    signal s_tx_busy      : std_logic;

    -- ========================================================================
    -- Sinais da FSM Principal (Interlock)
    -- ========================================================================

    type t_dbg_state is (
        IDLE, WAIT_FE, WAIT_BA, WAIT_BE, 
        ARMED_WAIT_FETCH, DEBUG_ACTIVE, STEP_EXEC, STEP_FETCH,
        DUMP_REGS, APPLY_RESET,
        BKP_B0, BKP_B1, BKP_B2, BKP_B3
    );
    signal dbg_state : t_dbg_state;
    
    -- Contadores para o dump de registradores (32 regs * 4 bytes)

    signal reg_idx  : integer range 0 to 32;
    signal byte_idx : integer range 0 to 3;

    signal s_mux_reg_data : std_logic_vector(31 downto 0);

    -- Sinais do Hardware Breakpoint
    
    signal r_bkp_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal r_bkp_en   : std_logic := '0';
    signal r_bkp_hit  : std_logic := '0';

begin

    -- Sincronizador RX

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            rx_sync <= rx_sync(0) & uart_rx_i;
        end if;
    end process;

    -- ========================================================================
    -- RX MACHINE
    -- ========================================================================

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                rx_state <= RX_IDLE;
                s_rx_valid <= '0';
            else
                s_rx_valid <= '0';
                case rx_state is
                    when RX_IDLE =>
                        rx_timer <= 0;
                        if rx_sync(1) = '0' then rx_state <= RX_START; end if;
                    when RX_START =>
                        if rx_timer < (c_BIT_PERIOD / 2) - 1 then rx_timer <= rx_timer + 1;
                        else
                            rx_timer <= 0;
                            if rx_sync(1) = '0' then rx_state <= RX_DATA; rx_bit_idx <= 0;
                            else rx_state <= RX_IDLE; end if;
                        end if;
                    when RX_DATA =>
                        if rx_timer < c_BIT_PERIOD - 1 then rx_timer <= rx_timer + 1;
                        else
                            rx_timer <= 0;
                            rx_shifter(rx_bit_idx) <= rx_sync(1);
                            if rx_bit_idx < 7 then rx_bit_idx <= rx_bit_idx + 1;
                            else rx_state <= RX_STOP; end if;
                        end if;
                    when RX_STOP =>
                        if rx_timer < c_BIT_PERIOD - 1 then rx_timer <= rx_timer + 1;
                        else
                            s_rx_data  <= rx_shifter;
                            s_rx_valid <= '1';
                            rx_state   <= RX_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- TX MACHINE
    -- ========================================================================

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                tx_state <= TX_IDLE;
                uart_tx_o <= '1';
                s_tx_busy <= '0';
            else
                case tx_state is
                    when TX_IDLE =>
                        uart_tx_o <= '1';
                        if r_tx_start = '1' then
                            tx_shifter <= r_tx_data;
                            tx_state   <= TX_START;
                            s_tx_busy  <= '1';
                            tx_timer   <= 0;
                        else
                            s_tx_busy <= '0';
                        end if;
                    when TX_START =>
                        uart_tx_o <= '0';
                        if tx_timer < c_BIT_PERIOD - 1 then tx_timer <= tx_timer + 1;
                        else tx_timer <= 0; tx_state <= TX_DATA; tx_bit_idx <= 0; end if;
                    when TX_DATA =>
                        uart_tx_o <= tx_shifter(tx_bit_idx);
                        if tx_timer < c_BIT_PERIOD - 1 then tx_timer <= tx_timer + 1;
                        else
                            tx_timer <= 0;
                            if tx_bit_idx < 7 then tx_bit_idx <= tx_bit_idx + 1;
                            else tx_state <= TX_STOP; end if;
                        end if;
                    when TX_STOP =>
                        uart_tx_o <= '1';
                        if tx_timer < c_BIT_PERIOD - 1 then tx_timer <= tx_timer + 1;
                        else tx_state <= TX_IDLE; end if;
                end case;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- HARDWARE BREAKPOINT MONITOR
    -- ========================================================================

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                r_bkp_hit <= '0';
            else
                -- Limpa o gatilho quando o debugger mandar retomar, dar step ou resetar
                if (dbg_state = DEBUG_ACTIVE and s_rx_valid = '1' and 
                   (s_rx_data = CMD_RESUME or s_rx_data = CMD_STEP or s_rx_data = CMD_RESET)) then
                    r_bkp_hit <= '0';
                
                -- Se estiver armado e o PC bater com o endereço alvo, puxa o freio de mão!
                elsif r_bkp_en = '1' and pc_i = r_bkp_addr and is_fetch_stage_i = '1' then
                    r_bkp_hit <= '1';
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- MAIN DEBUG FSM
    -- ========================================================================
    
    reg_addr_o <= std_logic_vector(to_unsigned(reg_idx, 5)) when reg_idx < 32 else "00000";
    s_mux_reg_data <= pc_i when reg_idx = 32 else reg_data_i;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                dbg_state   <= IDLE;
                soc_en_o    <= '1';
                debug_rst_o <= '0';
                r_tx_start  <= '0';
            else
                r_tx_start  <= '0';
                debug_rst_o <= '0'; -- Pulso padrao de 1 ciclo

                if uart_rts_i = '0' then
                    dbg_state <= IDLE;
                    soc_en_o  <= not r_bkp_hit;
                else
                    case dbg_state is
                        
                        -- HANDSHAKE (CAFEBABE)
                        when IDLE =>
                            soc_en_o <= not r_bkp_hit;
                            if s_rx_valid = '1' and s_rx_data = x"CA" then dbg_state <= WAIT_FE; end if;
                        when WAIT_FE =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"FE" then dbg_state <= WAIT_BA; else dbg_state <= IDLE; end if;
                            end if;
                        when WAIT_BA =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"BA" then dbg_state <= WAIT_BE; else dbg_state <= IDLE; end if;
                            end if;
                        when WAIT_BE =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"BE" then dbg_state <= ARMED_WAIT_FETCH; else dbg_state <= IDLE; end if;
                            end if;

                        -- PAUSA SEGURA
                        when ARMED_WAIT_FETCH =>
                            if is_fetch_stage_i = '1' then
                                soc_en_o  <= '0'; 
                                dbg_state <= DEBUG_ACTIVE;
                            else
                                soc_en_o  <= not r_bkp_hit;
                            end if;

                        -- AGUARDANDO COMANDOS
                        when DEBUG_ACTIVE =>
                            soc_en_o <= '0'; 
                            if s_rx_valid = '1' then
                                case s_rx_data is
                                    when CMD_RESUME   => dbg_state <= IDLE;
                                    when CMD_STEP     => dbg_state <= STEP_EXEC;
                                    when CMD_RESET    => dbg_state <= APPLY_RESET; 
                                    when CMD_SET_BKP  => dbg_state <= BKP_B0;
                                    when CMD_CLR_BKP  => r_bkp_en  <= '0';
                                    when CMD_READ_REG => 
                                        dbg_state <= DUMP_REGS;
                                        reg_idx <= 0;
                                        byte_idx <= 0;
                                    when others => null;
                                end case;
                            end if;

                        -- ESTADO DE RESET
                        when APPLY_RESET =>
                            debug_rst_o <= '1';          -- Dispara reset do sistema
                            soc_en_o    <= '0';          -- Mantém a CPU congelada
                            dbg_state   <= DEBUG_ACTIVE; -- Volta para modo Debug

                        -- ROTINA DE DESPEJO DE REGISTRADORES (132 BYTES)
                        when DUMP_REGS =>
                            soc_en_o <= '0';
                            if s_tx_busy = '0' and r_tx_start = '0' then
                                
                                -- Usamos a variável MUX em vez do reg_data_i direto
                                case byte_idx is
                                    when 0 => r_tx_data <= s_mux_reg_data(7 downto 0);
                                    when 1 => r_tx_data <= s_mux_reg_data(15 downto 8);
                                    when 2 => r_tx_data <= s_mux_reg_data(23 downto 16);
                                    when 3 => r_tx_data <= s_mux_reg_data(31 downto 24);
                                end case;
                                
                                r_tx_start <= '1'; 
                                
                                if byte_idx = 3 then
                                    byte_idx <= 0;
                                    if reg_idx = 32 then -- NOVO: Vai até 32 (PC)
                                        dbg_state <= DEBUG_ACTIVE;
                                    else
                                        reg_idx <= reg_idx + 1; 
                                    end if;
                                else
                                    byte_idx <= byte_idx + 1; 
                                end if;
                            end if;

                        -- STEP INSTRUCTION
                        when STEP_EXEC =>
                            soc_en_o <= '1';
                            if is_fetch_stage_i = '0' then dbg_state <= STEP_FETCH; end if;
                        when STEP_FETCH =>
                            soc_en_o <= '1';
                            if is_fetch_stage_i = '1' then
                                soc_en_o  <= '0'; 
                                dbg_state <= DEBUG_ACTIVE;
                            end if;

                        -- LEITURA DO ENDEREÇO DE BREAKPOINT (4 BYTES - LITTLE ENDIAN)
                        when BKP_B0 =>
                            soc_en_o <= '0';
                            if s_rx_valid = '1' then r_bkp_addr(7 downto 0) <= s_rx_data; dbg_state <= BKP_B1; end if;
                        when BKP_B1 =>
                            soc_en_o <= '0';
                            if s_rx_valid = '1' then r_bkp_addr(15 downto 8) <= s_rx_data; dbg_state <= BKP_B2; end if;
                        when BKP_B2 =>
                            soc_en_o <= '0';
                            if s_rx_valid = '1' then r_bkp_addr(23 downto 16) <= s_rx_data; dbg_state <= BKP_B3; end if;
                        when BKP_B3 =>
                            soc_en_o <= '0';
                            if s_rx_valid = '1' then 
                                r_bkp_addr(31 downto 24) <= s_rx_data; 
                                r_bkp_en <= '1';         
                                dbg_state <= DEBUG_ACTIVE; 
                            end if;

                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------