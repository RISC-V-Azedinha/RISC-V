-- ===============================================================================================================================================
--
-- File: lsu.vhd
--
-- ██╗     ███████╗██╗   ██╗
-- ██║     ██╔════╝██║   ██║
-- ██║     ███████╗██║   ██║
-- ██║     ╚════██║██║   ██║
-- ███████╗███████║╚██████╔╝
-- ╚══════╝╚══════╝ ╚═════╝ 
--
-- Descrição: Load Store Unit (Unidade de Carga e Armazenamento).
--      Centraliza o acesso à memória de dados, encapsulando as lógicas
--      de Load (leitura formatada) e Store (escrita formatada/parcial).
--
-- Autor     : [André Maiolini]
-- Data      : [30/12/2025]
--
-- ============+=================================================================================================================================

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadas

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da LOAD-STORE UNIT
-------------------------------------------------------------------------------------------------------------------

entity lsu is
    port (

        -----------------------------------------------------------------------
        -- Interface com o Core (Datapath/Control)
        -----------------------------------------------------------------------
        Addr_i        : in  std_logic_vector(31 downto 0); -- Endereço calculado pela ALU
        WriteData_i   : in  std_logic_vector(31 downto 0); -- Dado para escrita (vem de rs2)
        MemWrite_i    : in  std_logic;                     -- Sinal de controle de escrita (WE)
        Funct3_i      : in  std_logic_vector(2 downto 0);  -- Define o tamanho (Byte, Half, Word) e extensão (Signed/Unsigned)

        -----------------------------------------------------------------------
        -- Interface com a Memória RAM (DMem)
        -----------------------------------------------------------------------
        -- A RAM recebe o endereço diretamente
        DMem_addr_o   : out std_logic_vector(31 downto 0);
        
        -- A RAM fornece o dado lido (necessário tanto para Loads quanto para RMW - Read-Modify-Write - dos Stores)
        DMem_data_i   : in  std_logic_vector(31 downto 0);
        
        -- A LSU entrega o dado formatado para ser escrito na RAM
        DMem_data_o   : out std_logic_vector(31 downto 0);
        
        -- Sinal de escrita repassado (4 bits para seleção de bytes)
        DMem_we_o     : out std_logic_vector(3 downto 0);

        -----------------------------------------------------------------------
        -- Saída para o Datapath (Write Back)
        -----------------------------------------------------------------------
        LoadData_o    : out std_logic_vector(31 downto 0)  -- Dado lido da memória e formatado (Sign/Zero extended)

    );
end entity lsu;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA:Implementação da arquitetura da LOAD-STORE UNIT
-------------------------------------------------------------------------------------------------------------------

architecture rtl of lsu is
    
    -- Sinal auxiliar para os bits menos significativos do endereço (Byte Offset)
    signal s_addr_lsb : std_logic_vector(1 downto 0);

begin

    -- O endereço vai direto para a memória
    DMem_addr_o <= Addr_i;

    -- Extrai os 2 LSBs do endereço para definir alinhamento de Byte/Half
    s_addr_lsb  <= Addr_i(1 downto 0);

    -----------------------------------------------------------------------
    -- Processo para a carga (load) de dados
    -----------------------------------------------------------------------
    
    LOAD_UNIT_PROC: process(DMem_data_i, s_addr_lsb, Funct3_i)

        variable v_byte : std_logic_vector(7 downto 0);
        variable v_half : std_logic_vector(15 downto 0);

    begin

        -- O default é indefinido para ajudar na detecção de bugs
        LoadData_o <= (others => 'X');

        -- Decodifica o tipo de Load usando o campo funct3
        case Funct3_i is

            -- LW (Load Word): a palavra inteira é passada diretamente.
            when c_LW =>
                LoadData_o <= DMem_data_i;

            -- LH (Load Half-word, com extensão de sinal)
            when c_LH =>
                -- Usa o bit 1 do endereço para escolher a metade correta
                case s_addr_lsb(1) is
                    when '0' => v_half := DMem_data_i(15 downto 0);  -- Metade inferior
                    when '1' => v_half := DMem_data_i(31 downto 16); -- Metade superior
                    when others => v_half := (others => 'X');
                end case;
                -- Redimensiona para 32 bits (Signed Extension)
                LoadData_o <= std_logic_vector(resize(signed(v_half), 32));

            -- LHU (Load Half-word, com extensão de zero)
            when c_LHU =>
                case s_addr_lsb(1) is
                    when '0' => v_half := DMem_data_i(15 downto 0);
                    when '1' => v_half := DMem_data_i(31 downto 16);
                    when others => v_half := (others => 'X');
                end case;
                -- Redimensiona para 32 bits (Zero Extension)
                LoadData_o <= std_logic_vector(resize(unsigned(v_half), 32));

            -- LB (Load Byte, com extensão de sinal)
            when c_LB =>
                -- Usa os 2 bits do endereço para escolher o byte correto
                case s_addr_lsb is
                    when "00"   => v_byte := DMem_data_i(7 downto 0);
                    when "01"   => v_byte := DMem_data_i(15 downto 8);
                    when "10"   => v_byte := DMem_data_i(23 downto 16);
                    when "11"   => v_byte := DMem_data_i(31 downto 24);
                    when others => v_byte := (others => 'X');
                end case;
                LoadData_o <= std_logic_vector(resize(signed(v_byte), 32));

            -- LBU (Load Byte, com extensão de zero)
            when c_LBU =>
                case s_addr_lsb is
                    when "00"   => v_byte := DMem_data_i(7 downto 0);
                    when "01"   => v_byte := DMem_data_i(15 downto 8);
                    when "10"   => v_byte := DMem_data_i(23 downto 16);
                    when "11"   => v_byte := DMem_data_i(31 downto 24);
                    when others => v_byte := (others => 'X');
                end case;
                LoadData_o <= std_logic_vector(resize(unsigned(v_byte), 32));

            -- Caso padrão
            when others => LoadData_o <= (others => 'X');

        end case;

    end process LOAD_UNIT_PROC;

    -----------------------------------------------------------------------
    -- Processo para o armazenamento (store) de dados
    -----------------------------------------------------------------------
    -- Usa Byte Enables e alinha o dado de escrita
    
    STORE_UNIT_PROC: process(WriteData_i, s_addr_lsb, Funct3_i, MemWrite_i)
    begin

        -- Valores padrão (sem escrita)
        DMem_we_o   <= (others => '0');
        DMem_data_o <= (others => '0'); -- O valor padrão importa pouco pois o WE estará em 0

        -- Só ativamos os Write Enables se a instrução mandar escrever (MemWrite_i = '1')
        if MemWrite_i = '1' then
            case Funct3_i is

                -- SW (Store Word): Escreve os 4 bytes
                when c_SW =>
                    DMem_we_o   <= "1111";
                    DMem_data_o <= WriteData_i;

                -- SH (Store Half-word): Escreve 2 bytes
                when c_SH =>
                    if s_addr_lsb(1) = '0' then 
                        -- Metade inferior (Bytes 0 e 1)
                        DMem_we_o   <= "0011";
                        DMem_data_o(15 downto 0) <= WriteData_i(15 downto 0);
                    else 
                        -- Metade superior (Bytes 2 e 3)
                        DMem_we_o   <= "1100";
                        DMem_data_o(31 downto 16) <= WriteData_i(15 downto 0);
                    end if;

                -- SB (Store Byte): Escreve 1 byte
                when c_SB =>
                    case s_addr_lsb is
                        when "00" => -- Byte 0
                            DMem_we_o   <= "0001";
                            DMem_data_o(7 downto 0)  <= WriteData_i(7 downto 0);
                        when "01" => -- Byte 1
                            DMem_we_o   <= "0010";
                            DMem_data_o(15 downto 8) <= WriteData_i(7 downto 0);
                        when "10" => -- Byte 2
                            DMem_we_o   <= "0100";
                            DMem_data_o(23 downto 16) <= WriteData_i(7 downto 0);
                        when "11" => -- Byte 3
                            DMem_we_o   <= "1000";
                            DMem_data_o(31 downto 24) <= WriteData_i(7 downto 0);
                        when others => null;
                    end case;

                when others => 
                    -- Instrução inválida ou não implementada, não escreve nada
                    DMem_we_o <= "0000";
            end case;
        end if;

    end process STORE_UNIT_PROC;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------