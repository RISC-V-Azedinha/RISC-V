------------------------------------------------------------------------------------------------------------------
-- 
-- File: decoder.vhd
--
--   ██████╗ ███████╗ ██████╗ ██████╗ ██████╗ ███████╗██████╗ 
--   ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗
--   ██║  ██║█████╗  ██║     ██║   ██║██║  ██║█████╗  ██████╔╝
--   ██║  ██║██╔══╝  ██║     ██║   ██║██║  ██║██╔══╝  ██╔══██╗
--   ██████╔╝███████╗╚██████╗╚██████╔╝██████╔╝███████╗██║  ██║
--   ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝                                                                                                                                                           
-- 
-- Descrição : Unidade de Decodificação para um processador RISC-V de 32 bits (RV32I).
--             Decodifica o opcode da instrução e gera os sinais de controle
--             necessários para a operação correta do datapath.
--
-- Autor     : [André Maiolini]
-- Data      : [14/09/2025]
--
-------------------------------------------------------------------------------------------------------------------
--
-- IMPORTANTE: 
--  - O "opcode" indica apeenas a CATEGORIA (formato) da instrução.
--  - A operação exata (ex: ADD vs SUB, AND vs OR) é definida em outro nível,
--    usando os campos funct3 e funct7.
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadas
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da unidade decodificadora
-------------------------------------------------------------------------------------------------------------------

entity decoder is

  port (
    
    -- Entradas
    Opcode_i      : in  std_logic_vector(6 downto 0);    -- Opcode da instrução (bits [6:0])

    -- Saídas
    Decoder_o     : out t_decoder                        -- Record com todos os sinais de controle

  ) ;

end decoder ;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da unidade decodificadora
-------------------------------------------------------------------------------------------------------------------

architecture rtl of decoder is

    ---------------------------------------------------------------------------------------------------------------
    --
    -- MAPA DE FORMATOS DO RV32I
    --
    -- - Cada instrução pertence a um "formato" definido pelo campo OPCODE (7 bits).
    -- 
    -- - Formato R (registrador-registrador): operações aritméticas/lógicas
    --     opcode = 0110011
    --
    -- - Formato I (imediato): operações com imediato, loads, JALR
    --     opcode = 0010011 (I-type aritmético: ADDI, ANDI, ORI, ...)
    --     opcode = 0000011 (LOAD: LB, LH, LW, LBU, LHU)
    --     opcode = 1100111 (JALR)
    --
    -- - Formato S (store): operações de armazenamento na memória
    --     opcode = 0100011 (SB, SH, SW)
    --
    -- - Formato B (branch): desvios condicionais
    --     opcode = 1100011 (BEQ, BNE, BLT, ...)
    --
    -- - Formato U (upper immediate): imediato de 20 bits
    --     opcode = 0110111 (LUI)
    --     opcode = 0010111 (AUIPC)
    --
    -- - Formato J (jump): salto incondicional
    --     opcode = 1101111 (JAL)
    ---------------------------------------------------------------------------------------------------------------

begin

    --------------------------------------------------------------------------------------------------------------
    -- Processo de decodificação do OPCODE
    -- 
    -- Observação: alu_op é um código "resumido":
    --
    --   "00" → operações de soma (load/store, endereçamento, jalr, auipc)
    --   "01" → operações de comparação (branch)
    --   "10" → operações R-type (ADD, SUB, AND, OR, etc.)
    --   "11" → operações I-type aritméticas (ADDI, ANDI, ORI, etc.)
    --
    -- A distinção final é feita no módulo ALUControl, usando funct3/funct7.
    --
    --------------------------------------------------------------------------------------------------------------

    DECODING : process(Opcode_i)
    begin

        -- Valores padrão (NOP)
        Decoder_o <= c_DECODER_NOP;

        case Opcode_i is

            -- ===================================================================================================
            -- Formato R (ex: ADD, SUB...)
            -- ===================================================================================================
            when c_OPCODE_R_TYPE =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_b            <= '0' ;
                Decoder_o.alu_op               <= "10";

            -- ===================================================================================================
            -- Formato I (imediato ALU)
            -- ===================================================================================================
            when c_OPCODE_I_TYPE =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.alu_op               <= "11";

            -- ===================================================================================================
            -- LOAD (ex: LW)
            -- ===================================================================================================
            when c_OPCODE_LOAD =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.wb_src               <= "01"; -- write back data vem da memória (LSU)
                Decoder_o.alu_op               <= "00"; -- soma para endereçamento

            -- ===================================================================================================
            -- STORE (ex: SW)
            -- ===================================================================================================
            when c_OPCODE_STORE =>
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.mem_write            <= '1' ;
                Decoder_o.alu_op               <= "00"; -- soma para endereçamento

            -- ===================================================================================================
            -- BRANCH (ex: BEQ)
            -- ===================================================================================================
            when c_OPCODE_BRANCH =>
                Decoder_o.branch               <= '1' ;
                Decoder_o.alu_op               <= "01"; -- subtração para comparação

            -- ===================================================================================================
            -- JUMP (JAL)
            -- ===================================================================================================
            when c_OPCODE_JAL =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.wb_src               <= "10"; -- grava PC+4 no rd
                Decoder_o.jump                 <= '1' ;

            -- ===================================================================================================
            -- JUMP (JALR)
            -- ===================================================================================================
            when c_OPCODE_JALR =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.wb_src               <= "10"; -- grava PC+4 no rd
                Decoder_o.jump                 <= '1' ;
                Decoder_o.alu_op               <= "00";

            -- ===================================================================================================
            -- U-Type (LUI, AUIPC)
            -- ===================================================================================================
            when c_OPCODE_LUI =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_a            <= "10"; 
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.alu_op               <= "00";
                Decoder_o.wb_src               <= "00"; -- vem da ALU (0 + Imm)

            when c_OPCODE_AUIPC =>
                Decoder_o.reg_write            <= '1' ;
                Decoder_o.alu_src_a            <= "01"; 
                Decoder_o.alu_src_b            <= '1' ;
                Decoder_o.alu_op               <= "00";
                Decoder_o.wb_src               <= "00"; -- vem da ALU (PC + Imm)

            -- ===================================================================================================
            -- OPCODE desconhecido → NOP
            -- ===================================================================================================
            when others => null; -- mantém os valores padrão (NOP)

        end case;
        
    end process DECODING;

end architecture rtl;

-------------------------------------------------------------------------------------------------------------------