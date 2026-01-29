------------------------------------------------------------------------------------------------------------------
--
-- File: control.vhd
--
-- ███████╗███████╗███╗   ███╗
-- ██╔════╝██╔════╝████╗ ████║
-- █████╗  ███████╗██╔████╔██║
-- ██╔══╝  ╚════██║██║╚██╔╝██║
-- ██║     ███████║██║ ╚═╝ ██║
-- ╚═╝     ╚══════╝╚═╝     ╚═╝
--
-- Descrição : Máquina de estados finitos (do tipo Moore) que controla os estados do datapath para
--      a arquitetura multi-cycle do core RV32I (RISC-V).
--
-- Autor     : [André Maiolini]
-- Data      : [30/12/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_isa_pkg.all;       -- Contém todas as definições da ISA RISC-V especificadas
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Máquina de Estados Finitos (Main FSM)
-------------------------------------------------------------------------------------------------------------------

entity main_fsm is
    port (

        ----------------------------------------------------------------------------------------------------------
        -- Interface para Sincronismo do MULTI-CYCLE
        ----------------------------------------------------------------------------------------------------------

        -- Entradas
            
            Clk_i          : in  std_logic;
            Reset_i        : in  std_logic;
            Opcode_i       : in  std_logic_vector(6 downto 0);

        ----------------------------------------------------------------------------------------------------------
        -- Interface de Handshake 
        ----------------------------------------------------------------------------------------------------------

        -- Para Memória de Instruções (IMem)

            imem_rdy_i     : in  std_logic; 
            imem_vld_o     : out std_logic;

        -- Para Memória de DADOS (Load/Store)

            dmem_rdy_i   : in  std_logic; 
            dmem_vld_o   : out std_logic;  

        ----------------------------------------------------------------------------------------------------------
        -- Interface de sinais de controle
        ----------------------------------------------------------------------------------------------------------

        -- Sinais de Controle de Escrita/Habilitação

            PCWrite_o      : out std_logic;                          -- Escrita Incondicional (JAL, JALR, IF)
            OPCWrite_o     : out std_logic;                          -- Escrita de Old PC
            PCWriteCond_o  : out std_logic;                          -- Escrita Condicional (Branches)
            IRWrite_o      : out std_logic;                          -- Escrita no Instruction Register
            MemWrite_o     : out std_logic;                          -- Escrita na DMem (Memória de Dados)
            RegWrite_o     : out std_logic;                          -- Escrita no banco de registradores
            RS1Write_o     : out std_logic;                          -- Escrita do registrador de saída de RS1
            RS2Write_o     : out std_logic;                          -- Escrita do registrador de saída de RS2
            ALUrWrite_o    : out std_logic;                          -- Habilita escrita no reg ALUResult
            MDRWrite_o     : out std_logic;                          -- Habilita escrita no reg MDR
        
        -- Sinais de Seleção (Multiplexadores)

            PCSrc_o        : out std_logic_vector(1 downto 0);       -- 00: PC + 4, 01: OldPC + IMM, 10: r_alu_result
            ALUSrcA_o      : out std_logic_vector(1 downto 0);       -- 00: RS1, 01: OldPC, 10: '0'
            ALUSrcB_o      : out std_logic;                          -- 0: rs2, 1: Imm
            WBSel_o        : out std_logic_vector(1 downto 0);       -- 00: r_alu_result, 01: r_MDR, 10: PC + 4
        
        -- Controle Auxiliar para o controlador da ALU (alu_control.vhd)
        
            ALUOp_o        : out std_logic_vector(1 downto 0)        -- 00: Add, 01: Branch, 10: Funct

    );
end entity main_fsm;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Implementação da Máquina de Estados Finitos (Main FSM)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of main_fsm is

    -- Definição dos Estados da FSM -------------------------------------------------------------------------------

    type t_state is (
        S_IF,                                                                        -- IF  (Instruction Fetch)
        S_ID,                                                                        -- ID  (Instruction Decode)
        S_EX_ALU, S_EX_ADDR, S_EX_BR, S_EX_JAL, S_EX_JALR, S_EX_LUI, S_EX_AUIPC,     -- EX  (Execution)
        S_EX_FENCE, S_EX_SYSTEM,
        S_MEM_RD, S_MEM_WR,                                                          -- MEM (Memory Access)
        S_WB_REG, S_WB_JAL, S_WB_JALR                                                -- WB  (Write-Back)
    );

    -- Registro do estado atual e do próximo estado ---------------------------------------------------------------

    signal current_state, next_state : t_state;

    -- Microestado para o Branch ----------------------------------------------------------------------------------

    -- Feito para quebrar o critical path e estabilizar o timing

    signal s_br_wait_q : std_logic;  -- 0: Comp, 1: Decide

    ---------------------------------------------------------------------------------------------------------------

begin

    -- 1. Registrador de Estado (Processo Síncrono) ---------------------------------------------------------------

    process(Clk_i)
    begin

        if rising_edge(Clk_i) then

            if Reset_i = '1' then

                current_state <= S_IF;
                s_br_wait_q   <= '0'; 

            else 

                current_state <= next_state;

                -- Lógica do "Wait State" do Branch
                if current_state = S_EX_BR and s_br_wait_q = '0' then
                    s_br_wait_q <= '1';
                elsif current_state /= S_EX_BR then
                    s_br_wait_q <= '0';
                end if;

            end if;    

        end if;

    end process;

    -- 2. Lógica de Próximo Estado (Combinacional) ----------------------------------------------------------------

    process(current_state, Opcode_i, dmem_rdy_i, imem_rdy_i, s_br_wait_q)
    begin
        -- Default: manter estado 
        next_state <= current_state;

        case current_state is
            -- FETCH: Busca Instrução
            when S_IF =>
                -- STALL DE INSTRUÇÃO: Só avança se a memória entregar a instrução
                if imem_rdy_i = '1' then
                    next_state <= S_ID;
                else
                    next_state <= S_IF;
                end if;

            -- DECODE: Decodifica e lê registradores
            when S_ID =>
                case Opcode_i is
                    when c_OPCODE_R_TYPE | c_OPCODE_I_TYPE => next_state <= S_EX_ALU    ;
                    when c_OPCODE_LOAD   | c_OPCODE_STORE  => next_state <= S_EX_ADDR   ;
                    when c_OPCODE_BRANCH                   => next_state <= S_EX_BR     ;
                    when c_OPCODE_JAL                      => next_state <= S_EX_JAL    ;
                    when c_OPCODE_JALR                     => next_state <= S_EX_JALR   ;
                    when c_OPCODE_LUI                      => next_state <= S_EX_LUI    ;
                    when c_OPCODE_AUIPC                    => next_state <= S_EX_AUIPC  ;
                    when c_OPCODE_FENCE                    => next_state <= S_EX_FENCE  ;
                    when c_OPCODE_SYSTEM                   => next_state <= S_EX_SYSTEM ;
                    when others                            => next_state <= S_IF        ; -- Instrução inválida volta pro IF 
                end case;

            -- EXECUTE: Várias possibilidades
            when S_EX_ALU   => next_state <= S_WB_REG;
            
            when S_EX_ADDR  => 
                if Opcode_i = c_OPCODE_LOAD then
                    next_state <= S_MEM_RD; -- Load
                else
                    next_state <= S_MEM_WR; -- Store
                end if;

            when S_EX_BR => 
                if s_br_wait_q = '0' then
                    next_state <= S_EX_BR; -- STALL INTERNO: Espera ALU calcular
                else
                    next_state <= S_IF;    -- DECISÃO TOMADA: Segue fluxo
                end if;

            when S_EX_JAL    => next_state <= S_WB_JAL;
            when S_EX_JALR   => next_state <= S_WB_JALR;
            when S_EX_LUI    => next_state <= S_WB_REG;
            when S_EX_AUIPC  => next_state <= S_WB_REG;

            when S_EX_FENCE  => next_state <= S_IF; 
            when S_EX_SYSTEM => next_state <= S_IF;

            -- MEMORY READ (HANDSHAKE)
            when S_MEM_RD   => 
                if dmem_rdy_i = '1' then
                    next_state <= S_WB_REG; -- Sucesso, avança
                else
                    next_state <= S_MEM_RD; -- STALL: Fica esperando
                end if;

            -- MEMORY WRITE (HANDSHAKE)
            when S_MEM_WR   => 
                if dmem_rdy_i = '1' then
                    next_state <= S_IF;     -- Sucesso, próxima instrução
                else
                    next_state <= S_MEM_WR; -- STALL: Fica esperando
                end if;

            -- WRITE BACK: Fim da instrução
            when S_WB_REG   => next_state <= S_IF;
            when S_WB_JAL   => next_state <= S_IF;
            when S_WB_JALR  => next_state <= S_IF;
            
            when others => next_state <= S_IF;

        end case;
    end process;

    -- 3. Lógica de Saída (Combinacional - Moore) -----------------------------------------------------------------

    process(current_state, Opcode_i, dmem_rdy_i, imem_rdy_i, s_br_wait_q)
    begin
        
        -- Default Outputs (por segurança)
        PCWrite_o     <= '0';
        OPCWrite_o    <= '0';
        PCWriteCond_o <= '0';
        IRWrite_o     <= '0';
        MemWrite_o    <= '0';
        RegWrite_o    <= '0';
        ALUrWrite_o   <= '0';
        MDRWrite_o    <= '0';
        dmem_vld_o    <= '0';
        imem_vld_o    <= '0';
        
        -- Default Muxes (por segurança)
        PCSrc_o       <= "00"; -- PC+4
        ALUSrcA_o     <= "00"; -- rs1
        ALUSrcB_o     <= '0';  -- rs2
        WBSel_o       <= "00"; -- ALUResult
        ALUOp_o       <= "00"; -- ADD

        case current_state is
            
            -- Estado IF: IRWrite=1, PCWrite=1, OPCWrite=1
            when S_IF =>
                imem_vld_o     <= '1';
                -- Só atualiza o registrador de instrução e PC quando o dado chega
                if imem_rdy_i = '1' then
                    IRWrite_o  <= '1';
                    PCWrite_o  <= '1';
                    OPCWrite_o <= '1';
                end if;

            -- Estado ID: RS1Write=1, RS2Write=1
            when S_ID =>
                RS1Write_o <= '1';
                RS2Write_o <= '1';
                null;

            -- Estados de EXECUÇÃO
            when S_EX_ALU =>
                ALUrWrite_o <= '1';
                ALUSrcA_o   <= "00"; -- rs1
                
                -- Diferenciação R-Type vs I-Type
                if Opcode_i = c_OPCODE_I_TYPE then -- (Use a constante definida no seu pkg ou architecture)
                    ALUSrcB_o <= '1'; -- Usa Imediato
                    ALUOp_o   <= "11"; -- CÓDIGO CORRETO PARA I-TYPE (conforme alu_control)
                else
                    ALUSrcB_o <= '0'; -- Usa rs2
                    ALUOp_o   <= "10"; -- CÓDIGO CORRETO PARA R-TYPE
                end if;

            when S_EX_ADDR =>
                ALUrWrite_o <= '1';
                ALUOp_o     <= "00"; -- Force ADD
                ALUSrcA_o   <= "00"; -- rs1
                ALUSrcB_o   <= '1';  -- Imediato (Offset)

            when S_EX_BR =>

                -- Mantemos a ALU operando nos dois ciclos
                ALUOp_o       <= "01"; 
                ALUSrcA_o     <= "00"; 
                ALUSrcB_o     <= '0';

                -- Só habilitamos a escrita no PC no segundo microestado (ciclo 1)
                -- quando o registrador r_alu_zero já tem o valor estável.
                if s_br_wait_q = '1' then
                    PCWriteCond_o <= '1'; 
                    PCSrc_o       <= "01";
                end if;

            when S_EX_JAL =>
                -- JAL só espera (somador dedicado calcula alvo). PC atualiza no WB.
                -- Poderíamos atualizar aqui, mas movemos pro WB por segurança (Safe Mode).
                null; 

            when S_EX_JALR =>
                ALUrWrite_o <= '1';
                ALUOp_o     <= "00"; -- Force ADD
                ALUSrcA_o   <= "00"; -- rs1
                ALUSrcB_o   <= '1';  -- Imediato

            when S_EX_LUI =>
                ALUrWrite_o <= '1';
                ALUOp_o     <= "00"; -- ADD
                ALUSrcA_o   <= "10"; -- Zero
                ALUSrcB_o   <= '1';  -- Imediato

            when S_EX_AUIPC =>
                ALUrWrite_o <= '1';
                ALUOp_o     <= "00"; -- ADD
                ALUSrcA_o   <= "01"; -- OldPC
                ALUSrcB_o   <= '1';  -- Imediato

            when S_EX_FENCE  => 
                -- NOP: nenhuma escrita.
                null;

            when S_EX_SYSTEM => 
                -- Aqui haverá a ativação dos sinais de exceção.
                null;

            -- Estados de MEMÓRIA (HANDSHAKE)
            when S_MEM_RD =>
                -- Validamos o pedido de leitura
                dmem_vld_o <= '1';
                
                -- Só grava no MDR quando o dado estiver PRONTO (Ready=1)
                if dmem_rdy_i = '1' then
                    MDRWrite_o <= '1';
                end if;
                
            when S_MEM_WR =>
                -- Validamos o pedido de escrita
                dmem_vld_o <= '1';
                MemWrite_o   <= '1'; -- WE Físico

            -- Estados de WRITE-BACK
            when S_WB_REG =>
                RegWrite_o  <= '1';
                if Opcode_i = c_OPCODE_LOAD then
                    WBSel_o <= "01"; -- MDR
                else
                    WBSel_o <= "00"; -- ALUResult
                end if;

            when S_WB_JAL =>
                RegWrite_o  <= '1';
                WBSel_o     <= "10"; -- PC+4 (Link Address)
                PCWrite_o   <= '1';
                PCSrc_o     <= "01"; -- Alvo JAL (Somador Dedicado)

            when S_WB_JALR =>
                RegWrite_o  <= '1';
                WBSel_o     <= "10"; -- PC+4 (Link Address)
                PCWrite_o   <= '1';
                PCSrc_o     <= "10"; -- Alvo JALR (ALUResult)

        end case;
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------