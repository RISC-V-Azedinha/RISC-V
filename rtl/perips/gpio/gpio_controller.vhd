----------------------------------------------------------------------------------
-- 
-- File: gpio_controller.vhd
--
--  ██████╗ ██████╗ ██╗ ██████╗ 
-- ██╔════╝ ██╔══██╗██║██╔═══██╗
-- ██║  ███╗██████╔╝██║██║   ██║
-- ██║   ██║██╔═══╝ ██║██║   ██║
-- ╚██████╔╝██║     ██║╚██████╔╝
--  ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ 
--                          
-- Descrição : Controlador simples de GPIO (LEDs e Switches)
-- 
-- Autor     : [André Maiolini]
-- Data      : [31/12/2025]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Controlador de GPIO
-------------------------------------------------------------------------------------------------------------------

entity gpio_controller is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Interface do Barramento
        sel_i       : in  std_logic;                      -- Chip Select (Ativo quando endereço é 0x2...)
        we_i        : in  std_logic;                      -- Write Enable
        addr_i      : in  std_logic_vector( 3 downto 0);  -- Offset do endereço
        data_i      : in  std_logic_vector(31 downto 0);
        data_o      : out std_logic_vector(31 downto 0);
        ready_o     : out std_logic;
        
        -- Pinos Externos
        gpio_leds   : out std_logic_vector(15 downto 0);
        gpio_sw     : in  std_logic_vector(15 downto 0)
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do Controlador de GPIO
-------------------------------------------------------------------------------------------------------------------

architecture rtl of gpio_controller is

    signal r_leds : std_logic_vector(15 downto 0);

begin
    
    -- Conexão física
    gpio_leds <= r_leds;
    ready_o <= '1';

    -- Processo de Escrita (CPU -> LEDs)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_leds <= (others => '0');
            elsif sel_i = '1' and we_i = '1' then
                -- Offset 0x00: Registrador de LEDs
                if unsigned(addr_i) = 0 then
                    r_leds <= data_i(15 downto 0);
                end if;
            end if;
        end if;
    end process;

    -- Processo de Leitura (CPU <- Switches/LEDs)
    process(addr_i, r_leds, gpio_sw)
    begin
        data_o <= (others => '0'); -- Default
        
        case to_integer(unsigned(addr_i)) is
            when 0 => -- Lê o estado atual dos LEDs
                data_o(15 downto 0) <= r_leds;
            when 4 => -- Lê os Switches (Offset 0x04)
                data_o(15 downto 0) <= gpio_sw;
            when others =>
                null;
        end case;
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------