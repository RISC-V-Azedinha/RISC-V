------------------------------------------------------------------------------------------------------------------
--
-- File: datapath.vhd
--
--   ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ████████╗██╗  ██╗
--   ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██║  ██║
--   ██║  ██║███████║   ██║   ███████║██████╔╝███████║   ██║   ███████║
--   ██║  ██║██╔══██║   ██║   ██╔══██║██╔═══╝ ██╔══██║   ██║   ██╔══██║
--   ██████╔╝██║  ██║   ██║   ██║  ██║██║     ██║  ██║   ██║   ██║  ██║
--   ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝                                                             
--
-- Descrição : O Caminho de Dados (datapath) representa o 'circuito de potência' do processador RISC-V.
--             Ele contém todos os componentes estruturais responsáveis por armazenar,
--             transportar e processar os dados. Isso inclui o Contador de Programa (PC),
--             o Banco de Registradores, a Unidade Lógica e Aritmética (ALU), o Gerador
--             de Imediatos e todos os multiplexadores. Esta unidade não toma decisões;
--             ela apenas executa as operações comandadas pela Unidade de Controle.
--
-- Autor     : [André Maiolini]
-- Data      : [20/09/2025]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all; 
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Caminho de Dados (datapath)
-------------------------------------------------------------------------------------------------------------------

entity datapath is

    generic (

        DEBUG_EN : boolean := false  -- Habilita sinais de debug para monitoramento (desabilitado por padrão)
    
    );

    port (

        ----------------------------------------------------------------------------------------------------------
        -- Sinais e Interfaces de Memória
        ----------------------------------------------------------------------------------------------------------

        -- Sinais Globais (Clock e Mater-Reset)

        CLK_i              : in  std_logic;                           -- Clock principal
        Reset_i            : in  std_logic;                           -- Sinal de reset assíncrono

        -- Barramento de Memória de Instruções (IMEM)

        IMem_addr_o        : out std_logic_vector(31 downto 0);       -- Endereço para a IMEM (saída do PC)
        IMem_data_i        : in  std_logic_vector(31 downto 0);       -- Instrução lida da IMEM

        -- Barramento de Memória de Dados (DMEM)

        DMem_addr_o        : out std_logic_vector(31 downto 0);       -- Endereço para a DMEM 
        DMem_data_o        : out std_logic_vector(31 downto 0);       -- Dado a ser escrito na DMEM (de rs2)
        DMem_data_i        : in  std_logic_vector(31 downto 0);       -- Dado lido da DMEM
        DMem_writeEnable_o : out std_logic_vector( 3 downto 0);       -- Habilita escrita na DMEM

        ----------------------------------------------------------------------------------------------------------
        -- Interface com a Unidade de Controle
        ----------------------------------------------------------------------------------------------------------

        -- Entradas

        Control_i          : in  t_control;                           -- Recebe todos os sinais de controle (decoder, pcsrc, alucontrol)

        -- Saídas

        Instruction_o      : out std_logic_vector(31 downto 0);       -- Envia a instrução para o controle
        ALU_Zero_o         : out std_logic;                           -- Envia a flag Zero para o controle
    
        ----------------------------------------------------------------------------------------------------------
        -- Interface de DEBUG (somente observação – simulação / bring-up)
        ----------------------------------------------------------------------------------------------------------

        DBG_pc_current_o   : out std_logic_vector(31 downto 0);       -- PC atual
        DBG_pc_next_o      : out std_logic_vector(31 downto 0);       -- Próximo PC
        DBG_instruction_o  : out std_logic_vector(31 downto 0);       -- Instrução atual
        DBG_rs1_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs1
        DBG_rs2_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs2
        DBG_alu_result_o   : out std_logic_vector(31 downto 0);       -- Resultado da ALU
        DBG_write_back_o   : out std_logic_vector(31 downto 0);       -- Dados escritos de volta no banco de registradores
        DBG_alu_zero_o     : out std_logic                            -- Flag Zero da ALU

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do Caminho de Dados (datapath)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of datapath is

    -- ============== DECLARAÇÃO DOS SINAIS INTERNOS DO DATAPATH ==============

    -- Sinais para desempacotar Control_i
    signal s_reg_write            : std_logic := '0';                  
    signal s_alu_src_a            : std_logic_vector(1 downto 0) := (others => '0');
    signal s_alu_src_b            : std_logic := '0';                                   
    signal s_mem_write            : std_logic := '0';                   
    signal s_wb_src               : std_logic_vector(1 downto 0) := (others => '0');
    signal s_pc_src               : std_logic_vector(1 downto 0) := (others => '0');
    signal s_alucontrol           : std_logic_vector(3 downto 0) := (others => '0');

    -- Sinais internos do datapath
    signal s_pc_current           : std_logic_vector(31 downto 0) := (others => '0');     -- Contador de Programa (PC) atual
    signal s_pc_next              : std_logic_vector(31 downto 0) := (others => '0');     -- Próximo valor do PC
    signal s_pc_plus_4            : std_logic_vector(31 downto 0) := (others => '0');     -- PC + 4 (endereço da próxima instrução)
    signal s_instruction          : std_logic_vector(31 downto 0) := (others => '0');     -- Instrução lida da memória (IMEM)
    signal s_read_data_1          : std_logic_vector(31 downto 0) := (others => '0');     -- Dados lidos do primeiro registrador (rs1)
    signal s_read_data_2          : std_logic_vector(31 downto 0) := (others => '0');     -- Dados lidos do segundo registrador (rs2)
    signal s_immediate            : std_logic_vector(31 downto 0) := (others => '0');     -- Imediato estendido (32 bits)
    signal s_alu_in_a             : std_logic_vector(31 downto 0) := (others => '0');     -- Primeiro operando da ALU
    signal s_alu_in_b             : std_logic_vector(31 downto 0) := (others => '0');     -- Segundo operando da ALU (registrador ou imediato)
    signal s_alu_result           : std_logic_vector(31 downto 0) := (others => '0');     -- Resultado da ALU (32 bits)
    signal s_write_back_data      : std_logic_vector(31 downto 0) := (others => '0');     -- Dados a serem escritos de volta no banco de registradores
    signal s_alu_zero             : std_logic := '0';                                     -- Flag "Zero" da ALU
    signal s_branch_or_jal_addr   : std_logic_vector(31 downto 0) := (others => '0');     -- Endereço para Branch e JAL
    signal s_lsu_data_out         : std_logic_vector(31 downto 0) := (others => '0');     -- Sinal de saída da LSU (Load-Store Unit)

begin

    -- Desempacota os sinais de Control_i (vindos da unidade de controle)

        s_reg_write      <= Control_i.reg_write;
        s_alu_src_a      <= Control_i.alu_src_a;
        s_alu_src_b      <= Control_i.alu_src_b;
        s_mem_write      <= Control_i.mem_write;
        s_wb_src         <= Control_i.wb_src;
        s_pc_src         <= Control_i.pcsrc;
        s_alucontrol     <= Control_i.alucontrol;

    -- Saídas para o control path

        Instruction_o  <= s_instruction;
        ALU_Zero_o     <= s_alu_zero;

    -- ============== Estágio de Busca (FETCH) ===============================================

        -- Contador de Programa (PC) 
        -- - Registrador de 32 bits com reset assíncrono

            PC_REGISTER:process(CLK_i, Reset_i)
            begin
                if Reset_i = '1' then
                    s_pc_current <= (others => '0');
                elsif rising_edge(CLK_i) then
                    s_pc_current <= s_pc_next;
                end if;
            end process;

        -- O PC atual busca a instrução na memória (IMEM)

            IMem_addr_o <= s_pc_current;
            s_instruction <= IMem_data_i;

    -- ============== Estágio de Decodificação (DECODE) ======================================

        -- - Gerador de Imediatos (Immediate Generator)
        -- -- Extrai e estende o imediato da instrução para 32 bits

            U_IMM_GEN: entity work.imm_gen port map (
                Instruction_i => s_instruction, 
                Immediate_o => s_immediate
            );

        -- Os endereços rs1 e rs2 da instrução são enviados ao Banco de Registradores,
        -- que fornece os dados dos registradores de forma combinacional.

            U_REG_FILE: entity work.reg_file
                port map (
                    clk_i        => CLK_i,                            -- Clock do processador
                    RegWrite_i   => s_reg_write,                      -- Habilita escrita no banco de registradores
                    ReadAddr1_i  => s_instruction(19 downto 15),      -- rs1 (bits [19:15]) - 5 bits
                    ReadAddr2_i  => s_instruction(24 downto 20),      -- rs2 (bits [24:20]) - 5 bits
                    WriteAddr_i  => s_instruction(11 downto 7),       -- rd  (bits [11: 7]) - 5 bits
                    WriteData_i  => s_write_back_data,                -- Dados a serem escritos (da ALU ou da memória) - 32 bits
                    ReadData1_o  => s_read_data_1,                    -- Dados lidos do registrador rs1 (32 bits)
                    ReadData2_o  => s_read_data_2                     -- Dados lidos do registrador rs2 (32 bits)
                );

    -- ============== Estágio de Execução (EXECUTE) ==========================================

        -- O Mux ALUSrcB seleciona a segunda entrada da ULA:
        -- Se s_alusrc_b='0' (R-Type, Branch), usa o valor do registrador s_read_data_2.
        -- Se s_alusrc_b='1' (I-Type, Load, Store), usa a constante s_immediate.

            with s_alu_src_a select
                s_alu_in_a <= s_read_data_1   when "00",    -- Padrão (rs1)
                              s_pc_current    when "01",    -- AUIPC (PC)
                              x"00000000"     when "10",    -- LUI (Zero)
                              s_read_data_1   when others;  -- Necessário para compilação

            s_alu_in_b <= s_read_data_2 when s_alu_src_b = '0' else s_immediate;

        -- A ULA executa a operação comandada pelo s_alu_control.
        -- O resultado (s_alu_result) pode ser um valor aritmético, um endereço de memória ou um resultado de comparação.

            U_ALU: entity work.alu
                port map (
                    A_i => s_alu_in_a,
                    B_i => s_alu_in_b,
                    ALUControl_i => s_alucontrol,
                    Result_o => s_alu_result,
                    Zero_o => s_alu_zero
                );

    -- ============== Estágio de Acesso à Memória (MEMORY) ==================================

        -- Aqui ocorre o acesso à memória de dados (DMEM).
        -- Dependendo dos sinais de controle, a CPU pode ler ou escrever na memória.

        -- A LSU (Load Store Unit) encapsula toda a lógica de acesso à memória,
        -- incluindo alinhamento de bytes (Load/Store Byte/Half) e extensão de sinal.
        
        U_LSU: entity work.lsu
            port map (
                -- Interface com o Datapath (Entradas)
                Addr_i        => s_alu_result,                        -- Endereço calculado pela ALU
                WriteData_i   => s_read_data_2,                       -- Dado de rs2 para escrita
                MemWrite_i    => s_mem_write,                         -- Sinal de controle WE
                Funct3_i      => s_instruction(14 downto 12),         -- Funct3 define B, H, W
                
                -- Interface com a Memória Física (DMem)
                DMem_data_i   => DMem_data_i,                         -- Leitura crua da RAM
                DMem_addr_o   => DMem_addr_o,                         -- Endereço físico
                DMem_data_o   => DMem_data_o,                         -- Dado formatado para escrita
                DMem_we_o     => DMem_writeEnable_o,                  -- WE repassado
                
                -- Interface com o Datapath (Saída para Write-Back)
                LoadData_o    => s_lsu_data_out                       -- Dado lido formatado (Sign/Zero Ext)
            );

    -- ============== Estágio de Escrita de Volta (WRITE-BACK) ===============================

        -- Mux WRITE-BACK DATA: decide o que será escrito de volta no registrador

            with s_wb_src select
                s_write_back_data <= s_alu_result      when "00",     -- Tipo-R, Tipo-I (Aritmética)
                                     s_lsu_data_out    when "01",     -- Loads
                                     s_pc_plus_4       when "10",     -- JAL / JALR
                                     (others => '0')   when others;

    -- ============== Lógica de Cálculo do Próximo PC ======================================
    
        -- Candidato 1: Endereço sequencial (PC + 4)

            s_pc_plus_4 <= std_logic_vector(unsigned(s_pc_current) + 4);
    
        -- Candidato 2: Endereço de destino para Branch e JAL (PC + imediato)

            s_branch_or_jal_addr <= std_logic_vector(signed(s_pc_current) + signed(s_immediate));

        -- Mux final que alimenta o registrador do PC no próximo ciclo de clock
        -- - A prioridade é: Jumps têm precedência sobre Branches, que têm precedência sobre PC+4.

            with s_pc_src select
                s_pc_next <= s_pc_plus_4                    when "00", -- PC <- PC + 4
                            s_branch_or_jal_addr            when "01", -- PC <- Endereço de Branch ou JAL
                            s_alu_result(31 downto 1) & '0' when "10", -- PC <- Endereço do JALR (rs1 + imm)
                            (others => 'X')                 when others;

    -- ============== Sinais de DEBUG (MONITORAMENTO) ======================================

        -- Sinais de Debug / Monitoramento para observação externa

        ------------------------------------------------------------------------------
        -- DEBUG ENABLED
        ------------------------------------------------------------------------------
        gen_debug_on : if DEBUG_EN generate
            DBG_pc_current_o  <= s_pc_current;
            DBG_pc_next_o     <= s_pc_next;
            DBG_instruction_o <= s_instruction;
            DBG_rs1_data_o    <= s_read_data_1;
            DBG_rs2_data_o    <= s_read_data_2;
            DBG_alu_result_o  <= s_alu_result;
            DBG_write_back_o  <= s_write_back_data;
            DBG_alu_zero_o    <= s_alu_zero;
        end generate;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------