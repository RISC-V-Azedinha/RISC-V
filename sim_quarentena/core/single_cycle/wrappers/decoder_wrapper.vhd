---------------------------------------------------------------------------------------------------
--
-- File: decoder_wrapper.vhd
--
-- Descrição: Wrapper para expor os campos do record 't_decoder' como portas individuais
--            para verificação com COCOTB.
--
---------------------------------------------------------------------------------------------------

-- Inclusão dos módulos necessários
library ieee;
use ieee.std_logic_1164.all;
use work.riscv_isa_pkg.all;

-- A entidade do wrapper para o decoder
entity decoder_wrapper is
    port (
        -- Entrada do opcode
        Opcode_i          : in  std_logic_vector(6 downto 0);
        
        -- Saídas do record t_decoder
        reg_write_o       : out std_logic;
        alu_src_a_o       : out std_logic_vector(1 downto 0);
        alu_src_b_o       : out std_logic;
        mem_to_reg_o      : out std_logic;
        mem_write_o       : out std_logic;
        write_data_src_o  : out std_logic;
        branch_o          : out std_logic;
        jump_o            : out std_logic;
        alu_op_o          : out std_logic_vector(1 downto 0)
    );
end entity decoder_wrapper;

architecture struct of decoder_wrapper is
    
    signal s_decoder : t_decoder;

begin

    -- Instância do DUT original
    DUT: entity work.decoder
        port map (
            Opcode_i  => Opcode_i,
            Decoder_o => s_decoder
        );

    -- Atribuição dos campos do record para as saídas
    reg_write_o      <= s_decoder.reg_write;
    alu_src_a_o      <= s_decoder.alu_src_a;
    alu_src_b_o      <= s_decoder.alu_src_b;
    mem_to_reg_o     <= s_decoder.mem_to_reg;
    mem_write_o      <= s_decoder.mem_write;
    write_data_src_o <= s_decoder.write_data_src;
    branch_o         <= s_decoder.branch;
    jump_o           <= s_decoder.jump;
    alu_op_o         <= s_decoder.alu_op;

end architecture struct;