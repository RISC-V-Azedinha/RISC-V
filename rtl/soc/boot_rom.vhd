------------------------------------------------------------------------------------------------------------------
--
-- File: boot_rom.vhd
--
-- ██████╗  ██████╗  ██████╗ ████████╗   ██████╗  ██████╗ ███╗   ███╗
-- ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝   ██╔══██╗██╔═══██╗████╗ ████║
-- ██████╔╝██║   ██║██║   ██║   ██║█████╗██████╔╝██║   ██║██╔████╔██║
-- ██╔══██╗██║   ██║██║   ██║   ██║╚════╝██╔══██╗██║   ██║██║╚██╔╝██║
-- ██████╔╝╚██████╔╝╚██████╔╝   ██║      ██║  ██║╚██████╔╝██║ ╚═╝ ██║
-- ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝      ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
-- 
-- Descrição : Módulo de Boot ROM com inicialização via arquivo HEX
-- 
-- Autor     : [André Maiolini]
-- Data      : [22/12/2025]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Boot ROM
-------------------------------------------------------------------------------------------------------------------

entity boot_rom is
    generic (
        INIT_FILE  : string  := "build/boot/bootloader.hex";     -- Arquivo HEX de inicialização (bootloader)
        ADDR_WIDTH : integer := 10 -- Total de 4 KB              -- Largura do endereço (em palavras de 4 bytes) 
    );
    port (
        -- Sinal de controle de clock (sincronização da leitura)
        clk       : in  std_logic;
        
        -- Porta A: Dedicada ao Fetch (Instruções)
        vld_a_i   : in  std_logic;
        addr_a_i  : in  std_logic_vector(31 downto 0);            -- Endereço de 32 bits para leitura de instruções
        data_a_o  : out std_logic_vector(31 downto 0);            -- Dados de 32 bits lidos (instrução)
        rdy_a_o   : out std_logic;

        -- Porta B: Dedicada ao LOAD/STORE (Dados)
        vld_b_i   : in  std_logic;
        addr_b_i  : in  std_logic_vector(31 downto 0);            -- Endereço de 32 bits para leitura de dados
        data_b_o  : out std_logic_vector(31 downto 0);            -- Dados de 32 bits lidos (dados)
        rdy_b_o   : out std_logic
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da Boot ROM
-------------------------------------------------------------------------------------------------------------------

architecture rtl of boot_rom is

    -- Tipo de dado para a ROM (ARRAY de palavras de 32 bits)
    type t_rom is array (0 to (2**ADDR_WIDTH)-1) of std_logic_vector(31 downto 0);
    
    -- Função para inicializar a ROM a partir de um arquivo HEX
    impure function init_rom_from_file(file_name : string) return t_rom is

        file     f       : text open read_mode is file_name;
        variable l       : line;
        variable v_data  : std_logic_vector(31 downto 0);
        variable v_rom   : t_rom := (others => (others => '0'));
    
    begin
    
        for i in 0 to (2**ADDR_WIDTH)-1 loop
            exit when endfile(f);
            readline(f, l);
            hread(l, v_data);
            v_rom(i) := v_data;
        end loop;
        return v_rom;
    
    end function;

    -- Memória ROM inicializada via arquivo HEX
    signal rom_content : t_rom := init_rom_from_file(INIT_FILE);

    -- ATRIBUTO PARA FORÇAR BRAM (Sintaxe Xilinx/Vivado)
    attribute ram_style : string;
    attribute ram_style of rom_content : signal is "block";

begin

    -- Leitura Síncrona - Porta A (FETCH)
    process(clk)
        variable v_addr_idx : std_logic_vector(ADDR_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if vld_a_i = '1' then
                rdy_a_o <= '1';
            else
                rdy_a_o <= '0';
            end if;

            -- Busca da Instrução
            if vld_a_i = '1' then
                v_addr_idx := addr_a_i(ADDR_WIDTH+1 downto 2);
                if Is_X(v_addr_idx) then
                    data_a_o <= (others => '0');
                else
                    data_a_o <= rom_content(to_integer(unsigned(v_addr_idx)));
                end if;
            end if;
        end if;
    end process;

    -- Leitura Síncrona - Porta B (DADOS)
    process(clk)
        variable v_addr_idx : std_logic_vector(ADDR_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            -- Geração do Ready (1 ciclo de latência)
            if vld_b_i = '1' then
                rdy_b_o <= '1';
            else
                rdy_b_o <= '0';
            end if;

            -- Leitura de Dados
            if vld_b_i = '1' then
                v_addr_idx := addr_b_i(ADDR_WIDTH+1 downto 2);
                if Is_X(v_addr_idx) then
                    data_b_o <= (others => '0');
                else
                    data_b_o <= rom_content(to_integer(unsigned(v_addr_idx)));
                end if;
            end if;
        end if;
    end process;

end architecture;

-------------------------------------------------------------------------------------------------------------------