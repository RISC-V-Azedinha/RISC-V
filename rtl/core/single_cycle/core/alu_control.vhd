-------------------------------------------------------------------------------------------------------------------
-- 
-- File: alu_control.vhd
--
--    █████╗ ██╗     ██╗   ██╗         ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗     
--   ██╔══██╗██║     ██║   ██║        ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║     
--   ███████║██║     ██║   ██║        ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║     
--   ██╔══██║██║     ██║   ██║        ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║     
--   ██║  ██║███████╗╚██████╔╝███████╗╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗
--   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
--                                                                                                                                                                                                                                                           
-- 
-- Descrição : Unidade de Controle da ALU para um processador RISC-V de 32 bits (RV32I).
--             Decodifica o opcode e funct3/funct7 da instrução para gerar o sinal de controle
--             que determina a operação a ser realizada pela ALU.
--
-- Autor     : [André Maiolini]
-- Data      : [14/09/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadass

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da unidade de controle da unidade lógica e aritmética (ALU)
-------------------------------------------------------------------------------------------------------------------

entity alu_control is

  port (
    
    -- Entradas
    ALUOp_i       : in  std_logic_vector(1 downto 0);     -- Código de operação da ALU vindo da control_unit
    Funct3_i      : in  std_logic_vector(2 downto 0);     -- Campo funct3 da instrução (bits [14:12])
    Funct7_i      : in  std_logic_vector(6 downto 0);     -- Campo funct7 da instrução (bits [31:25])

    -- Saídas
    ALUControl_o  : out std_logic_vector(3 downto 0)      -- Sinal de controle da ALU (4 bits)

  ) ;

end alu_control ;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da unidade de controle da unidade lógica e aritmética (ALU)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of alu_control is
begin

    DECODER: process(ALUOp_i, Funct3_i, Funct7_i)
    begin

        -- Valor padrão (default):

            ALUControl_o <= c_ALU_ADD;

        -----------------------------------------------------------------------------------------------------------
        -- NÍVEL 1: Decodificação com base em ALUOp_i
        -----------------------------------------------------------------------------------------------------------

            case ALUOp_i is
            
                -- ================================================================================================
                -- MODO 1: Soma Forçada (Load, Store, LUI, AUIPC, JAL, JALR)
                -- ================================================================================================

                    when "00" => ALUControl_o <= c_ALU_ADD ;

                -- ================================================================================================
                -- MODO 2: Branches (Decodificação Específica para Comparação)
                -- ================================================================================================

                    when "01" =>

                        -------------------------------------------------------------------------------------------
                        -- NÍVEL 2: Decodificação com base em funct3
                        -------------------------------------------------------------------------------------------

                        case Funct3_i is
                            
                            when "000" | "001" => ALUControl_o <= c_ALU_SUB;   -- BEQ, BNE (subtração)
                            when "100" | "101" => ALUControl_o <= c_ALU_SLT;   -- BLT, BGE (usa SLT ao invés de SUB) 
                            when "110" | "111" => ALUControl_o <= c_ALU_SLTU;  -- BLTU, BGEU (sinalizado)
                            when others => ALUControl_o <= c_ALU_ADD;          -- Valor padrão (default)
                        
                        end case;

                -- ================================================================================================
                -- MODO 3: R-Type ("10") e I-Type ("11") 
                -- ================================================================================================

                when "10" | "11" =>
                    case Funct3_i is
                        
                        -- ADD / SUB
                        when "000" => 
                            -- Apenas R-Type ("10") suporta SUB via bit 30 (Funct7 bit 5)
                            if ALUOp_i = "10" and Funct7_i(5) = '1' then
                                ALUControl_o <= c_ALU_SUB;
                            else
                                ALUControl_o <= c_ALU_ADD; -- I-Type (ADDI) é sempre ADD
                            end if;

                        -- Shifts e Lógica
                        when "001" => ALUControl_o <= c_ALU_SLL;  -- SLL / SLLI
                        when "010" => ALUControl_o <= c_ALU_SLT;  -- SLT / SLTI
                        when "011" => ALUControl_o <= c_ALU_SLTU; -- SLTU / SLTIU
                        when "100" => ALUControl_o <= c_ALU_XOR;  -- XOR / XORI
                        when "110" => ALUControl_o <= c_ALU_OR;   -- OR  / ORI
                        when "111" => ALUControl_o <= c_ALU_AND;  -- AND / ANDI

                        -- Shift Right (Lógico/Aritmético)
                        when "101" => 
                            -- Tanto R quanto I suportam troca de SRL/SRA via bit 30
                            if Funct7_i(5) = '1' then
                                ALUControl_o <= c_ALU_SRA; -- SRA / SRAI
                            else
                                ALUControl_o <= c_ALU_SRL; -- SRL / SRLI
                            end if;

                        when others => ALUControl_o <= c_ALU_ADD;
                    end case;

                -- ================================================================================================
                -- MODO 4: Default (Não Utilizado) 
                -- ================================================================================================

                    when others => ALUControl_o <= c_ALU_ADD;
            
            end case ;

    end process DECODER;

end rtl ; -- rtl

-------------------------------------------------------------------------------------------------------------------