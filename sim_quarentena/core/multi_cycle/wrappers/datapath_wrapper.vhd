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

        -- Sinais de Controle Provisórios (teste da FSM)
        PCWrite_i          : in  std_logic;
        OPCWrite_i         : in  std_logic;
        IRWrite_i          : in  std_logic;
        RS1Write_i         : in  std_logic;
        RS2Write_i         : in  std_logic;
        ALUWrite_i         : in  std_logic;
        MDRWrite_i         : in  std_logic;

        -- Saídas de Status
        Instruction_o       : out std_logic_vector(31 downto 0);
        ALU_Zero_o          : out std_logic;

        -- Debug / Monitor (espelha a interface do datapath)

        DBG_pc_next_o      : out std_logic_vector(31 downto 0);       -- Próximo PC
        DBG_instruction_o  : out std_logic_vector(31 downto 0);       -- Instrução atual
        DBG_rs1_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs1
        DBG_rs2_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs2
        DBG_alu_result_o   : out std_logic_vector(31 downto 0);       -- Resultado da ALU
        DBG_write_back_o   : out std_logic_vector(31 downto 0);       -- Dados escritos de volta no banco de registradores
        DBG_alu_zero_o     : out std_logic;                           -- Flag Zero da ALU
        DBG_r_pc_o         : out std_logic_vector(31 downto 0);       -- PC atual
        DBG_r_opc_o        : out std_logic_vector(31 downto 0);       -- OldPC atual
        DBG_r_ir_o         : out std_logic_vector(31 downto 0);       -- IR atual
        DBG_r_rs1_o        : out std_logic_vector(31 downto 0);       -- RS1 atual
        DBG_r_rs2_o        : out std_logic_vector(31 downto 0);       -- RS2 atual 
        DBG_r_alu_o        : out std_logic_vector(31 downto 0);       -- ALUResult atual
        DBG_r_MDR_o        : out std_logic_vector(31 downto 0)        -- MDR atual

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
            DBG_pc_next_o       => DBG_pc_next_o,
            DBG_instruction_o   => DBG_instruction_o,
            DBG_rs1_data_o      => DBG_rs1_data_o,
            DBG_rs2_data_o      => DBG_rs2_data_o,
            DBG_alu_result_o    => DBG_alu_result_o,
            DBG_write_back_o    => DBG_write_back_o,
            DBG_alu_zero_o      => DBG_alu_zero_o,
            DBG_r_pc_o          => DBG_r_pc_o,
            DBG_r_opc_o         => DBG_r_opc_o,
            DBG_r_ir_o          => DBG_r_ir_o,
            DBG_r_rs1_o         => DBG_r_rs1_o,
            DBG_r_rs2_o         => DBG_r_rs2_o,
            DBG_r_alu_o         => DBG_r_alu_o,
            DBG_r_MDR_o         => DBG_r_mdr_o,  
            PCWrite_i           => PCWrite_i,
            OPCWrite_i          => OPCWrite_i,
            IRWrite_i           => IRWrite_i,
            RS1Write_i          => RS1Write_i,
            RS2Write_i          => RS2Write_i,
            ALUWrite_i          => ALUWrite_i,
            MDRWrite_i          => MDRWrite_i
        );

end architecture struct;