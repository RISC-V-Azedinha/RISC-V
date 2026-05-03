-------------------------------------------------------------------------------------------------------------------
-- 
-- File: ALU.vhd
--
--    █████╗ ██╗     ██╗   ██╗
--   ██╔══██╗██║     ██║   ██║
--   ███████║██║     ██║   ██║
--   ██╔══██║██║     ██║   ██║
--   ██║  ██║███████╗╚██████╔╝
--   ╚═╝  ╚═╝╚══════╝ ╚═════╝ 
-- 
-- Descrição : Unidade Lógica e Aritmética (ALU) de 32 bits.
--             Realiza operações aritméticas e lógicas básicas
--             a partir de sinais de controle (ALUControl_i).
--
-- Autor     : [André Maiolini]
-- Data      : [14/09/2025] 
--
-------------------------------------------------------------------------------------------------------------------
--
--                    A_i          B_i
--                     |            |
--                     v            v
--                 _________    _________
--                 \        \  /        /
--                  \        \/        /                               ->> Zero_o: flag de zero;
--                   \                /                                ->> A_i, B_i: operandos de entrada;
--   ALUControl_i --> \     ALU      / --> FLAGS (Zero_o)              ->> ALUControl_i: seleção da operação;
--                     \            /                                  ->> Result_o: resultado da operação.
--                      \__________/
--                           |
--                           v
--                        data_out
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadas

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da ALU
-------------------------------------------------------------------------------------------------------------------

entity alu is

    port (

        -- Operandos de entrada (32 bits cada)
        A_i           : in  std_logic_vector(31 downto 0);    
        B_i           : in  std_logic_vector(31 downto 0);

        -- Código de operação da ALU (ex.: 0111 = AND, 0110 = OR, 0000 = ADD, etc.)
        ALUControl_i  : in  std_logic_vector(3 downto 0);     

        -- Saída com resultado da operação
        Result_o      : out std_logic_vector(31 downto 0);    

        -- Flag "Zero": ativo em '1' quando o resultado for igual a zero
        Zero_o        : out std_logic

    );

end entity alu;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da ALU
-------------------------------------------------------------------------------------------------------------------

architecture rtl of alu is

    signal result_int : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- A lista de sensibilidade "all" indica que o processo será executado sempre que qualquer sinal de entrada mudar
    -- Isso é adequado para uma ALU, que deve reagir imediatamente a mudanças nos operandos ou no controle

    OPERATIONS: process(A_i, B_i, ALUControl_i)

        -- Variável para armazenar o resultado temporariamente
        variable v_result : std_logic_vector(31 downto 0);

    begin

        -- O CASE statement para selecionar a operação com base no sinal de controle ALUControl_i
        case ALUControl_i is
        
            -- Operações Aritméticas (usando 'signed')
            when c_ALU_ADD  => v_result := std_logic_vector(signed(A_i) + signed(B_i));  
            when c_ALU_SUB  => v_result := std_logic_vector(signed(A_i) - signed(B_i));  

            -- Comparações (preenchem v_result com 1 ou 0 - ocupando 32 bits)
            when c_ALU_SLT  => 
                if signed(A_i) < signed(B_i) then v_result := std_logic_vector(to_unsigned(1, 32));
                else v_result := std_logic_vector(to_unsigned(0, 32));
                end if;

            when c_ALU_SLTU => 
                if unsigned(A_i) < unsigned(B_i) then v_result := std_logic_vector(to_unsigned(1, 32));
                else v_result := std_logic_vector(to_unsigned(0, 32));
                end if;
            
            -- Operações Lógicas (operam diretamente nos vetores)
            when c_ALU_XOR  => v_result := A_i xor B_i;
            when c_ALU_OR   => v_result := A_i or B_i;
            when c_ALU_AND  => v_result := A_i and B_i;
            
            -- Operações de Shift
            when c_ALU_SLL  => v_result := std_logic_vector(shift_left(unsigned(A_i), to_integer(unsigned(B_i(4 downto 0)))));
            when c_ALU_SRL  => v_result := std_logic_vector(shift_right(unsigned(A_i), to_integer(unsigned(B_i(4 downto 0)))));
            when c_ALU_SRA  => v_result := std_logic_vector(shift_right(signed(A_i), to_integer(unsigned(B_i(4 downto 0)))));

            -- OBS.: 5 bits resulta em um deslocamento completo de 32 bits
            
            -- Caso padrão para códigos de operação não definidos
            when others     => v_result := (others => 'X');                              -- 'X' para indefinido
        
        end case ;

        -- Atribuição do resultado final à saída Result_o
        result_int <= v_result;

    end process OPERATIONS;

    -- Atribuição da flag Zero_o: '1' se o resultado for zero, caso contrário '0'
    Zero_o <= '1' when result_int = x"00000000" else '0';
    
    -- Atribuição do resultado final à saída Result_o
    Result_o <= result_int;

end architecture rtl;

-------------------------------------------------------------------------------------------------------------------