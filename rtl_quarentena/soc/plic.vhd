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
--             Suporta até 32 fontes de interrupção com prioridades programáveis.
--
-- Autor     : [André Maiolini]
-- Data      : [31/01/2026]   
--
------------------------------------------------------------------------------------------------------------------
--
-- Mapa de Memória (Base Offset):
--
--   0x000000: Prioridades (1 reg de 32 bits por fonte)
--   0x001000: Pending Bits (1 reg de 32 bits - RO)
--   0x002000: Enables (1 reg de 32 bits por Contexto)
--   0x200000: Threshold (Context 0)
--   0x200004: Claim/Complete (Context 0)
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Define a interface do PLIC (Platform-Level Interrupt Controller)
------------------------------------------------------------------------------------------------------------------

entity plic is

    generic (
        NUM_SOURCES : integer := 4  -- UART, GPIO, DMA, NPU
    );

    port (

        -- Interface de Controle Global --------------------------------------------------------------------------

        Clk_i         : in  std_logic;
        Reset_i       : in  std_logic;

        -- Interface de Barramento (Slave) -----------------------------------------------------------------------

        Addr_i        : in  std_logic_vector(23 downto 0); 
        Data_i        : in  std_logic_vector(31 downto 0);
        Data_o        : out std_logic_vector(31 downto 0);
        We_i          : in  std_logic;
        Vld_i         : in  std_logic;
        Rdy_o         : out std_logic;

        -- Fontes de Interrupção (Assíncronas/Síncronas) ---------------------------------------------------------

        -- Bit 0 deve ser '0' (Source 0 é reservada)
        Irq_Sources_i : in  std_logic_vector(31 downto 0);

        -- Saída para o Core
        Irq_Req_o     : out std_logic -- Liga no Irq_External do Core

        ----------------------------------------------------------------------------------------------------------

    );

end entity;

------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do PLIC (Platform-Level Interrupt Controller)
------------------------------------------------------------------------------------------------------------------

architecture rtl of plic is

    -- Registradores ---------------------------------------------------------------------------------------------

    type t_priority_array is array (0 to 31) of unsigned(2 downto 0); -- 3 bits de prioridade (0-7)
    signal r_priorities : t_priority_array;

    signal r_pending    : std_logic_vector(31 downto 0);
    signal r_enable     : std_logic_vector(31 downto 0);
    signal r_threshold  : unsigned(2 downto 0);
    
    -- Gateway (Detector de Borda/Nível) -------------------------------------------------------------------------

    signal r_gateway_claimed : std_logic_vector(31 downto 0); -- Bits que foram "Claimed" mas ainda não "Completed"

    -- ID da interrupção vencedora -------------------------------------------------------------------------------

    signal s_max_id     : integer range 0 to 31;
    signal s_max_prio   : unsigned(2 downto 0);

    --------------------------------------------------------------------------------------------------------------

begin

    -- ===========================================================================================================
    -- 1. Arbiter (Prioritizer) - Combinacional
    -- ===========================================================================================================

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

    -- Dispara interrupção para o Core se houver um vencedor válido (>0)
    Irq_Req_o <= '1' when s_max_id /= 0 else '0';

    -- ===========================================================================================================
    -- 2. Lógica de Controle de Barramento e Estado (SÍNCRONA)
    -- ===========================================================================================================

    process(Clk_i)
    begin

        if rising_edge(Clk_i) then

            if Reset_i = '1' then

                r_pending         <= (others => '0');
                r_gateway_claimed <= (others => '0');
                r_enable          <= (others => '0');
                r_threshold       <= (others => '0');
                for k in 0 to 31 loop r_priorities(k) <= (others => '0'); end loop;
                
                -- Interface de Barramento Reset
                Rdy_o  <= '0';
                Data_o <= (others => '0');

            else

                -- Defaults
                Rdy_o  <= '0'; 
                Data_o <= (others => '0');

                -- A. GATEWAY LOGIC (Detecta novas interrupções)
                for i in 1 to 31 loop
                    if Irq_Sources_i(i) = '1' and r_gateway_claimed(i) = '0' then
                        r_pending(i) <= '1';
                    end if;
                end loop;

                -- B. BARRAMENTO (Leitura e Escrita)
                if Vld_i = '1' then
                    
                    -- Handshake: Resposta no próximo ciclo (T+1)
                    Rdy_o <= '1'; 

                    -- ESCRITA
                    if We_i = '1' then

                        if Addr_i = x"200004" then -- Complete
                            r_gateway_claimed(to_integer(unsigned(Data_i(4 downto 0)))) <= '0';

                        elsif Addr_i(23 downto 12) = x"000" then -- Priority
                            r_priorities(to_integer(unsigned(Addr_i(6 downto 2)))) <= unsigned(Data_i(2 downto 0));

                        elsif Addr_i = x"002000" then -- Enable
                            r_enable <= Data_i;

                        elsif Addr_i = x"200000" then -- Threshold
                            r_threshold <= unsigned(Data_i(2 downto 0));

                        end if;

                    -- LEITURA
                    else 

                        if Addr_i = x"200004" then -- Claim
                            Data_o <= std_logic_vector(to_unsigned(s_max_id, 32));
                            -- Efeito colateral do Claim: Consumir a pendência
                            if s_max_id /= 0 then
                                r_pending(s_max_id)         <= '0';
                                r_gateway_claimed(s_max_id) <= '1';
                            end if;
                        
                        elsif Addr_i(23 downto 12) = x"000" then -- Priority
                            Data_o(2 downto 0) <= std_logic_vector(r_priorities(to_integer(unsigned(Addr_i(6 downto 2)))));
                        
                        elsif Addr_i = x"001000" then -- Pending
                            Data_o <= r_pending;
                        
                        elsif Addr_i = x"002000" then -- Enable
                            Data_o <= r_enable;
                        
                        elsif Addr_i = x"200000" then -- Threshold
                            Data_o(2 downto 0) <= std_logic_vector(r_threshold);

                        end if;
                        
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture; -- rtl

------------------------------------------------------------------------------------------------------------------