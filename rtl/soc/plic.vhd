------------------------------------------------------------------------------------------------------------------
-- File: plic.vhd
--
--  ██████╗ ██╗     ██╗ ██████╗
--  ██╔══██╗██║     ██║██╔════╝
--  ██████╔╝██║     ██║██║     
--  ██╔═══╝ ██║     ██║██║     
--  ██║     ███████╗██║╚██████╗
--  ╚═╝     ╚══════╝╚═╝ ╚═════╝
--                       
-- Descrição : Mini-PLIC (Platform-Level Interrupt Controller) para RISC-V.
--             [ATUALIZADO: Edge Guard e proteção contra leituras destrutivas fantasma]
--
-- Autor     : [André Maiolini]
-- Data      : [31/01/2026]   
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity plic is
    generic (
        NUM_SOURCES : integer := 4
    );
    port (
        Clk_i         : in  std_logic;
        Reset_i       : in  std_logic;

        Addr_i        : in  std_logic_vector(23 downto 0); 
        Data_i        : in  std_logic_vector(31 downto 0);
        Data_o        : out std_logic_vector(31 downto 0);
        We_i          : in  std_logic;
        Vld_i         : in  std_logic;
        Rdy_o         : out std_logic;

        Irq_Sources_i : in  std_logic_vector(31 downto 0);
        Irq_Req_o     : out std_logic 
    );
end entity;

architecture rtl of plic is

    type t_priority_array is array (0 to 31) of unsigned(2 downto 0);
    signal r_priorities : t_priority_array;
    signal r_pending    : std_logic_vector(31 downto 0);
    signal r_enable     : std_logic_vector(31 downto 0);
    signal r_threshold  : unsigned(2 downto 0);
    signal r_gateway_claimed : std_logic_vector(31 downto 0);

    signal s_max_id     : integer range 0 to 31;
    signal s_max_prio   : unsigned(2 downto 0);

    -- Edge Guard
    signal r_rdy        : std_logic := '0';

begin

    Rdy_o <= r_rdy;

    -- Arbiter
    process(r_pending, r_enable, r_priorities, r_threshold)
        variable v_max_prio : unsigned(2 downto 0);
        variable v_max_id   : integer;
    begin
        v_max_prio := r_threshold;
        v_max_id   := 0;
        for i in 1 to 31 loop
            if r_pending(i) = '1' and r_enable(i) = '1' then
                if r_priorities(i) > v_max_prio then
                    v_max_prio := r_priorities(i);
                    v_max_id   := i;
                end if;
            end if;
        end loop;
        s_max_id   <= v_max_id;
        s_max_prio <= v_max_prio;
    end process;

    Irq_Req_o <= '1' when s_max_id /= 0 else '0';

    -- Lógica Síncrona
    process(Clk_i)
    begin
        if rising_edge(Clk_i) then
            if Reset_i = '1' then
                r_pending         <= (others => '0');
                r_gateway_claimed <= (others => '0');
                r_enable          <= (others => '0');
                r_threshold       <= (others => '0');
                for k in 0 to 31 loop r_priorities(k) <= (others => '0'); end loop;
                r_rdy  <= '0';
                Data_o <= (others => '0');
            else

                -- Gateway
                for i in 1 to 31 loop
                    if Irq_Sources_i(i) = '1' and r_gateway_claimed(i) = '0' then
                        r_pending(i) <= '1';
                    end if;
                end loop;

                -- Handshake Seguro
                r_rdy  <= '0'; 
                Data_o <= (others => '0');

                if Vld_i = '1' and r_rdy = '0' then
                    r_rdy <= '1'; 

                    if We_i = '1' then
                        if Addr_i = x"200004" then 
                            r_gateway_claimed(to_integer(unsigned(Data_i(4 downto 0)))) <= '0';
                        elsif Addr_i(23 downto 12) = x"000" then 
                            r_priorities(to_integer(unsigned(Addr_i(6 downto 2)))) <= unsigned(Data_i(2 downto 0));
                        elsif Addr_i = x"002000" then 
                            r_enable <= Data_i;
                        elsif Addr_i = x"200000" then 
                            r_threshold <= unsigned(Data_i(2 downto 0));
                        end if;
                    else 
                        if Addr_i = x"200004" then 
                            Data_o <= std_logic_vector(to_unsigned(s_max_id, 32));
                            if s_max_id /= 0 then
                                r_pending(s_max_id)         <= '0';
                                r_gateway_claimed(s_max_id) <= '1';
                            end if;
                        elsif Addr_i(23 downto 12) = x"000" then 
                            Data_o(2 downto 0) <= std_logic_vector(r_priorities(to_integer(unsigned(Addr_i(6 downto 2)))));
                        elsif Addr_i = x"001000" then 
                            Data_o <= r_pending;
                        elsif Addr_i = x"002000" then 
                            Data_o <= r_enable;
                        elsif Addr_i = x"200000" then 
                            Data_o(2 downto 0) <= std_logic_vector(r_threshold);
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture;