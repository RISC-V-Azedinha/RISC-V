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
-- Descrição: Core Local Interruptor (Compacto) para RISC-V Single Core
--            Implementa mtime, mtimecmp e msip. RISC-V Privileged Spec
--
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Define a interface do CLINT (Core Local Interruptor)
-------------------------------------------------------------------------------------------------------------

entity clint is

    port (

        -- Interface de Controle Global ---------------------------------------------------------------------

        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        
        -- Interface de Barramento (MMIO slave) -------------------------------------------------------------

        addr_i      : in  std_logic_vector(4 downto 0); 
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        we_i        : in  std_logic;
        vld_i       : in  std_logic;
        rdy_o       : out std_logic;

        -- Saídas de Interrupção (Direto para o Core) -------------------------------------------------------

        irq_timer_o : out std_logic;
        irq_soft_o  : out std_logic

        -----------------------------------------------------------------------------------------------------

    );

end entity;

-------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do CLINT (Core Local Interruptor)
-------------------------------------------------------------------------------------------------------------

architecture rtl of clint is

    -- Registradores de 64 bits

    signal r_mtime    : unsigned(63 downto 0);
    signal r_mtimecmp : unsigned(63 downto 0);

    signal r_msip     : std_logic; -- Software Interrupt Pending

begin

    -- ======================================================================================================
    -- Lógica de Geração de Interrupções
    -- ======================================================================================================
    
    -- Timer Interrupt: dispara quando mtime >= mtimecmp
    irq_timer_o <= '1' when (r_mtime >= r_mtimecmp) else '0';
    
    -- Software Interrupt: dispara quando msip(0) = 1 estiver setado via software
    irq_soft_o  <= r_msip;

    -- ======================================================================================================
    -- Lógica Principal
    -- ======================================================================================================

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                r_mtime    <= (others => '0');
                r_mtimecmp <= (others => '1'); -- Max Value (sem IRQ no boot)
                r_msip     <= '0';
                rdy_o      <= '0';
                data_o     <= (others => '0');
            else

                -- Incremento Contínuo do Timer 
                r_mtime <= r_mtime + 1;

                -- Handshake de Barramento
                rdy_o <= '0'; -- Pulso único

                if vld_i = '1' then

                    rdy_o <= '1';
                    
                    if we_i = '1' then

                        -- === ESCRITA ======================================================================

                        case addr_i is

                            -- ------------------------------------------------------------------------------
                            -- MSIP: Machine Software Interrupt Pending (Offset 0x00)
                            -- Escrita no bit 0 gera uma interrupção de software.
                            -- ------------------------------------------------------------------------------

                            when "00000" => r_msip <= data_i(0);

                            -- ------------------------------------------------------------------------------
                            -- MTIMECMP: Machine Timer Compare (Offsets 0x08 e 0x0C)
                            -- Define o "alarme" do timer. São 64 bits divididos em 2 palavras.
                            -- ------------------------------------------------------------------------------

                            when "01000" => r_mtimecmp(31 downto 0)  <= unsigned(data_i); -- Low (0x08)
                            when "01100" => r_mtimecmp(63 downto 32) <= unsigned(data_i); -- High (0x0C)

                            -- ------------------------------------------------------------------------------
                            -- MTIME: Machine Time (Offsets 0x10 e 0x14)
                            -- Permite escrever no contador atual.
                            -- ------------------------------------------------------------------------------

                            when "10000" => r_mtime(31 downto 0)     <= unsigned(data_i); -- Low (0x10)
                            when "10100" => r_mtime(63 downto 32)    <= unsigned(data_i); -- High (0x14)
                            
                            when others => null;

                        end case;
                    else

                        -- === LEITURA ======================================================================

                        case addr_i is

                            -- Leitura do MSIP --------------------------------------------------------------

                            when "00000" => data_o <= (0 => r_msip, others => '0');
                            
                            -- Leitura do MTIMECMP ----------------------------------------------------------

                            when "01000" => data_o <= std_logic_vector(r_mtimecmp(31 downto 0));
                            when "01100" => data_o <= std_logic_vector(r_mtimecmp(63 downto 32));
                            
                            -- Leitura do MTIME (Contador Atual) --------------------------------------------

                            when "10000" => data_o <= std_logic_vector(r_mtime(31 downto 0));
                            when "10100" => data_o <= std_logic_vector(r_mtime(63 downto 32));
                            
                            when others => data_o <= (others => '0');

                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture; -- rtl 

-------------------------------------------------------------------------------------------------------------