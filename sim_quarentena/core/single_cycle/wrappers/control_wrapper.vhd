---------------------------------------------------------------------------------------------------
-- File: control_wrapper.vhd
-- Descrição: Wrapper para expor os campos do record 't_control' como portas individuais.
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.riscv_isa_pkg.all;

entity control_wrapper is
    port (
        -- Entradas do Datapath
        Instruction_i     : in  std_logic_vector(31 downto 0);
        ALU_Zero_i        : in  std_logic;
        
        -- Saídas do record t_control (Sinais de Controle)
        reg_write_o       : out std_logic;
        alu_src_a_o       : out std_logic_vector(1 downto 0);
        alu_src_b_o       : out std_logic;
        mem_to_reg_o      : out std_logic;
        mem_write_o       : out std_logic;
        write_data_src_o  : out std_logic;
        pcsrc_o           : out std_logic_vector(1 downto 0);
        alucontrol_o      : out std_logic_vector(3 downto 0)
    );
end entity control_wrapper;

architecture struct of control_wrapper is
    signal s_control : t_control;
begin

    -- Instância da Unidade de Controle Original
    DUT: entity work.control
        port map (
            Instruction_i => Instruction_i,
            ALU_Zero_i    => ALU_Zero_i,
            Control_o     => s_control
        );

    -- Decomposição do record para saídas individuais
    reg_write_o      <= s_control.reg_write;
    alu_src_a_o      <= s_control.alu_src_a;
    alu_src_b_o      <= s_control.alu_src_b;
    mem_to_reg_o     <= s_control.mem_to_reg;
    mem_write_o      <= s_control.mem_write;
    write_data_src_o <= s_control.write_data_src;
    pcsrc_o          <= s_control.pcsrc;
    alucontrol_o     <= s_control.alucontrol;

end architecture struct;