---------------------------------------------------------------------------------------------------
-- File: control_wrapper.vhd
-- Descrição: Wrapper para a Unidade de Controle. Desempacota o record 't_control' de saída
--            em sinais individuais (std_logic) para facilitar a leitura no Cocotb/GHDL.
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.riscv_uarch_pkg.all;

entity control_wrapper is
    port (
        Clk_i             : in  std_logic;
        Reset_i           : in  std_logic;
        imem_rdy_i        : in  std_logic;
        imem_vld_o        : out std_logic;
        dmem_rdy_i        : in  std_logic;
        dmem_vld_o        : out std_logic;
        Instruction_i     : in  std_logic_vector(31 downto 0);
        ALU_Zero_i        : in  std_logic;

        soc_en_i          : in  std_logic;
        is_fetch_stage_o  : out std_logic;

        CSR_Mstatus_MIE_i : in std_logic;
        CSR_Mie_i         : in std_logic_vector(31 downto 0);
        CSR_Mip_i         : in std_logic_vector(31 downto 0);
        Csr_Valid_i       : in  std_logic;

        -- Sinais de Controle Desempacotados (Saídas planas para o Testbench)
        Ctrl_pc_write_o   : out std_logic;
        Ctrl_opc_write_o  : out std_logic;
        Ctrl_ir_write_o   : out std_logic;
        Ctrl_mem_write_o  : out std_logic;
        Ctrl_reg_write_o  : out std_logic;
        Ctrl_rs1_write_o  : out std_logic;
        Ctrl_rs2_write_o  : out std_logic;
        Ctrl_alur_write_o : out std_logic;
        Ctrl_mdr_write_o  : out std_logic;
        Ctrl_csr_write_o  : out std_logic;
        Ctrl_trap_enter_o : out std_logic;
        Ctrl_trap_return_o: out std_logic;
        Ctrl_trap_cause_o : out std_logic_vector(31 downto 0);
        Ctrl_pc_src_o     : out std_logic_vector(1 downto 0);
        Ctrl_alu_src_a_o  : out std_logic_vector(1 downto 0);
        Ctrl_alu_src_b_o  : out std_logic;
        Ctrl_wb_sel_o     : out std_logic_vector(1 downto 0);
        Ctrl_alu_control_o: out std_logic_vector(3 downto 0)
    );
end entity;

architecture struct of control_wrapper is
    signal s_control : t_control;
begin

    -- Instancia a Unidade de Controle Verdadeira
    DUT: entity work.control
    port map (
        Clk_i             => Clk_i,
        Reset_i           => Reset_i,
        imem_rdy_i        => imem_rdy_i,
        imem_vld_o        => imem_vld_o,
        dmem_rdy_i        => dmem_rdy_i,
        dmem_vld_o        => dmem_vld_o,
        Instruction_i     => Instruction_i,
        ALU_Zero_i        => ALU_Zero_i,
        Control_o         => s_control,
        soc_en_i          => soc_en_i,
        is_fetch_stage_o  => is_fetch_stage_o,
        CSR_Mstatus_MIE_i => CSR_Mstatus_MIE_i,
        CSR_Mie_i         => CSR_Mie_i,
        CSR_Mip_i         => CSR_Mip_i,
        Csr_Valid_i       => Csr_Valid_i
    );

    -- Desempacota o record de saída para os pinos do Wrapper
    Ctrl_pc_write_o   <= s_control.pc_write;
    Ctrl_opc_write_o  <= s_control.opc_write;
    Ctrl_ir_write_o   <= s_control.ir_write;
    Ctrl_mem_write_o  <= s_control.mem_write;
    Ctrl_reg_write_o  <= s_control.reg_write;
    Ctrl_rs1_write_o  <= s_control.rs1_write;
    Ctrl_rs2_write_o  <= s_control.rs2_write;
    Ctrl_alur_write_o <= s_control.alur_write;
    Ctrl_mdr_write_o  <= s_control.mdr_write;
    Ctrl_csr_write_o  <= s_control.csr_write;
    Ctrl_trap_enter_o <= s_control.trap_enter;
    Ctrl_trap_return_o<= s_control.trap_return;
    Ctrl_trap_cause_o <= s_control.trap_cause;
    Ctrl_pc_src_o     <= s_control.pc_src;
    Ctrl_alu_src_a_o  <= s_control.alu_src_a;
    Ctrl_alu_src_b_o  <= s_control.alu_src_b;
    Ctrl_wb_sel_o     <= s_control.wb_sel;
    Ctrl_alu_control_o<= s_control.alu_control;

end architecture;