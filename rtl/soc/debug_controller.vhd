------------------------------------------------------------------------------------------------------------------
-- File: debug_controller.vhd
-- Descrição : Controlador de Debug Out-of-Band (Multiplexado).
--             [ATUALIZADO: Opcodes Dinâmicos de Boot Address e Register Clear]
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;      
use ieee.numeric_std.all;

entity debug_controller is
    generic (
        CLK_FREQ    : integer := 100_000_000;
        BAUD_RATE   : integer := 115_200
    );
    port (
        clk_i            : in  std_logic;
        rst_i            : in  std_logic;
        uart_rx_i        : in  std_logic;
        uart_tx_o        : out std_logic;
        uart_rts_i       : in  std_logic;
        
        is_fetch_stage_i : in  std_logic;
        soc_en_o         : out std_logic;
        debug_rst_o      : out std_logic;
        
        -- NOVAS PORTAS FÍSICAS DE CONTROLE
        dbg_boot_addr_o  : out std_logic_vector(31 downto 0);
        dbg_reg_clr_o    : out std_logic;

        reg_addr_o       : out std_logic_vector(4 downto 0);
        reg_data_i       : in  std_logic_vector(31 downto 0);
        pc_i             : in  std_logic_vector(31 downto 0) 
    );
end entity debug_controller;

architecture rtl of debug_controller is

    constant c_BIT_PERIOD : integer := CLK_FREQ / BAUD_RATE;

    constant CMD_HALT       : std_logic_vector(7 downto 0) := x"01";
    constant CMD_RESUME     : std_logic_vector(7 downto 0) := x"02";
    constant CMD_STEP       : std_logic_vector(7 downto 0) := x"03";
    constant CMD_RESET_RUN  : std_logic_vector(7 downto 0) := x"04";
    constant CMD_SET_BKP    : std_logic_vector(7 downto 0) := x"05";
    constant CMD_CLR_BKP    : std_logic_vector(7 downto 0) := x"06";
    constant CMD_RESET_HALT : std_logic_vector(7 downto 0) := x"08";
    constant CMD_SET_BOOT   : std_logic_vector(7 downto 0) := x"09";
    constant CMD_CLR_REGS   : std_logic_vector(7 downto 0) := x"0A";
    constant CMD_READ_REG   : std_logic_vector(7 downto 0) := x"10";

    type t_rx_state is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state   : t_rx_state;
    signal rx_timer   : integer range 0 to c_BIT_PERIOD;
    signal rx_bit_idx : integer range 0 to 7;
    signal rx_shifter : std_logic_vector(7 downto 0);
    signal rx_sync    : std_logic_vector(1 downto 0);
    
    signal s_rx_data  : std_logic_vector(7 downto 0);
    signal s_rx_valid : std_logic;

    type t_tx_state is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state       : t_tx_state;
    signal tx_timer       : integer range 0 to c_BIT_PERIOD;
    signal tx_bit_idx     : integer range 0 to 7;
    signal tx_shifter     : std_logic_vector(7 downto 0);
    
    signal r_tx_start     : std_logic;
    signal r_tx_data      : std_logic_vector(7 downto 0);
    signal s_tx_busy      : std_logic;

    type t_dbg_state is (
        IDLE, WAIT_FE, WAIT_BA, WAIT_BE, 
        ARMED_WAIT_FETCH, DEBUG_ACTIVE, STEP_EXEC, STEP_FETCH,
        DUMP_REGS, APPLY_RESET,
        BKP_B0, BKP_B1, BKP_B2, BKP_B3,
        BOOT_B0, BOOT_B1, BOOT_B2, BOOT_B3,
        WAIT_REG_CLR
    );
    signal dbg_state : t_dbg_state;
    
    signal reg_idx  : integer range 0 to 32;
    signal byte_idx : integer range 0 to 3;
    signal s_mux_reg_data : std_logic_vector(31 downto 0);

    signal r_bkp_addr       : std_logic_vector(31 downto 0) := (others => '0');
    signal r_boot_addr      : std_logic_vector(31 downto 0) := (others => '0');
    signal r_reset_run_flag : std_logic := '0';
    signal r_bkp_en         : std_logic := '0';
    signal r_bkp_hit        : std_logic := '0';
    signal r_bkp_bypass     : std_logic := '0';
    signal s_bkp_match      : std_logic;
    signal r_soc_en         : std_logic := '1';
    signal r_bkp_alerted    : std_logic := '0';
    signal r_bkp_delay      : integer range 0 to 2047 := 0;

begin

    dbg_boot_addr_o <= r_boot_addr;
    s_bkp_match <= '1' when (r_bkp_en = '1' and pc_i = r_bkp_addr and is_fetch_stage_i = '1' and r_bkp_bypass = '0') else '0';
    soc_en_o <= '0' when (r_bkp_hit = '1' or s_bkp_match = '1') else r_soc_en;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            rx_sync <= rx_sync(0) & uart_rx_i;
        end if;
    end process;

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
                        else tx_timer <= 0; tx_state <= TX_DATA;
                        tx_bit_idx <= 0; end if;
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

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                r_bkp_hit    <= '0';
                r_bkp_bypass <= '0';
            else
                if pc_i /= r_bkp_addr then
                    r_bkp_bypass <= '0';
                end if;
                
                -- CMD_RESET_HALT e RUN também levantam o bypass para a CPU destravar se parada no breakpoint
                if (dbg_state = DEBUG_ACTIVE and s_rx_valid = '1' and 
                   (s_rx_data = CMD_RESUME or s_rx_data = CMD_STEP or s_rx_data = CMD_RESET_RUN or s_rx_data = CMD_RESET_HALT or s_rx_data = CMD_CLR_BKP)) then
        
                    r_bkp_hit    <= '0';
                    r_bkp_bypass <= '1';
                
                elsif s_bkp_match = '1' then
                    r_bkp_hit <= '1';
                end if;
            end if;
        end if;
    end process;

    reg_addr_o <= std_logic_vector(to_unsigned(reg_idx mod 32, 5));
    s_mux_reg_data <= pc_i when reg_idx = 32 else reg_data_i;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            
            if rst_i = '1' then
                dbg_state     <= IDLE;
                r_soc_en      <= '1';
                debug_rst_o   <= '0';
                dbg_reg_clr_o <= '0';
                r_tx_start    <= '0';
                r_bkp_en      <= '0'; 
                r_bkp_alerted <= '0';
                r_boot_addr   <= (others => '0'); -- Retorna à ROM em hardware-reset
            else
                r_tx_start  <= '0';
                debug_rst_o <= '0'; 

                if uart_rts_i = '0' then
                    dbg_state <= IDLE;
                    r_soc_en  <= '1'; 
                    dbg_reg_clr_o <= '0';

                    if r_bkp_hit = '1' and r_bkp_alerted = '0' then
                        if r_bkp_delay < 1500 then
                            r_bkp_delay <= r_bkp_delay + 1;
                        elsif s_tx_busy = '0' then
                            r_tx_data <= x"BB";
                            r_tx_start <= '1';
                            r_bkp_alerted <= '1'; 
                        end if;
                    else
                        r_bkp_delay <= 0;
                    end if;
                else
                    case dbg_state is
                        when IDLE =>
                            r_soc_en <= '1';
                            r_bkp_alerted <= '0';
                            dbg_reg_clr_o <= '0';
                            if s_rx_valid = '1' and s_rx_data = x"CA" then dbg_state <= WAIT_FE; end if;
                        when WAIT_FE =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"FE" then dbg_state <= WAIT_BA;
                                else dbg_state <= IDLE; end if;
                            end if;
                        when WAIT_BA =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"BA" then dbg_state <= WAIT_BE;
                                else dbg_state <= IDLE; end if;
                            end if;
                        when WAIT_BE =>
                            if s_rx_valid = '1' then
                                if s_rx_data = x"BE" then dbg_state <= ARMED_WAIT_FETCH;
                                else dbg_state <= IDLE; end if;
                            end if;

                        when ARMED_WAIT_FETCH =>
                            if is_fetch_stage_i = '1' then
                                r_soc_en  <= '0';
                                dbg_state <= DEBUG_ACTIVE;
                            else
                                r_soc_en  <= '1';
                            end if;

                        when DEBUG_ACTIVE =>
                            r_soc_en <= '0';
                            dbg_reg_clr_o <= '0'; -- O pulso de Clear encerra aqui
                            if s_rx_valid = '1' then
                                case s_rx_data is
                                    when CMD_RESUME     => dbg_state <= IDLE;
                                    when CMD_STEP       => dbg_state <= STEP_EXEC;
                                    when CMD_RESET_RUN  => r_reset_run_flag <= '1'; dbg_state <= APPLY_RESET;
                                    when CMD_RESET_HALT => r_reset_run_flag <= '0'; dbg_state <= APPLY_RESET;
                                    when CMD_SET_BKP    => dbg_state <= BKP_B0;
                                    when CMD_CLR_BKP    => r_bkp_en  <= '0';
                                    when CMD_READ_REG   => dbg_state <= DUMP_REGS; reg_idx <= 0; byte_idx <= 0;
                                    when CMD_SET_BOOT   => dbg_state <= BOOT_B0;
                                    when CMD_CLR_REGS   => dbg_reg_clr_o <= '1'; dbg_state <= WAIT_REG_CLR; -- Pulso Síncrono 1 ciclo
                                    when others => null;
                                end case;
                            end if;
                            
                        when WAIT_REG_CLR =>
                            dbg_reg_clr_o <= '0';
                            dbg_state <= DEBUG_ACTIVE;
                            
                        when APPLY_RESET =>
                            debug_rst_o <= '1';
                            if r_reset_run_flag = '1' then
                                r_soc_en  <= '1';
                                dbg_state <= IDLE;
                            else
                                r_soc_en  <= '0';
                                dbg_state <= DEBUG_ACTIVE;
                            end if;
                            
                        when DUMP_REGS =>
                            r_soc_en <= '0';
                            if s_tx_busy = '0' and r_tx_start = '0' then
                                case byte_idx is
                                    when 0 => r_tx_data <= s_mux_reg_data(7 downto 0);
                                    when 1 => r_tx_data <= s_mux_reg_data(15 downto 8);
                                    when 2 => r_tx_data <= s_mux_reg_data(23 downto 16);
                                    when 3 => r_tx_data <= s_mux_reg_data(31 downto 24);
                                end case;
                                
                                r_tx_start <= '1';
                                if byte_idx = 3 then
                                    byte_idx <= 0;
                                    if reg_idx = 32 then
                                        dbg_state <= DEBUG_ACTIVE;
                                    else
                                        reg_idx <= reg_idx + 1;
                                    end if;
                                else
                                    byte_idx <= byte_idx + 1;
                                end if;
                            end if;

                        when STEP_EXEC =>
                            r_soc_en <= '1';
                            if is_fetch_stage_i = '0' then dbg_state <= STEP_FETCH; end if;
                        when STEP_FETCH =>
                            r_soc_en <= '1';
                            if is_fetch_stage_i = '1' then
                                r_soc_en  <= '0';
                                dbg_state <= DEBUG_ACTIVE;
                            end if;

                        when BKP_B0 => r_soc_en <= '0'; if s_rx_valid = '1' then r_bkp_addr(7 downto 0) <= s_rx_data; dbg_state <= BKP_B1; end if;
                        when BKP_B1 => r_soc_en <= '0'; if s_rx_valid = '1' then r_bkp_addr(15 downto 8) <= s_rx_data; dbg_state <= BKP_B2; end if;
                        when BKP_B2 => r_soc_en <= '0'; if s_rx_valid = '1' then r_bkp_addr(23 downto 16) <= s_rx_data; dbg_state <= BKP_B3; end if;
                        when BKP_B3 => 
                            r_soc_en <= '0';
                            if s_rx_valid = '1' then 
                                r_bkp_addr(31 downto 24) <= s_rx_data;
                                r_bkp_en <= '1';         
                                dbg_state <= DEBUG_ACTIVE; 
                            end if;
                            
                        when BOOT_B0 => r_soc_en <= '0'; if s_rx_valid = '1' then r_boot_addr(7 downto 0) <= s_rx_data; dbg_state <= BOOT_B1; end if;
                        when BOOT_B1 => r_soc_en <= '0'; if s_rx_valid = '1' then r_boot_addr(15 downto 8) <= s_rx_data; dbg_state <= BOOT_B2; end if;
                        when BOOT_B2 => r_soc_en <= '0'; if s_rx_valid = '1' then r_boot_addr(23 downto 16) <= s_rx_data; dbg_state <= BOOT_B3; end if;
                        when BOOT_B3 => 
                            r_soc_en <= '0';
                            if s_rx_valid = '1' then 
                                r_boot_addr(31 downto 24) <= s_rx_data;
                                dbg_state <= DEBUG_ACTIVE; 
                            end if;

                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture;