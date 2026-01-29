------------------------------------------------------------------------------------------------------------------
-- 
-- File: riscv_isa_pkg.vhd
--
-- ██╗███████╗ █████╗ 
-- ██║██╔════╝██╔══██╗
-- ██║███████╗███████║
-- ██║╚════██║██╔══██║
-- ██║███████║██║  ██║
-- ╚═╝╚══════╝╚═╝  ╚═╝                                                                                                                                                       
-- 
-- Descrição : Pacote que carrega as especificações para arquitetura RISC-V.
--      Inclui constantes para OPCODES, FUNCT3 e FUNCT7, além de constantes para
--      seleções de operações na ALU e de LOAD/STORE.
--
-- Autor     : [André Maiolini]
-- Data      : [25/12/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)

-------------------------------------------------------------------------------------------------------------------
-- PACOTE: Definição do pacote de especificação ISA do RISC-V
-------------------------------------------------------------------------------------------------------------------

package riscv_isa_pkg is

    -- === Opcodes (RV32I) ===
    -- Constantes para os opcodes das instruções RISC-V

    constant c_OPCODE_R_TYPE : std_logic_vector(6 downto 0) := "0110011";        -- Operações entre registradores
    constant c_OPCODE_I_TYPE : std_logic_vector(6 downto 0) := "0010011";        -- Operações imediato
    constant c_OPCODE_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant c_OPCODE_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant c_OPCODE_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant c_OPCODE_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant c_OPCODE_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant c_OPCODE_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant c_OPCODE_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant c_OPCODE_SYSTEM : std_logic_vector(6 downto 0) := "1110011";
    constant c_OPCODE_FENCE  : std_logic_vector(6 downto 0) := "0001111";

    -- === Funct3 (ALU/Branch/Mem) ===
    
    constant c_FUNCT3_BEQ  : std_logic_vector(2 downto 0) := "000";
    constant c_FUNCT3_BNE  : std_logic_vector(2 downto 0) := "001";
    constant c_FUNCT3_BLT  : std_logic_vector(2 downto 0) := "100";
    constant c_FUNCT3_BGE  : std_logic_vector(2 downto 0) := "101";
    constant c_FUNCT3_BLTU : std_logic_vector(2 downto 0) := "110";
    constant c_FUNCT3_BGEU : std_logic_vector(2 downto 0) := "111";

    -- === Funct3 (Load/Store Unit) ===
    -- Constantes para os valores de funct3 para as instruções de Load

    constant c_LB  : std_logic_vector(2 downto 0) := "000";                      -- Load Byte (com sinal)
    constant c_LH  : std_logic_vector(2 downto 0) := "001";                      -- Load Half-word (com sinal)
    constant c_LW  : std_logic_vector(2 downto 0) := "010";                      -- Load Word
    constant c_LBU : std_logic_vector(2 downto 0) := "100";                      -- Load Byte Unsigned (sem sinal)
    constant c_LHU : std_logic_vector(2 downto 0) := "101";                      -- Load Half-word Unsigned (sem sinal)

    -- Constantes para os valores de funct3 para as intruções de store

    constant c_SB : std_logic_vector(2 downto 0) := "000";                       -- Store Byte
    constant c_SH : std_logic_vector(2 downto 0) := "001";                       -- Store Half-word
    constant c_SW : std_logic_vector(2 downto 0) := "010";                       -- Store Word

    -- === Funct3 (System) ===

    constant c_FUNCT3_PRIV  : std_logic_vector(2 downto 0) := "000";             -- Traps (ECALL, EBREAK...)
    constant c_FUNCT3_CSRRW : std_logic_vector(2 downto 0) := "001";             -- CSR Read/Write

    -- === Funct12 (ECALL/EBRAK) ===
    -- O campo 'Immediate' (bits 31-20) usado como código. Funct7 é utilizado em R-Type

    constant c_FUNCT12_ECALL  : std_logic_vector(11 downto 0) := "000000000000"; -- 0x000
    constant c_FUNCT12_EBREAK : std_logic_vector(11 downto 0) := "000000000001"; -- 0x001
    constant c_FUNCT12_MRET   : std_logic_vector(11 downto 0) := "001100000010"; -- 0x302

    -- === ALU Operations (Interno) ===
    -- Constantes para os códigos de operação da ALU (4 bits)

    constant c_ALU_ADD  : std_logic_vector(3 downto 0) := "0000";
    constant c_ALU_SUB  : std_logic_vector(3 downto 0) := "1000";
    constant c_ALU_SLT  : std_logic_vector(3 downto 0) := "0010";
    constant c_ALU_SLTU : std_logic_vector(3 downto 0) := "0011";
    constant c_ALU_XOR  : std_logic_vector(3 downto 0) := "0100";
    constant c_ALU_OR   : std_logic_vector(3 downto 0) := "0110";
    constant c_ALU_AND  : std_logic_vector(3 downto 0) := "0111";
    constant c_ALU_SLL  : std_logic_vector(3 downto 0) := "0001";
    constant c_ALU_SRL  : std_logic_vector(3 downto 0) := "0101";
    constant c_ALU_SRA  : std_logic_vector(3 downto 0) := "1101";

end package riscv_isa_pkg;