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
-- Data      : [20/09/2025]
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
        -- Interface com o Datapath
        ----------------------------------------------------------------------------------------------------------

        -- Entradas

            Instruction_i  : in  std_logic_vector(31 downto 0);   -- A instrução para decodificação
            ALU_Zero_i     : in  std_logic;                       -- Flag 'Zero' vinda do Datapath
        
        -- Saídas (Sinais de Controle para o Datapath)

            Control_o      : out t_control                        -- Barramento com todos os sinais de controle 
                                                                  -- (decoder, pcsrc, alucontrol)

    );

end entity;

architecture rtl of control is

    -- Sinais internos
    signal s_opcode               : std_logic_vector(6 downto 0) := (others => '0');
    signal s_funct3               : std_logic_vector(2 downto 0) := (others => '0');
    signal s_funct7               : std_logic_vector(6 downto 0) := (others => '0');

    -- Sinal para armazenar o pacote de controle vindo do Decoder
    signal s_decoder              : t_decoder := c_DECODER_NOP;

    -- Sinais internos para lógica de control (extraídos de s_decoder)
    signal s_alucontrol           : std_logic_vector(3 downto 0) := (others => '0');
    signal s_pcsrc                : std_logic_vector(1 downto 0) := (others => '0');

    -- Sinal interno para lógica de branch
    signal s_branch_condition_met : std_logic := '0'; 

begin

    -- Extrai os campos da instrução

        s_opcode <= Instruction_i(6 downto 0);
        s_funct3 <= Instruction_i(14 downto 12);
        s_funct7 <= Instruction_i(31 downto 25);

    -- Unidade de Controle Principal

        -- Decodifica o Opcode para gerar os sinais de controle primários.

        -- OBS.: na arquitetura RISC-V, os campos da instrução são fixos:

        -- - opcode nos bits [6:0];
        -- - funct3 nos bits [14:12];
        -- - funct7 nos bits [31:25].     
        -- - rd nos bits [11:7];
        -- - rs1 nos bits [19:15];
        -- - rs2 nos bits [24:20].

            U_CONTROL: entity work.decoder
                port map (
                    Opcode_i       => s_opcode,
                    Decoder_o      => s_decoder
                );

    -- Unidade de Controle da ALU

        -- Decodifica os campos funct3 e funct7, junto com o ALUOp,
        -- para gerar o código final da operação da ULA.
    
            U_ALU_CONTROL: entity work.alu_control
                port map (
                    ALUOp_i        => s_decoder.alu_op,
                    Funct3_i       => s_funct3,
                    Funct7_i       => s_funct7,
                    ALUControl_o   => s_alucontrol
                );

    -- Lógica para o sinal PCSrc
    
        -- Usa funct3 para decidir qual condição verificar
            U_BRANCH_UNIT: entity work.branch_unit
                port map (
                    Branch_i       => s_decoder.branch,       -- Sinal decodificado do decoder
                    Funct3_i       => s_funct3,               -- Campo funct3 da instrução
                    ALU_Zero_i     => ALU_Zero_i,             -- Flag Zero vinda do datapath
                    BranchTaken_o  => s_branch_condition_met  -- Saída que indica se o desvio deve ser tomado
                );

        -- Calcula o valor de pcsrc baseado na lógica de branch e jump

            s_pcsrc <= "10" when (s_decoder.jump = '1' and s_opcode = "1100111") else            -- JALR
                       "01" when (s_decoder.jump = '1' and s_opcode = "1101111") else            -- JAL
                       "01" when (s_decoder.branch = '1' and s_branch_condition_met = '1') else  -- Branch Tomado
                       "00";                                                                     -- Padrão (PC + 4)

    -- Monta o pacote de controle (t_control) com todos os sinais
    
            Control_o <= (
                reg_write      => s_decoder.reg_write,
                alu_src_a      => s_decoder.alu_src_a,
                alu_src_b      => s_decoder.alu_src_b,
                mem_write      => s_decoder.mem_write,
                wb_src         => s_decoder.wb_src,
                pcsrc          => s_pcsrc,
                alucontrol     => s_alucontrol
            );

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------