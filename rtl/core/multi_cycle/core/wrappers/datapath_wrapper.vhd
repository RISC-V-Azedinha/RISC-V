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
        DMem_writeEnable_o  : out std_logic_vector(3 downto 0); 

        -- Sinais de Controle (Decompostos do record t_control)
        reg_write_i         : in  std_logic;
        alu_src_a_i         : in  std_logic_vector(1 downto 0);
        alu_src_b_i         : in  std_logic;
        mem_write_i         : in  std_logic;
        wb_src_i            : in  std_logic_vector(1 downto 0);
        pcsrc_i             : in  std_logic_vector(1 downto 0);
        alucontrol_i        : in  std_logic_vector(3 downto 0);

        -- Sinais de Controle Provisórios (teste da FSM)
        PCWrite_i           : in  std_logic;
        OPCWrite_i          : in  std_logic;
        IRWrite_i           : in  std_logic;
        RS1Write_i          : in  std_logic;
        RS2Write_i          : in  std_logic;
        ALUWrite_i          : in  std_logic;
        MDRWrite_i          : in  std_logic;

        -- Saídas de Status
        Instruction_o       : out std_logic_vector(31 downto 0);
        ALU_Zero_o          : out std_logic;

        -- Debug / Monitor (espelha a interface do datapath)
        DBG_pc_next_o       : out std_logic_vector(31 downto 0);        
        DBG_instruction_o   : out std_logic_vector(31 downto 0);        
        DBG_rs1_data_o      : out std_logic_vector(31 downto 0);        
        DBG_rs2_data_o      : out std_logic_vector(31 downto 0);        
        DBG_alu_result_o    : out std_logic_vector(31 downto 0);        
        DBG_write_back_o    : out std_logic_vector(31 downto 0);        
        DBG_alu_zero_o      : out std_logic;                            
        DBG_r_pc_o          : out std_logic_vector(31 downto 0);        
        DBG_r_opc_o         : out std_logic_vector(31 downto 0);        
        DBG_r_ir_o          : out std_logic_vector(31 downto 0);        
        DBG_r_rs1_o         : out std_logic_vector(31 downto 0);        
        DBG_r_rs2_o         : out std_logic_vector(31 downto 0);        
        DBG_r_alu_o         : out std_logic_vector(31 downto 0);        
        DBG_r_MDR_o         : out std_logic_vector(31 downto 0)         

    );
end entity datapath_wrapper;

architecture struct of datapath_wrapper is

    -- Sinal interno para o record de controle
    signal s_control : t_control;

begin

    -- Nomes ajustados para a nova definição do t_control
    s_control.reg_write   <= reg_write_i;
    s_control.alu_src_a   <= alu_src_a_i;
    s_control.alu_src_b   <= alu_src_b_i;
    s_control.mem_write   <= mem_write_i;
    s_control.wb_sel      <= wb_src_i;
    s_control.pc_src      <= pcsrc_i;
    s_control.alu_control <= alucontrol_i;

    -- Empacota os Enables dentro do s_control (no Datapath, eles não são portas separadas)
    s_control.pc_write    <= PCWrite_i;
    s_control.opc_write   <= OPCWrite_i;
    s_control.ir_write    <= IRWrite_i;
    s_control.rs1_write   <= RS1Write_i;
    s_control.rs2_write   <= RS2Write_i;
    s_control.alur_write  <= ALUWrite_i;
    s_control.mdr_write   <= MDRWrite_i;

    -- Amarra os controles do CSR que não serão estimulados neste teste
    s_control.csr_write   <= '0';
    s_control.trap_enter  <= '0';
    s_control.trap_return <= '0';
    s_control.trap_cause  <= (others => '0');

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

            -- Fixa os sinais de Interrupção em '0' para o teste básico do datapath
            Irq_External_i      => '0',
            Irq_Timer_i         => '0',
            Irq_Software_i      => '0',

            -- Deixa os sinais de saída do CSR abertos (open)
            CSR_Mstatus_MIE_o   => open,
            CSR_Mie_o           => open,
            CSR_Mip_o           => open,
            CSR_Valid_o         => open,

            -- Sinais do Debugger (fixa entrada em '0')
            debug_reg_addr_i    => (others => '0'),
            debug_reg_data_o    => open,

            Control_i           => s_control,
            Instruction_o       => Instruction_o,
            ALU_Zero_o          => ALU_Zero_o,

            -- Sinais de Debug para o Testbench
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
            DBG_r_MDR_o         => DBG_r_MDR_o
        );

end architecture struct;