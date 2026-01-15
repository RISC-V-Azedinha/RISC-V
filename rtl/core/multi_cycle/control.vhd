------------------------------------------------------------------------------------------------------------------
--
-- File: control.vhd
--
--    ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗
--   ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║
--   ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║
--   ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║
--   ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗
--    ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
--
-- Descrição : A Unidade de Controle (Control) representa o 'circuito de comando' do processador.
--             Ela recebe os campos da instrução (Opcode, Funct3, Funct7) e as
--             flags de status (ex: Zero) vindos do datapath e, com base nessas informações, 
--             ela gera todos os sinais de controle (RegWrite, ALUSrc, MemtoReg, etc.) que orquestram as 
--             operações do datapath, ditando o que cada componente deve fazer em um determinado
--             momento.
--
-- Autor     : [André Maiolini]
-- Data      : [29/12/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Unidade de Controle
-------------------------------------------------------------------------------------------------------------------

entity control is

    port (

        ----------------------------------------------------------------------------------------------------------
        -- Interface de controle (Sincronismo para MULTI-CYCLE)
        ----------------------------------------------------------------------------------------------------------
        
        -- Entradas
            
            Clk_i          : in  std_logic;                          -- CLOCK global
            Reset_i        : in  std_logic;                          -- Sinal de Master-Reset (IF)

        ----------------------------------------------------------------------------------------------------------
        -- Interface de Handshake
        ----------------------------------------------------------------------------------------------------------

        -- Estes sinais passam direto para a Main FSM

            dmem_ready_i   : in  std_logic;
            dmem_valid_o   : out std_logic;

        ----------------------------------------------------------------------------------------------------------
        -- Interface com o Datapath
        ----------------------------------------------------------------------------------------------------------

        -- Entradas

            Instruction_i  : in  std_logic_vector(31 downto 0);      -- A instrução para decodificação
            ALU_Zero_i     : in  std_logic;                          -- Flag 'Zero' vinda do Datapath
        
        -- Saídas (Sinais de Controle para o Datapath)

            Control_o      : out t_control                           -- Barramento com todos os sinais de controle 
                                                                     -- (decoder, pcsrc, alucontrol)

    );

end entity;

architecture rtl of control is

    --------------------------------------------------------------------------------------------------------------
    -- Sinais Internos (Fios de interconexão)
    --------------------------------------------------------------------------------------------------------------
    
    -- Campos da Instrução

    signal s_opcode : std_logic_vector(6 downto 0);                  -- Código de operação da instrução 
    signal s_funct3 : std_logic_vector(2 downto 0);                  -- Campo Funct3 da instrução
    signal s_funct7 : std_logic_vector(6 downto 0);                  -- Campo Funct7 da instrução

    -- Sinais vindos da FSM (Main Finite State Machine)

    signal s_fsm_pc_write      : std_logic;
    signal s_fsm_pc_write_cond : std_logic;                          -- Habilita condicional (Branch)
    signal s_fsm_alu_op        : std_logic_vector(1 downto 0);       -- Comunicação FSM -> ALU Control

    -- Sinais vindos da Branch Unit
    
    signal s_branch_taken      : std_logic;                          -- Sinal que verifica branch

    -- Sinais vindos do ALU Control
    
    signal s_alu_function      : std_logic_vector(3 downto 0);       -- Determina operação da ALU

begin

    --------------------------------------------------------------------------------------------------------------
    -- 1. Extração dos Campos da Instrução
    --------------------------------------------------------------------------------------------------------------

    s_opcode <= Instruction_i(6 downto 0);
    s_funct3 <= Instruction_i(14 downto 12);
    s_funct7 <= Instruction_i(31 downto 25);

    --------------------------------------------------------------------------------------------------------------
    -- 2. Instância da FSM Principal (Sequenciador)
    --------------------------------------------------------------------------------------------------------------

    u_main_fsm : entity work.main_fsm
    port map (

        -- Sinais de controle e sincronismo
        Clk_i          => Clk_i,
        Reset_i        => Reset_i,
        Opcode_i       => s_opcode,

        -- Conexão do Handshake
        dmem_ready_i   => dmem_ready_i,
        dmem_valid_o   => dmem_valid_o,

        -- Saídas de Controle de Escrita/Enable
        PCWrite_o      => s_fsm_pc_write,                            -- Escrita Incondicional
        PCWriteCond_o  => s_fsm_pc_write_cond,                       -- Escrita Condicional (Branch)
        OPCWrite_o     => Control_o.opc_write,
        IRWrite_o      => Control_o.ir_write,
        MemWrite_o     => Control_o.mem_write,
        RegWrite_o     => Control_o.reg_write,
        RS1Write_o     => Control_o.rs1_write,
        RS2Write_o     => Control_o.rs2_write,
        ALUrWrite_o    => Control_o.alur_write,
        MDRWrite_o     => Control_o.mdr_write,

        -- Saídas de Seleção (Muxes)
        PCSrc_o        => Control_o.pc_src,
        ALUSrcA_o      => Control_o.alu_src_a,
        ALUSrcB_o      => Control_o.alu_src_b,
        WBSel_o        => Control_o.wb_sel,

        -- Interface Interna
        ALUOp_o        => s_fsm_alu_op

    );

    --------------------------------------------------------------------------------------------------------------
    -- 3. Instância da Unidade de Controle da ALU (Combinacional)
    --------------------------------------------------------------------------------------------------------------

    -- Traduz o 'ALUOp' da FSM + Funct3/7 em sinais específicos para a ALU

    u_alu_control : entity work.alu_control
    port map (
        ALUOp_i        => s_fsm_alu_op,
        Funct3_i       => s_funct3,
        Funct7_i       => s_funct7,
        ALUControl_o   => s_alu_function
    );

    -- Conecta a saída ao record principal
    Control_o.alu_control <= s_alu_function;

    --------------------------------------------------------------------------------------------------------------
    -- 4. Instância da Unidade de Branch (Combinacional)
    --------------------------------------------------------------------------------------------------------------

    -- Decide se o salto deve ser tomado com base no Funct3 e na flag Zero

    u_branch_unit : entity work.branch_unit
    port map (
        Branch_i       => s_fsm_pc_write_cond,
        Funct3_i       => s_funct3,
        ALU_Zero_i     => ALU_Zero_i,
        BranchTaken_o  => s_branch_taken
    );

    --------------------------------------------------------------------------------------------------------------
    -- 5. Lógica de habilitação condicional + incondicional de PCWrite
    --------------------------------------------------------------------------------------------------------------

    -- O PC deve ser escrito se:
    -- A) A FSM mandar escrever incondicionalmente (JAL, JALR, Fetch) OU
    -- B) A FSM permitir escrita condicional (Branch) E a Branch Unit confirmar o desvio.
    
    Control_o.pc_write <= s_fsm_pc_write OR (s_fsm_pc_write_cond AND s_branch_taken);

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------