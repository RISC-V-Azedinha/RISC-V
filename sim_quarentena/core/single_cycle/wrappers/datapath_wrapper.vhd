---------------------------------------------------------------------------------------------------
-- File: datapath_wrapper.vhd
-- Descrição: Wrapper para o Datapath. Decompõe o record 't_control' em entradas individuais
--            e expõe sinais internos para monitoramento no testbench.
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

entity datapath_wrapper is
    port (
        CLK_i               : in  std_logic;
        Reset_i             : in  std_logic;

        -- Memória
        IMem_addr_o         : out std_logic_vector(31 downto 0);
        IMem_data_i         : in  std_logic_vector(31 downto 0);
        DMem_addr_o         : out std_logic_vector(31 downto 0);
        DMem_data_o         : out std_logic_vector(31 downto 0);
        DMem_data_i         : in  std_logic_vector(31 downto 0);
        DMem_writeEnable_o  : out std_logic;

        -- Sinais de Controle (Decompostos do record t_control)
        reg_write_i         : in  std_logic;
        alu_src_a_i         : in  std_logic_vector(1 downto 0);
        alu_src_b_i         : in  std_logic;
        mem_write_i         : in  std_logic;
        wb_src_i            : in  std_logic_vector(1 downto 0);
        pcsrc_i             : in  std_logic_vector(1 downto 0);
        alucontrol_i        : in  std_logic_vector(3 downto 0);

        -- Saídas de Status
        Instruction_o       : out std_logic_vector(31 downto 0);
        ALU_Zero_o          : out std_logic;

        
        -- Debug / Monitor (espelha a interface do datapath)
        dbg_pc_current_o   : out std_logic_vector(31 downto 0);
        dbg_pc_next_o      : out std_logic_vector(31 downto 0);
        dbg_instruction_o  : out std_logic_vector(31 downto 0);
        dbg_rs1_data_o     : out std_logic_vector(31 downto 0);
        dbg_rs2_data_o     : out std_logic_vector(31 downto 0);
        dbg_alu_result_o   : out std_logic_vector(31 downto 0);
        dbg_write_back_o   : out std_logic_vector(31 downto 0);
        dbg_alu_zero_o     : out std_logic

    );
end entity datapath_wrapper;

architecture struct of datapath_wrapper is

    -- Sinal interno para o record de controle
    signal s_control : t_control;

begin

    -- Empacota as entradas individuais no record esperado pelo datapath
    s_control.reg_write      <= reg_write_i;
    s_control.alu_src_a      <= alu_src_a_i;
    s_control.alu_src_b      <= alu_src_b_i;
    s_control.mem_write      <= mem_write_i;
    s_control.wb_src         <= wb_src_i;
    s_control.pcsrc          <= pcsrc_i;
    s_control.alucontrol     <= alucontrol_i;

    -- Instância do Datapath
    DUT: entity work.datapath
        generic map (
            DEBUG_EN => true
        )
        port map (
            CLK_i               => CLK_i,
            Reset_i             => Reset_i,
            IMem_addr_o         => IMem_addr_o,
            IMem_data_i         => IMem_data_i,
            DMem_addr_o         => DMem_addr_o,
            DMem_data_o         => DMem_data_o,
            DMem_data_i         => DMem_data_i,
            DMem_writeEnable_o  => DMem_writeEnable_o,
            Control_i           => s_control,
            Instruction_o       => Instruction_o,
            ALU_Zero_o          => ALU_Zero_o,
            DBG_pc_current_o    => dbg_pc_current_o,
            DBG_pc_next_o       => dbg_pc_next_o,
            DBG_instruction_o   => dbg_instruction_o,
            DBG_rs1_data_o      => dbg_rs1_data_o,
            DBG_rs2_data_o      => dbg_rs2_data_o,
            DBG_alu_result_o    => dbg_alu_result_o,
            DBG_write_back_o    => dbg_write_back_o,
            DBG_alu_zero_o      => dbg_alu_zero_o
        );

end architecture struct;