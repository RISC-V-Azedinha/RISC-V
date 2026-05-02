------------------------------------------------------------------------------------------------------------------
-- 
-- File: video_ram.vhd
-- 
-- ██╗   ██╗██████╗  █████╗ ███╗   ███╗
-- ██║   ██║██╔══██╗██╔══██╗████╗ ████║
-- ██║   ██║██████╔╝███████║██╔████╔██║
-- ╚██╗ ██╔╝██╔══██╗██╔══██║██║╚██╔╝██║
--  ╚████╔╝ ██║  ██║██║  ██║██║ ╚═╝ ██║
--   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝
-- 
-- Descrição : Memória de Vídeo para o Controlador VGA (Video RAM).
-- 
-- Autor     : [André Maiolini]
-- Data      : [02/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Video RAM (Memória de Vídeo)
-------------------------------------------------------------------------------------------------------------------

entity video_ram is
    generic (
        ADDR_WIDTH : integer := 17; -- 320x240 = 76.800 endereços (precisa de 17 bits)
        DATA_WIDTH : integer := 8   -- 8 bits de cor (RRRGGGBB)
    );
    port (
        clk      : in std_logic;
        
        -- Porta A: Processador (Escrita)
        we_a     : in std_logic;
        addr_a   : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_a   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Porta B: VGA Core (Leitura)
        addr_b   : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_b   : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Definição do comportamento da Memória de Vídeo (Video RAM)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of video_ram is

    -- Inferência de Block RAM (BRAM)
    type ram_type is array (0 to (2**ADDR_WIDTH)-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ram : ram_type := (others => (others => '0'));

begin

    -- Processo de Leitura/Escrita da RAM
    process(clk)
    begin

        if rising_edge(clk) then

            -- Escrita do Processador (Write-First)
            if we_a = '1' then
                ram(to_integer(unsigned(addr_a))) <= data_a;
            end if;
            
            -- Leitura do VGA (Sempre ativa)
            data_b <= ram(to_integer(unsigned(addr_b)));

        end if;

    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------