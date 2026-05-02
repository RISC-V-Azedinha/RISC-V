------------------------------------------------------------------------------------------------------------------
-- File: csr_file.vhd
--
--   ██████╗███████╗██████╗ 
--  ██╔════╝██╔════╝██╔══██╗
--  ██║     ███████╗██████╔╝
--  ██║     ╚════██║██╔══██╗
--  ╚██████╗███████║██║  ██║
--   ╚═════╝╚══════╝╚═╝  ╚═╝
--
-- Descrição : Banco de Registradores de Controle e Status (CSRs) para RISC-V (M-Mode).
--             Implementa os registradores definidos na especificação Zicsr / Privileged
--             necessários para tratamento de traps e interrupções.
--
--             Destaques da Implementação:
--             - Suporte a operações Atômicas: Read/Write (RW), Read/Set (RS), Read/Clear (RC).
--             - Tratamento de Exceções em Hardware (Salva PC e Causa automaticamente).
--             - Lógica de prioridade de escrita (Trap > MRET > CSR Write).
--
-- Autor     : [André Maiolini]
-- Data      : [31/01/2026] 
--
------------------------------------------------------------------------------------------------------------------
--
-- Registradores Implementados (Machine Mode):
--    
--  - mstatus  (0x300): Status global (controla o bit MIE - Interrupt Enable).
--  - mie      (0x304): Máscara de habilitação de interrupções individuais.
--  - mtvec    (0x305): Endereço base para onde o processador salta em caso de Trap.
--  - mscratch (0x340): Registrador auxiliar para o kernel (uso livre do SO).
--  - mepc     (0x341): Machine Exception Program Counter (salva o endereço de retorno).
--  - mcause   (0x342): Código numérico indicando a causa da exceção/interrupção.
--  - mip      (0x344): Machine Interrupt Pending (quais interrupções estão esperando).
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do banco de CSRs
------------------------------------------------------------------------------------------------------------------

entity csr_file is

    port (

        -- =======================================================================================================
        -- Interface de Controle Global
        -- =======================================================================================================

        Clk_i           : in  std_logic;
        Reset_i         : in  std_logic;

        -- =======================================================================================================
        -- Interface de Leitura/Escrita (Instruções CSR)
        -- =======================================================================================================

        Csr_Addr_i      : in  std_logic_vector(11 downto 0); -- Endereço do CSR (12 bits)
        Csr_Write_i     : in  std_logic;                     -- Enable de Escrita (comando da FSM)
        
        -- Opcode da operação CSR (Vem do Funct3[1:0]):
        -- 01: CSRRW (Write) - Troca o valor antigo pelo novo.
        -- 10: CSRRS (Set)   - Liga os bits indicados pela máscara (OR).
        -- 11: CSRRC (Clear) - Desliga os bits indicados pela máscara (AND NOT).

        Csr_Op_i        : in  std_logic_vector(1 downto 0);
        
        Csr_WData_i     : in  std_logic_vector(31 downto 0); -- Dado de entrada (rs1 ou uimm)
        Csr_RData_o     : out std_logic_vector(31 downto 0); -- Dado de saída (valor antigo do CSR)
        Csr_Valid_o     : out std_logic;                     -- '1' se o endereço do CSR existe

        -- =======================================================================================================
        -- Interface de Trap (Hardware) - Prioridade Máxima
        -- =======================================================================================================

        Trap_Enter_i    : in  std_logic;                     -- Sinal de entrada em Trap
        Trap_Return_i   : in  std_logic;                     -- Sinal de retorno (instrução MRET)
        Trap_PC_i       : in  std_logic_vector(31 downto 0); -- PC atual (para salvar no MEPC)
        Trap_Cause_i    : in  std_logic_vector(31 downto 0); -- Causa do Trap (para salvar no MCAUSE)

        -- =======================================================================================================
        -- Sinais de Interrupção Externa (Entradas Assíncronas)
        -- =======================================================================================================

        Irq_Ext_i       : in  std_logic := '0';
        Irq_Timer_i     : in  std_logic := '0';
        Irq_Soft_i      : in  std_logic := '0';
        
        -- =======================================================================================================
        -- Saídas de Status para o Processador
        -- =======================================================================================================

        Mtvec_o         : out std_logic_vector(31 downto 0); -- Para o PC Logic (Next PC = MTVEC)
        Mepc_o          : out std_logic_vector(31 downto 0); -- Para o PC Logic (Next PC = MEPC)
        Global_Irq_En_o : out std_logic;                     -- Para a FSM/Control (mstatus.MIE)
        Mie_o           : out std_logic_vector(31 downto 0); -- Para a FSM (Interrupt Enable Mask)
        Mip_o           : out std_logic_vector(31 downto 0)  -- Para a FSM (Interrupt Pending)

        -- =======================================================================================================

    );

end entity;

------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação comportamental
------------------------------------------------------------------------------------------------------------------

architecture rtl of csr_file is

    -- Endereços dos CSRs (Padrão RISC-V Privileged) -------------------------------------------------------------

    constant c_ADDR_MSTATUS : std_logic_vector(11 downto 0) := x"300";
    constant c_ADDR_MIE     : std_logic_vector(11 downto 0) := x"304";
    constant c_ADDR_MTVEC   : std_logic_vector(11 downto 0) := x"305";
    constant c_ADDR_MEPC    : std_logic_vector(11 downto 0) := x"341";
    constant c_ADDR_MCAUSE  : std_logic_vector(11 downto 0) := x"342";
    constant c_ADDR_MIP     : std_logic_vector(11 downto 0) := x"344";

    -- Índices de Bits importantes no mstatus --------------------------------------------------------------------

    constant c_MIE_BIT  : integer := 3; -- Machine Interrupt Enable (1=Habilitado)
    constant c_MPIE_BIT : integer := 7; -- Machine Previous Interrupt Enable (Backup ao entrar em trap)

    -- Registradores Físicos -------------------------------------------------------------------------------------

    signal r_mtvec   : std_logic_vector(31 downto 0);
    signal r_mepc    : std_logic_vector(31 downto 0);
    signal r_mcause  : std_logic_vector(31 downto 0);
    signal r_mie     : std_logic_vector(31 downto 0);
    signal r_mstatus : std_logic_vector(31 downto 0);

    -- Sinais combinacionais -------------------------------------------------------------------------------------

    signal s_mip_comb : std_logic_vector(31 downto 0); -- Vetor MIP construído dinamicamente

    -- Sinais auxiliares para a lógica Read-Modify-Write (RMW) ---------------------------------------------------

    signal s_write_val   : std_logic_vector(31 downto 0); -- Valor final a ser escrito
    signal s_curr_val    : std_logic_vector(31 downto 0); -- Valor lido atualmente
    signal s_we_internal : std_logic;                     -- Write Enable interno (após validação)

    --------------------------------------------------------------------------------------------------------------

begin

    -- ===========================================================================================================
    -- 1. Construção do Vetor MIP (Machine Interrupt Pending)
    -- ===========================================================================================================
    -- O registrador MIP reflete o estado das linhas de interrupção em tempo real.
    -- Bits definidos pela spec RISC-V:
    -- Bit 11: MEIP (Machine External Interrupt)
    -- Bit  7: MTIP (Machine Timer Interrupt)
    -- Bit  3: MSIP (Machine Software Interrupt)

    s_mip_comb <= (
        11 => Irq_Ext_i, 
        7  => Irq_Timer_i, 
        3  => Irq_Soft_i, 
        others => '0'
    );

    -- ===========================================================================================================
    -- 2. Processo de Leitura Assíncrona (Read Logic)
    -- ===========================================================================================================
    -- Este processo seleciona qual registrador está sendo lido com base no endereço.
    -- O valor lido (s_curr_val) é usado tanto para a saída (Csr_RData_o) quanto para
    -- calcular o novo valor nas operações de bitwise (Set/Clear).

    process(Csr_Addr_i, r_mtvec, r_mepc, r_mcause, r_mie, r_mstatus, s_mip_comb)
    begin

        Csr_Valid_o <= '1'; -- Default: Válido
        
        case Csr_Addr_i is
            when c_ADDR_MTVEC   => s_curr_val <= r_mtvec;
            when c_ADDR_MEPC    => s_curr_val <= r_mepc;
            when c_ADDR_MCAUSE  => s_curr_val <= r_mcause;
            when c_ADDR_MIE     => s_curr_val <= r_mie;
            when c_ADDR_MSTATUS => s_curr_val <= r_mstatus;
            when c_ADDR_MIP     => s_curr_val <= s_mip_comb; -- MIP é Read-Only (Hardware driven)
            
            when others => 
                s_curr_val  <= (others => '0'); 
                Csr_Valid_o <= '0'; -- Endereço inválido gera exceção na FSM

        end case;
    end process;
    
    Csr_RData_o <= s_curr_val;

    -- ===========================================================================================================
    -- 3. Lógica Combinacional de Read-Modify-Write (Atomicidade)
    -- ===========================================================================================================
    -- Aqui calculamos o "Próximo Valor" (s_write_val) dependendo da operação (Funct3).
    -- Isso garante atomicidade: lemos o valor atual, modificamos e preparamos a escrita no mesmo ciclo.

    process(s_curr_val, Csr_WData_i, Csr_Op_i, Csr_Write_i)
    begin
        s_we_internal <= '0';
        s_write_val   <= s_curr_val; -- Default: Se nada acontecer, mantém o valor.

        if Csr_Write_i = '1' then
            case Csr_Op_i is
                
                -- CSRRW (Read / Write): Escreve o novo valor diretamente.
                -- Equivalente a: CSR = rs1
                when "01" => 
                    s_write_val   <= Csr_WData_i;
                    s_we_internal <= '1';
                
                -- CSRRS (Read / Set Bit): Liga os bits onde a máscara (rs1) é '1'.
                -- Equivalente a: CSR = CSR OR rs1
                when "10" => 
                    s_write_val   <= s_curr_val OR Csr_WData_i;
                    
                    -- Proteção RISC-V: Se rs1=0, a instrução serve apenas para LEITURA.
                    -- Não devemos gerar pulso de escrita para evitar efeitos colaterais.
                    if unsigned(Csr_WData_i) /= 0 then
                        s_we_internal <= '1';
                    end if;

                -- CSRRC (Read / Clear Bit): Desliga os bits onde a máscara (rs1) é '1'.
                -- Equivalente a: CSR = CSR AND (NOT rs1)
                when "11" => 
                    s_write_val   <= s_curr_val AND (NOT Csr_WData_i);
                    
                    -- Proteção RISC-V: Se rs1=0, não escreve.
                    if unsigned(Csr_WData_i) /= 0 then
                        s_we_internal <= '1';
                    end if;
                    
                when others => null;
            end case;
        end if;
    end process;

    -- ===========================================================================================================
    -- 4. Processo Principal de Escrita (Síncrono)
    -- ===========================================================================================================
    -- Gerencia as atualizações dos registradores com base em prioridades:
    -- 1. Reset (Highest)
    -- 2. Trap Entry (Hardware Exception/IRQ)
    -- 3. Trap Return (MRET)
    -- 4. CSR Instruction (Software Write)

    process(Clk_i, Reset_i)
    begin
        if rising_edge(Clk_i) then
            if Reset_i = '1' then
                r_mtvec   <= (others => '0'); 
                r_mepc    <= (others => '0'); 
                r_mcause  <= (others => '0'); 
                r_mie     <= (others => '0');
                
                -- mstatus Reset: 
                -- MIE=0 (Interrupções desabilitadas), MPIE=1, MPP=11 (Machine Mode)
                r_mstatus <= (others => '0'); 
                r_mstatus(c_MPIE_BIT) <= '1'; 
                r_mstatus(12 downto 11) <= "11"; 

            else
                
                -- -----------------------------------------------------------
                -- A. TRAP ENTRY (Entrada em Exceção/Interrupção)
                -- -----------------------------------------------------------
                if Trap_Enter_i = '1' then
                    r_mepc   <= Trap_PC_i;    -- Salva PC atual
                    r_mcause <= Trap_Cause_i; -- Salva o motivo do erro
                    
                    -- Manipulação de Contexto (mstatus):
                    r_mstatus(c_MPIE_BIT) <= r_mstatus(c_MIE_BIT); -- Backup do Enable atual
                    r_mstatus(c_MIE_BIT)  <= '0';                  -- Desabilita interrupções globalmente
                
                -- -----------------------------------------------------------
                -- B. TRAP RETURN (Instrução MRET)
                -- -----------------------------------------------------------
                elsif Trap_Return_i = '1' then
                    -- Restaura Contexto:
                    r_mstatus(c_MIE_BIT)  <= r_mstatus(c_MPIE_BIT); -- Restaura Enable do backup
                    r_mstatus(c_MPIE_BIT) <= '1';                   -- Define backup como 1 (padrão)
                
                -- -----------------------------------------------------------
                -- C. ESCRITA DE SOFTWARE (Instruções CSRRW/RS/RC)
                -- -----------------------------------------------------------
                elsif s_we_internal = '1' then
                    case Csr_Addr_i is
                        when c_ADDR_MTVEC   => 
                            r_mtvec(31 downto 2) <= s_write_val(31 downto 2); 
                            r_mtvec(1 downto 0)  <= "00"; -- Hardwired: Direct Mode Only
                        
                        when c_ADDR_MEPC    => r_mepc    <= s_write_val;
                        when c_ADDR_MCAUSE  => r_mcause  <= s_write_val;
                        when c_ADDR_MIE     => r_mie     <= s_write_val;
                        
                        when c_ADDR_MSTATUS => 
                            -- Apenas bits específicos são writable
                            r_mstatus(c_MIE_BIT)  <= s_write_val(c_MIE_BIT);
                            r_mstatus(c_MPIE_BIT) <= s_write_val(c_MPIE_BIT);
                            -- MPP é mantido em "11" (Machine Mode Only)
                        
                        when others => null;
                    end case;
                end if;

            end if;
        end if;
    end process;

    -- ===========================================================================================================
    -- 5. Conexão das Saídas
    -- ===========================================================================================================

    Mtvec_o         <= r_mtvec;
    Mepc_o          <= r_mepc;
    Global_Irq_En_o <= r_mstatus(c_MIE_BIT); -- Bit MIE controla interrupções globais no Datapath
    Mie_o           <= r_mie;
    Mip_o           <= s_mip_comb;

end architecture; -- rtl 

------------------------------------------------------------------------------------------------------------------