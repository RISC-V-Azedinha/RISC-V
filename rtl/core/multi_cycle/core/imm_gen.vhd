------------------------------------------------------------------------------------------------------------------
-- 
-- File: imm_gen.vhd
--   
--   ██╗███╗   ███╗███╗   ███╗         ██████╗ ███████╗███╗   ██╗
--   ██║████╗ ████║████╗ ████║        ██╔════╝ ██╔════╝████╗  ██║
--   ██║██╔████╔██║██╔████╔██║        ██║  ███╗█████╗  ██╔██╗ ██║
--   ██║██║╚██╔╝██║██║╚██╔╝██║        ██║   ██║██╔══╝  ██║╚██╗██║
--   ██║██║ ╚═╝ ██║██║ ╚═╝ ██║███████╗╚██████╔╝███████╗██║ ╚████║
--   ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝
--                                                               
-- Descrição : O gerador de imediatos extrai e estende o valor imediato
--             de instruções RISC-V de 32 bits, suportando os formatos
--             I, S, B, U e J.
--
-- Autor     : [André Maiolini]
-- Data      : [14/09/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadas

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do gerador de imediatos
-------------------------------------------------------------------------------------------------------------------

entity imm_gen is

    port (

        -- Entrada: instrução de 32 bits
        Instruction_i : in  std_logic_vector(31 downto 0);    

        -- Saída: valor imediato estendido para 32 bits
        Immediate_o   : out std_logic_vector(31 downto 0)     

    );

end entity imm_gen;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do Gerador de Imediatos (IMM_GEN)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of imm_gen is
begin

    -- Formatos de instrução RISC-V:

    -- - R-Type: não possui imediato
    -- -- [ funct7 | rs2 | rs1 | funct3 | rd | opcode ]
    
    -- - I-Type: bits [31:20] 
    -- -- [ imm[11:0] | rs1 | funct3 | rd | opcode ]

    -- - S-Type: bits [31:25] e [11:7] 
    -- -- [ imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode ]

    -- - B-Type: bits [31], [7], [30:25], [11:8] 
    -- -- [ imm[12|10:5] | rs2 | rs1 | funct3 | imm[4:1|11] | opcode ]

    -- - U-Type: bits [31:12] 
    -- -- [ imm[31:12] | rd | opcode ]

    -- - J-Type: bits [31], [19:12], [20], [30:21] 
    -- -- [ imm[20|10:1|11|19:12] | rd | opcode ]

    -- Processo combinacional ÚNICO para toda a lógica
    IMM_GEN_PROCESS: process(Instruction_i)

        -- Variável para o imediato de 12 bits (Formatos I e S)
        variable v_imm12 : std_logic_vector(11 downto 0);

        -- Variável para o imediato de 13 bits (Formato B)
        variable v_imm13 : std_logic_vector(12 downto 0);

        -- Variável para o imediato de 21 bits (Formato J)
        variable v_imm21 : std_logic_vector(20 downto 0);

    begin
        
        case Instruction_i(6 downto 0) is

            -- Formato I: LOAD, IMM, JALR
            when c_OPCODE_LOAD | c_OPCODE_I_TYPE | c_OPCODE_JALR =>
                v_imm12 := Instruction_i(31 downto 20);
                Immediate_o <= std_logic_vector(resize(signed(v_imm12), 32));

            -- Formato S: STORE
            when c_OPCODE_STORE =>
                v_imm12 := Instruction_i(31 downto 25) & Instruction_i(11 downto 7);
                Immediate_o <= std_logic_vector(resize(signed(v_imm12), 32));

            -- Formato B: BRANCH
            when c_OPCODE_BRANCH =>
                v_imm13 := Instruction_i(31) & Instruction_i(7) & Instruction_i(30 downto 25) & Instruction_i(11 downto 8) & '0';
                Immediate_o <= std_logic_vector(resize(signed(v_imm13), 32));

                -- A especificação RISC-V foi projetada para suportar a extensão de instruções comprimidas ('C'), que têm 16 bits 
                -- (2 bytes). Isso significa que o alinhamento mínimo garantido para QUALQUER instrução é de 2 bytes. Consequentemente, 
                -- o endereço de qualquer instrução válida é sempre par, o que garante que o bit menos significativo (LSB, bit 0) do 
                -- endereço é SEMPRE '0'.

            -- Formato U: LUI, AUIPC
            when c_OPCODE_LUI | c_OPCODE_AUIPC =>
                Immediate_o <= Instruction_i(31 downto 12) & x"000";

                -- As instruções do Tipo-U (LUI e AUIPC) são projetadas para construir constantes
                -- de 32 bits. A definição da instrução 'LUI' (Load Upper Immediate), por exemplo,
                -- é: "carregar um valor de 20 bits nos 20 bits MAIS significativos de um
                -- registrador e preencher os 12 bits MENOS significativos com zeros".

            -- Formato J: JAL
            when c_OPCODE_JAL =>
                v_imm21 := Instruction_i(31) & Instruction_i(19 downto 12) & Instruction_i(20) & Instruction_i(30 downto 21) & '0';
                Immediate_o <= std_logic_vector(resize(signed(v_imm21), 32));

            -- Caso padrão para instruções que não usam imediato (como Tipo-R)
            when others =>
                Immediate_o <= (others => '0');

        end case;
        
    end process IMM_GEN_PROCESS;

end architecture rtl;

-------------------------------------------------------------------------------------------------------------------