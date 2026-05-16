-------------------------------------------------------------------------------------------------------------
-- File: clint.vhd
--
--   ██████╗██╗     ██╗███╗   ██╗████████╗
--  ██╔════╝██║     ██║████╗  ██║╚══██╔══╝
--  ██║     ██║     ██║██╔██╗ ██║   ██║   
--  ██║     ██║     ██║██║╚██╗██║   ██║   
--  ╚██████╗███████╗██║██║ ╚████║   ██║   
--   ╚═════╝╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝   
--
-- Descrição : Core Local Interruptor (Compacto) para RISC-V Single Core
--             [ATUALIZADO: Edge Guard para Barramento MMIO Seguro]
--
-- Autor     : [André Maiolini]
-- Data      : [31/01/2026]   
--
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------
-- ENTIDADE
-------------------------------------------------------------------------------------------------------------
entity clint is
    port (
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        soc_en_i    : in  std_logic;
        
        addr_i      : in  std_logic_vector(4 downto 0); 
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        we_i        : in  std_logic;
        vld_i       : in  std_logic;
        rdy_o       : out std_logic;

        irq_timer_o : out std_logic;
        irq_soft_o  : out std_logic
    );
end entity;

-------------------------------------------------------------------------------------------------------------
-- ARQUITETURA
-------------------------------------------------------------------------------------------------------------
architecture rtl of clint is

    signal r_mtime    : unsigned(63 downto 0);
    signal r_mtimecmp : unsigned(63 downto 0);
    signal r_msip     : std_logic;

    -- Edge Guard
    signal r_rdy      : std_logic := '0';

begin

    irq_timer_o <= '1' when (r_mtime >= r_mtimecmp) else '0';
    irq_soft_o  <= r_msip;
    
    rdy_o       <= r_rdy;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                r_mtime    <= (others => '0');
                r_mtimecmp <= (others => '1');
                r_msip     <= '0';
                r_rdy      <= '0';
                data_o     <= (others => '0');
            else

                if soc_en_i = '1' then
                    r_mtime <= r_mtime + 1;
                end if;

                -- Handshake de Barramento Seguro
                r_rdy  <= '0'; 
                data_o <= (others => '0');

                if vld_i = '1' and r_rdy = '0' then

                    r_rdy <= '1';
                    
                    if we_i = '1' then
                        case addr_i is
                            when "00000" => r_msip <= data_i(0);
                            when "01000" => r_mtimecmp(31 downto 0)  <= unsigned(data_i);
                            when "01100" => r_mtimecmp(63 downto 32) <= unsigned(data_i);
                            when "10000" => r_mtime(31 downto 0)     <= unsigned(data_i);
                            when "10100" => r_mtime(63 downto 32)    <= unsigned(data_i);
                            when others => null;
                        end case;
                    else
                        case addr_i is
                            when "00000" => data_o <= (0 => r_msip, others => '0');
                            when "01000" => data_o <= std_logic_vector(r_mtimecmp(31 downto 0));
                            when "01100" => data_o <= std_logic_vector(r_mtimecmp(63 downto 32));
                            when "10000" => data_o <= std_logic_vector(r_mtime(31 downto 0));
                            when "10100" => data_o <= std_logic_vector(r_mtime(63 downto 32));
                            when others => data_o <= (others => '0');
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture;