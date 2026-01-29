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
-- Autor     : [André Maiolini]
-- Data      : [29/01/2026]
--
------------------------------------------------------------------------------------------------------------------
--
-- Registradores Implementados:
--    
--  - mstatus  (0x300): Status global (interrupt enable)
--  - mie      (0x304): Máscara de habilitação de interrupções
--  - mtvec    (0x305): Endereço base do vetor de traps
--  - mscratch (0x340): Registrador auxiliar para o kernel
--  - mepc     (0x341): PC salvo na exceção
--  - mcause   (0x342): Causa da exceção/interrupção
--  - mip      (0x344): Interrupções pendentes
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

        -- Interface de Controle Global

        Clk_i           : in  std_logic;
        Reset_i         : in  std_logic;

        -- Interface de Leitura/Escrita (Instruções CSR)

        Csr_Addr_i      : in  std_logic_vector(11 downto 0); -- Endereço (12 bits)
        Csr_Write_i     : in  std_logic;                     -- Enable de Escrita
        Csr_WData_i     : in  std_logic_vector(31 downto 0); -- Dado Escrita
        Csr_RData_o     : out std_logic_vector(31 downto 0); -- Dado Leitura

        -- Interface de Trap (Hardware)

        Trap_Enter_i    : in  std_logic;                     -- Entrar no Trap (Salva PC)
        Trap_Return_i   : in  std_logic;                     -- Retorno (MRET) - Não usado neste bloco simples, mas mantido na interface
        Trap_PC_i       : in  std_logic_vector(31 downto 0); -- PC da instrução que falhou
        Trap_Cause_i    : in  std_logic_vector(31 downto 0); -- Causa (ex: ECALL)

        -- Sinais ignorados por enquanto 

        Irq_Ext_i       : in  std_logic := '0';
        Irq_Timer_i     : in  std_logic := '0';
        Irq_Soft_i      : in  std_logic := '0';
        
        -- Saídas para o Datapath/Control

        Mtvec_o         : out std_logic_vector(31 downto 0); -- Vetor de Interrupção
        Mepc_o          : out std_logic_vector(31 downto 0); -- Endereço de Retorno
        
        -- Saídas de Status

        Global_Irq_En_o : out std_logic;
        Mie_o           : out std_logic_vector(31 downto 0);
        Mip_o           : out std_logic_vector(31 downto 0)

    );

end entity;

------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação comportamental do banco de CSRs
------------------------------------------------------------------------------------------------------------------

architecture rtl of csr_file is

    -- Endereços dos CSRs (Padrão RISC-V Privileged)

    constant c_ADDR_MSTATUS : std_logic_vector(11 downto 0) := x"300";
    constant c_ADDR_MTVEC   : std_logic_vector(11 downto 0) := x"305";
    constant c_ADDR_MEPC    : std_logic_vector(11 downto 0) := x"341";
    constant c_ADDR_MCAUSE  : std_logic_vector(11 downto 0) := x"342";

    -- Registradores Internos

    signal r_mtvec   : std_logic_vector(31 downto 0);
    signal r_mepc    : std_logic_vector(31 downto 0);
    signal r_mcause  : std_logic_vector(31 downto 0);

begin

    -- ===========================================================================================================
    -- Processo de Escrita (Síncrono)
    -- ===========================================================================================================

    -- Lida com escritas via instrução (CSRRW) e via Hardware (Trap)

    process(Clk_i, Reset_i)
    begin
        if rising_edge(Clk_i) then
            if Reset_i = '1' then
                r_mtvec   <= (others => '0'); -- Reset para 0 (ou um endereço base fixo)
                r_mepc    <= (others => '0');
                r_mcause  <= (others => '0');
            else
                
                -- Prioridade 1: Hardware Trap (Exceção ocorre)
                if Trap_Enter_i = '1' then
                    r_mepc   <= Trap_PC_i;    -- Salva o PC atual
                    r_mcause <= Trap_Cause_i; -- Salva a causa (ex: 11 para Ecall)
                
                -- Prioridade 2: Escrita via Software (Instrução CSRRW)
                elsif Csr_Write_i = '1' then
                    case Csr_Addr_i is
                        when c_ADDR_MTVEC   => r_mtvec   <= Csr_WData_i;
                        when c_ADDR_MEPC    => r_mepc    <= Csr_WData_i;
                        when c_ADDR_MCAUSE  => r_mcause  <= Csr_WData_i;
                        when others         => null; -- Ignora outros endereços
                    end case;
                end if;

            end if;
        end if;
    end process;

    -- ===========================================================================================================
    -- Processo de Leitura (Assíncrono / Combinacional)
    -- ===========================================================================================================

    process(Csr_Addr_i, r_mtvec, r_mepc, r_mcause)
    begin
        case Csr_Addr_i is
            when c_ADDR_MTVEC   => Csr_RData_o <= r_mtvec;
            when c_ADDR_MEPC    => Csr_RData_o <= r_mepc;
            when c_ADDR_MCAUSE  => Csr_RData_o <= r_mcause;
            when c_ADDR_MSTATUS => Csr_RData_o <= (others => '0'); 
            when others         => Csr_RData_o <= (others => '0');
        end case;
    end process;

    -- ===========================================================================================================
    -- 3. Saídas para o Datapath
    -- ===========================================================================================================

    Mtvec_o         <= r_mtvec;
    Mepc_o          <= r_mepc;
    Global_Irq_En_o <= '0';
    Mie_o           <= (others => '0');
    Mip_o           <= (others => '0');

    -- ===========================================================================================================

end architecture; -- rtl 

------------------------------------------------------------------------------------------------------------------