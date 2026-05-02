------------------------------------------------------------------------------------------------------------------
-- 
-- File: reg_file.vhd
--
--   ██████╗ ███████╗ ██████╗         ███████╗██╗██╗     ███████╗
--   ██╔══██╗██╔════╝██╔════╝         ██╔════╝██║██║     ██╔════╝
--   ██████╔╝█████╗  ██║  ███╗        █████╗  ██║██║     █████╗  
--   ██╔══██╗██╔══╝  ██║   ██║        ██╔══╝  ██║██║     ██╔══╝  
--   ██║  ██║███████╗╚██████╔╝███████╗██║     ██║███████╗███████╗
--   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝╚══════╝                                                            
-- 
-- Descrição : Banco de Registradores de 32 bits com 32 registradores.
--             Permite leitura e escrita de dados com controle de escrita (RegWrite_i).
--             Leitura assíncrona e escrita síncrona.
--
-- Autor     : [André Maiolini]
-- Data      : [14/09/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do banco de registradores
-------------------------------------------------------------------------------------------------------------------

entity reg_file is

    port (

        -- Entradas
        clk_i        : in  std_logic;                             -- Sinal de clock
        RegWrite_i   : in  std_logic;                             -- Habilita escrita no banco de registradores
        ReadAddr1_i  : in  std_logic_vector(4 downto 0);          -- Endereço do primeiro registrador a ser lido (0-31) rs1
        ReadAddr2_i  : in  std_logic_vector(4 downto 0);          -- Endereço do segundo registrador a ser lido (0-31) rs2
        WriteAddr_i  : in  std_logic_vector(4 downto 0);          -- Endereço do registrador a ser escrito (0-31) rd
        WriteData_i  : in  std_logic_vector(31 downto 0);         -- Dados a serem escritos no registrador

        -- Saídas
        ReadData1_o  : out std_logic_vector(31 downto 0);         -- Dados lidos do primeiro registrador
        ReadData2_o  : out std_logic_vector(31 downto 0)          -- Dados lidos do segundo registrador

    );

end entity reg_file;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da banco de registradores
-------------------------------------------------------------------------------------------------------------------

architecture rtl of reg_file is

    -- Definimos um novo TIPO de dado: um array de 32 elementos (0 a 31),
    -- onde cada elemento é um vetor de 32 bits.
    type t_reg_array is array (0 to 31) of std_logic_vector(31 downto 0);

    -- Sinal interno que representa o banco de registradores
    signal s_registers : t_reg_array := (others => (others => '0'));

begin

    -- A ABI (Application Binary Interface) da RISC-V define o registrador x0 como zero.
    -- ABI Mnemonic: zero | Register: x0  | Hard-wired to zero | Usage: Constant zero
    -- Portanto, qualquer tentativa de escrever no registrador 0 deve ser ignorada.
    -- Zero register é uma técnica comum em arquiteturas RISC para simplificar operações,
    -- como evitar a necessidade de carregar o valor zero de memória.

    -- Vide: RISC-V ABIs Specification (p. 6 - Integer Register Convention)

    -- Porta de Leitura 1 (para rs1)
    -- Se o endereço for "00000", a saída é zero. Senão, leia do nosso array.
    ReadData1_o <= x"00000000" when ReadAddr1_i = "00000" else
                s_registers(to_integer(unsigned(ReadAddr1_i)));

    -- Porta de Leitura 2 (para rs2)
    ReadData2_o <= x"00000000" when ReadAddr2_i = "00000" else
                s_registers(to_integer(unsigned(ReadAddr2_i)));

    -- Processo síncrono para escrita no banco de registradores
    WRITE: process(clk_i)
    begin

        if rising_edge(clk_i) then

            -- Impede a escrita no registrador zero - x0
            if RegWrite_i = '1' and WriteAddr_i /= "00000" then
                s_registers(to_integer(unsigned(WriteAddr_i))) <= WriteData_i;
            end if;

        end if;

    end process WRITE;

end architecture rtl;

-------------------------------------------------------------------------------------------------------------------