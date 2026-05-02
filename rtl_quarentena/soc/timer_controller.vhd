------------------------------------------------------------------------------------------------------------------
--
-- File: timer_controller.vhd
--
--  ████████╗██╗███╗   ███╗███████╗██████╗ 
--  ╚══██╔══╝██║████╗ ████║██╔════╝██╔══██╗
--     ██║   ██║██╔████╔██║█████╗  ██████╔╝
--     ██║   ██║██║╚██╔╝██║██╔══╝  ██╔══██╗
--     ██║   ██║██║ ╚═╝ ██║███████╗██║  ██║
--     ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝
-- 
-- Descrição : Temporizador MMIO (para cronometragem de benchmark)
-- 
-- Autor     : [André Maiolini]
-- Data      : [23/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Timer
-------------------------------------------------------------------------------------------------------------------

entity timer_controller is

    port (

        -- Sinais de Controle e Sincronização ---------------------------------------------------------------------

        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        
        -- Interface de Barramento (Slave) ------------------------------------------------------------------------

        addr_i      : in  std_logic_vector(3 downto 0); 
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        we_i        : in  std_logic;
        vld_i       : in  std_logic;
        rdy_o       : out std_logic

        -----------------------------------------------------------------------------------------------------------

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Implementação comportamental do Timer
-------------------------------------------------------------------------------------------------------------------

architecture rtl of timer_controller is

    -- Contador Real (64 bits) - Incrementa continuamente ---------------------------------------------------------

    signal r_counter_run : unsigned(63 downto 0);
    
    -- Registradores de Snapshot (64 bits) - Estáticos para leitura segura ----------------------------------------
    
    signal r_counter_snap : std_logic_vector(63 downto 0);

    -- Controle ---------------------------------------------------------------------------------------------------

    signal r_enable : std_logic;

    ---------------------------------------------------------------------------------------------------------------

begin

    process(clk_i)
    begin

        if rising_edge(clk_i) then

            if rst_i = '1' then

                r_counter_run  <= (others => '0');
                r_counter_snap <= (others => '0');
                r_enable       <= '0';
                rdy_o          <= '0';
                data_o         <= (others => '0');

            else

                -- 1. Lógica do Contador (Free Running se Habilitado)
                if r_enable = '1' then
                    r_counter_run <= r_counter_run + 1;
                end if;

                -- 2. Interface de Barramento
                rdy_o <= '0'; -- Pulso único de Ready
                
                if vld_i = '1' then

                    rdy_o <= '1';
                    
                    if we_i = '1' then

                        -- === ESCRITA (COMANDOS) ===
                        if addr_i = x"0" then

                            -- [Bit 0] ENABLE: 1=Run, 0=Stop
                            r_enable <= data_i(0);
                            
                            -- [Bit 1] RESET: 1=Zera Contador (Auto-clearing funcional)
                            if data_i(1) = '1' then
                                r_counter_run <= (others => '0');
                            end if;

                            -- [Bit 2] SNAPSHOT: 1=Tira Foto (Atualiza registradores de leitura)
                            if data_i(2) = '1' then
                                r_counter_snap <= std_logic_vector(r_counter_run);
                            end if;

                        end if;

                    else

                        -- === LEITURA (DATA) ===
                        case addr_i is

                            when x"0" => -- STATUS
                                data_o <= (0 => r_enable, others => '0');
                                
                            when x"4" => -- LOW WORD (Do Snapshot)
                                data_o <= r_counter_snap(31 downto 0);
                                
                            when x"8" => -- HIGH WORD (Do Snapshot)
                                data_o <= r_counter_snap(63 downto 32);
                                
                            when others => 
                                data_o <= (others => '0');

                        end case;

                    end if;

                end if;

            end if;

        end if;

    end process;

end architecture; -- rtl 

-------------------------------------------------------------------------------------------------------------------