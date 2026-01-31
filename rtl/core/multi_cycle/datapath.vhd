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
-- Data      : [29/12/2025]
--
------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
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
        Reset_i            : in  std_logic;                           -- Sinal de reset síncrono

        -- Barramento de Memória de Instruções (IMEM)

        IMem_addr_o        : out std_logic_vector(31 downto 0);       -- Endereço para a IMEM (saída do PC)
        IMem_data_i        : in  std_logic_vector(31 downto 0);       -- Instrução lida da IMEM

        -- Barramento de Memória de Dados (DMEM)

        DMem_addr_o        : out std_logic_vector(31 downto 0);       -- Endereço para a DMEM 
        DMem_data_o        : out std_logic_vector(31 downto 0);       -- Dado a ser escrito na DMEM (de rs2)
        DMem_data_i        : in  std_logic_vector(31 downto 0);       -- Dado lido da DMEM
        DMem_writeEnable_o : out std_logic_vector( 3 downto 0);       -- Habilita escrita na DMEM

        ----------------------------------------------------------------------------------------------------------
        -- Interface de Interrupções 
        ----------------------------------------------------------------------------------------------------------

        Irq_External_i     : in std_logic;
        Irq_Timer_i        : in std_logic;
        Irq_Software_i     : in std_logic;

        ----------------------------------------------------------------------------------------------------------
        -- Status CSR para o Controle 
        ----------------------------------------------------------------------------------------------------------

        CSR_Mstatus_MIE_o  : out std_logic;                           -- Bit Global Interrupt Enable
        CSR_Mie_o          : out std_logic_vector(31 downto 0);       -- Máscara de Enables
        CSR_Mip_o          : out std_logic_vector(31 downto 0);       -- Interrupções Pendentes
        CSR_Valid_o        : out std_logic;                           -- Sinaliza se o Endereço CSR é Válido

        ----------------------------------------------------------------------------------------------------------
        -- Interface com a Unidade de Controle
        ----------------------------------------------------------------------------------------------------------

        -- Entradas

        Control_i          : in  t_control;                           -- Recebe todos os sinais de controle (decoder, pcsrc, alucontrol)

        -- Entradas temporárias para validação do datapath

        -- Saídas

        Instruction_o      : out std_logic_vector(31 downto 0);       -- Envia a instrução para o controle
        ALU_Zero_o         : out std_logic;                           -- Envia a flag Zero para o controle
    
        ----------------------------------------------------------------------------------------------------------
        -- Interface de DEBUG (somente observação – simulação / bring-up)
        ----------------------------------------------------------------------------------------------------------

        -- Sinais combinacionais 

        DBG_pc_next_o      : out std_logic_vector(31 downto 0);       -- Próximo PC
        DBG_instruction_o  : out std_logic_vector(31 downto 0);       -- Instrução atual
        DBG_rs1_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs1
        DBG_rs2_data_o     : out std_logic_vector(31 downto 0);       -- Dados lidos do rs2
        DBG_alu_result_o   : out std_logic_vector(31 downto 0);       -- Resultado da ALU
        DBG_write_back_o   : out std_logic_vector(31 downto 0);       -- Dados escritos de volta no banco de registradores
        DBG_alu_zero_o     : out std_logic;                           -- Flag Zero da ALU

        -- Dados dos registradores

        DBG_r_pc_o   : out std_logic_vector(31 downto 0);             -- PC atual
        DBG_r_opc_o  : out std_logic_vector(31 downto 0);             -- OldPC atual
        DBG_r_ir_o   : out std_logic_vector(31 downto 0);             -- IR atual
        DBG_r_rs1_o  : out std_logic_vector(31 downto 0);             -- RS1 atual
        DBG_r_rs2_o  : out std_logic_vector(31 downto 0);             -- RS2 atual 
        DBG_r_alu_o  : out std_logic_vector(31 downto 0);             -- ALUResult atual
        DBG_r_MDR_o  : out std_logic_vector(31 downto 0)              -- MDR atual

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação do Caminho de Dados (datapath)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of datapath is

    -- ============== DECLARAÇÃO DOS SINAIS INTERNOS DO DATAPATH ==============

    -- Sinais internos do datapath

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

    -- Registradores de estado para o MULTI-CYCLE

    signal r_PC             : std_logic_vector(31 downto 0) := (others => '0');           -- Contador de Programa (PC) atual
    signal r_OldPC          : std_logic_vector(31 downto 0) := (others => '0');           -- Program Counter da instrução selecionada
    signal r_IR             : std_logic_vector(31 downto 0) := (others => '0');           -- Instruction Register
    signal r_MDR            : std_logic_vector(31 downto 0) := (others => '0');           -- Memory Data Register
    signal r_RS1            : std_logic_vector(31 downto 0) := (others => '0');           -- Lê rs1
    signal r_RS2            : std_logic_vector(31 downto 0) := (others => '0');           -- Lê rs2
    signal r_ALUResult      : std_logic_vector(31 downto 0) := (others => '0');           -- Salva resultado da ALU

    -- Sinais para conexão com o CSR File

    signal s_csr_rdata : std_logic_vector(31 downto 0);
    signal s_csr_mtvec : std_logic_vector(31 downto 0);                                   -- Endereço do tratador de trap
    signal s_csr_mepc  : std_logic_vector(31 downto 0);                                   -- Endereço de retorno

begin

    -- Saídas para o control path

        Instruction_o    <= r_IR;
        ALU_Zero_o       <= s_alu_zero;

    -- Control and Status Registers

    U_CSR_FILE : entity work.csr_file
        port map (
            Clk_i           => CLK_i,
            Reset_i         => Reset_i,
            
            -- Leitura/Escrita
            Csr_Addr_i      => r_IR(31 downto 20),      
            Csr_Write_i     => Control_i.csr_write,     
            Csr_WData_i     => r_RS1,                   
            Csr_RData_o     => s_csr_rdata,    
            Csr_Valid_o     => CSR_Valid_o,         
            
            -- Hardware Trap
            Trap_Enter_i    => Control_i.trap_enter,
            Trap_Return_i   => Control_i.trap_return,
            Trap_PC_i       => r_OldPC,                 
            Trap_Cause_i    => Control_i.trap_cause,    
            
            -- Entradas de Interrupção (Do Top Level)
            Irq_Ext_i       => Irq_External_i,
            Irq_Timer_i     => Irq_Timer_i,
            Irq_Soft_i      => Irq_Software_i,
            
            -- Vetores
            Mtvec_o         => s_csr_mtvec,             
            Mepc_o          => s_csr_mepc,              
            
            -- Status para a FSM (Saídas do Datapath)
            Global_Irq_En_o => CSR_Mstatus_MIE_o,
            Mie_o           => CSR_Mie_o,
            Mip_o           => CSR_Mip_o
        );

    -- Gerenciamento dos registradores intermediários do MULTI-CYCLE 

        process(CLK_i, Reset_i) 
        begin

            if rising_edge(CLK_i) then

                if Reset_i = '1' then

                    -- Reinicia o estado do CORE com sinal de  [SÍNCRONO]

                    r_OldPC     <= (others => '0');
                    r_IR        <= (others => '0');
                    r_MDR       <= (others => '0');
                    r_RS1       <= (others => '0');
                    r_RS2       <= (others => '0');
                    r_ALUResult <= (others => '0');

                else 

                    if Control_i.opc_write = '1' then
                        r_OldPC <= r_PC;               -- Registra o valor de PC referente à instrução atual
                    end if;

                    if Control_i.ir_write = '1' then
                        r_IR <= s_instruction;         -- Registrado para ser usado em ID
                    end if;

                    if Control_i.mdr_write = '1' then
                        r_MDR <= s_lsu_data_out;       -- Registrado para ser usado em WB
                    end if;
                    
                    if Control_i.rs1_write = '1' then
                        r_RS1 <= s_read_data_1;        -- Registrado para ser usado em EX
                    end if;

                    if Control_i.rs2_write = '1' then
                        r_RS2 <= s_read_data_2;        -- Registrado para ser usado em EX
                    end if;

                    if Control_i.alur_write = '1' then
                        r_ALUResult <= s_alu_result;   -- Registrado para ser usado em MEM
                    end if;

                end if;

            end if;

        end process;

    -- ============== Estágio de Busca (FETCH) ===============================================

        -- Contador de Programa (PC) 
        -- - Registrador de 32 bits com reset assíncrono

            PC_REGISTER:process(CLK_i, Reset_i)
            begin
                if rising_edge(CLK_i) then
                    if Reset_i = '1' then
                        r_PC <= (others => '0');
                    else 
                        if Control_i.pc_write = '1' then
                            r_PC <= s_pc_next;
                        end if;
                    end if;
                end if;
            end process;

        -- O PC atual busca a instrução na memória (IMEM)

            IMem_addr_o   <= r_PC;         -- Utiliza o valor advindo do registrador program counter (PC) atual
            s_instruction <= IMem_data_i;  -- Utiliza o valor advindo do registrador intermediário

    -- ============== Estágio de Decodificação (DECODE) ======================================

        -- - Gerador de Imediatos (Immediate Generator)
        -- -- Extrai e estende o imediato da instrução para 32 bits

            U_IMM_GEN: entity work.imm_gen port map (
                Instruction_i => r_IR, 
                Immediate_o => s_immediate
            );

        -- Os endereços rs1 e rs2 da instrução são enviados ao Banco de Registradores,
        -- que fornece os dados dos registradores de forma combinacional.

            U_REG_FILE: entity work.reg_file
                port map (
                    clk_i        => CLK_i,                            -- Clock do processador
                    RegWrite_i   => Control_i.reg_write,              -- Habilita escrita no banco de registradores
                    ReadAddr1_i  => r_IR(19 downto 15),               -- rs1 (bits [19:15]) - 5 bits
                    ReadAddr2_i  => r_IR(24 downto 20),               -- rs2 (bits [24:20]) - 5 bits
                    WriteAddr_i  => r_IR(11 downto 7),                -- rd  (bits [11: 7]) - 5 bits
                    WriteData_i  => s_write_back_data,                -- Dados a serem escritos (da ALU ou da memória) - 32 bits
                    ReadData1_o  => s_read_data_1,                    -- Dados lidos do registrador rs1 (32 bits)
                    ReadData2_o  => s_read_data_2                     -- Dados lidos do registrador rs2 (32 bits)
                );

    -- ============== Estágio de Execução (EXECUTE) ==========================================

        -- O Mux ALUSrcB seleciona a segunda entrada da ULA:
        -- Se s_alusrc_b='0' (R-Type, Branch), usa o valor do registrador s_read_data_2.
        -- Se s_alusrc_b='1' (I-Type, Load, Store), usa a constante s_immediate.

            with Control_i.alu_src_a select
                s_alu_in_a <= r_RS1       when "00",    -- Padrão (rs1)
                              r_OldPC     when "01",    -- AUIPC (PC)
                              x"00000000" when "10",    -- LUI (Zero)
                              r_RS1       when others;  -- Necessário para compilação

            s_alu_in_b <= r_RS2 when Control_i.alu_src_b = '0' else s_immediate;

        -- A ULA executa a operação comandada pelo s_alu_control.
        -- O resultado (s_alu_result) pode ser um valor aritmético, um endereço de memória ou um resultado de comparação.

            U_ALU: entity work.alu
                port map (
                    A_i => s_alu_in_a,
                    B_i => s_alu_in_b,
                    ALUControl_i => Control_i.alu_control,
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
                Addr_i        => r_ALUResult,                         -- Endereço calculado pela ALU
                WriteData_i   => r_RS2,                               -- Dado de rs2 para escrita
                MemWrite_i    => Control_i.mem_write,                 -- Sinal de controle WE
                Funct3_i      => r_IR(14 downto 12),                  -- Funct3 define B, H, W
                
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

            with Control_i.wb_sel select
                s_write_back_data <= r_ALUResult       when "00",     -- Tipo-R, Tipo-I (Aritmética)
                                     r_MDR             when "01",     -- Loads
                                     r_PC              when "10",     -- JAL / JALR
                                     s_csr_rdata       when "11",     -- Dado do CSR
                                     (others => '0')   when others;

    -- ============== Lógica de Cálculo do Próximo PC ======================================
    
        -- Candidato 1: Endereço sequencial (PC + 4)

            s_pc_plus_4 <= std_logic_vector(unsigned( r_PC) + 4);
    
        -- Candidato 2: Endereço de destino para Branch e JAL (PC + imediato)

            s_branch_or_jal_addr <= std_logic_vector(signed(r_OldPC) + signed(s_immediate));

        -- Mux final que alimenta o registrador do PC no próximo ciclo de clock
        -- - A prioridade é: Jumps têm precedência sobre Branches, que têm precedência sobre PC+4.

            process(Control_i, s_pc_plus_4, s_branch_or_jal_addr, r_ALUResult, s_csr_mtvec, s_csr_mepc)
            begin
                if Control_i.trap_enter = '1' then
                    s_pc_next <= s_csr_mtvec;       -- Pula para o vetor de interrupção
                elsif Control_i.trap_return = '1' then
                    s_pc_next <= s_csr_mepc;        -- Retorna para o endereço salvo
                else
                    -- Lógica normal existente
                    case Control_i.pc_src is
                        when "00"   => s_pc_next <= s_pc_plus_4;                     -- PC <- PC + 4
                        when "01"   => s_pc_next <= s_branch_or_jal_addr;            -- PC <- Endereço de Branch ou JAL
                        when "10"   => s_pc_next <= r_ALUResult(31 downto 1) & '0';  -- PC <- Endereço do JALR (rs1 + imm)
                        when others => s_pc_next <= (others => 'X');
                    end case;
                end if;
            end process;

    -- ============== Sinais de DEBUG (MONITORAMENTO) ======================================

        -- Sinais de Debug / Monitoramento para observação externa

        ------------------------------------------------------------------------------
        -- DEBUG ENABLED
        ------------------------------------------------------------------------------
        gen_debug_on : if DEBUG_EN generate
            DBG_r_pc_o        <= r_PC;
            DBG_r_opc_o       <= r_OldPC;
            DBG_r_ir_o        <= r_IR;
            DBG_r_rs1_o       <= r_RS1;
            DBG_r_rs2_o       <= r_RS2; 
            DBG_r_alu_o       <= r_ALUResult;
            DBG_r_MDR_o       <= r_MDR;
            DBG_pc_next_o     <= s_pc_next;
            DBG_instruction_o <= r_IR;
            DBG_rs1_data_o    <= r_RS1;
            DBG_rs2_data_o    <= r_RS2;
            DBG_alu_result_o  <= r_ALUResult;
            DBG_write_back_o  <= s_write_back_data;
            DBG_alu_zero_o    <= s_alu_zero;
        end generate;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------