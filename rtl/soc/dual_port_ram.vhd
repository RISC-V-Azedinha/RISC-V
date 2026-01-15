------------------------------------------------------------------------------------------------------------------
-- 
-- File: dual_port_ram.vhd
--
-- ██████╗  █████╗ ███╗   ███╗
-- ██╔══██╗██╔══██╗████╗ ████║
-- ██████╔╝███████║██╔████╔██║
-- ██╔══██╗██╔══██║██║╚██╔╝██║
-- ██║  ██║██║  ██║██║ ╚═╝ ██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝
--  
-- Descrição : Módulo de RAM dual-port para leitura e escrita simultâneas
--    em duas portas independentes - usando BRAM inferida.
-- 
-- Autor     : [André Maiolini]
-- Data      : [30/12/2025]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

entity dual_port_ram is
    generic (
        ADDR_WIDTH : integer := 12; 
        DATA_WIDTH : integer := 32
    );
    port (
        clk        : in  std_logic;
        
        -- Porta A
        we_a       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        addr_a     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_in_a  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_out_a : out std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Porta B
        en_b_i     : in  std_logic;
        we_b       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        addr_b     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_in_b  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_out_b : out std_logic_vector(DATA_WIDTH-1 downto 0);
        ready_b_o  : out std_logic
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

architecture rtl of dual_port_ram is

    -- Tipo de dado para a RAM
    type t_ram is array (0 to (2**ADDR_WIDTH)-1)
        of std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Usar shared variable permite que múltiplos processos acessem a memória sem conflito.
    shared variable ram : t_ram := (others => (others => '0'));

    -- Atributo para forçar inferência de Block RAM 
    attribute ram_style : string;
    attribute ram_style of ram : variable is "block";

begin

    -- =========================
    -- PORTA A
    -- =========================
    process(clk)
    begin

        if rising_edge(clk) then

            -- MODO READ-FIRST:
            -- 1. Lemos a variável para a saída (pega o valor atual/antigo)
            data_out_a <= ram(to_integer(unsigned(addr_a)));

            -- 2. Escrita com Byte Enable
            for i in 0 to (DATA_WIDTH/8)-1 loop
                if we_a(i) = '1' then
                    -- Escreve apenas no byte correspondente (i*8 até i*8+7)
                    ram(to_integer(unsigned(addr_a)))(8*i+7 downto 8*i) := data_in_a(8*i+7 downto 8*i);
                end if;
            end loop;

        end if;
        
    end process;

    -- =========================
    -- PORTA B
    -- =========================
    process(clk)
    begin

        if rising_edge(clk) then

            if en_b_i = '1' then
                ready_b_o <= '1';
            else
                ready_b_o <= '0';
            end if;

            -- Acesso à Memória
            if en_b_i = '1' then
                data_out_b <= ram(to_integer(unsigned(addr_b)));
                for i in 0 to (DATA_WIDTH/8)-1 loop
                    if we_b(i) = '1' then
                        ram(to_integer(unsigned(addr_b)))(8*i+7 downto 8*i) := data_in_b(8*i+7 downto 8*i);
                    end if;
                end loop;
            end if;

        end if;

    end process;

end architecture;

-------------------------------------------------------------------------------------------------------------------