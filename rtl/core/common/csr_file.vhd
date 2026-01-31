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
        Csr_Valid_o     : out std_logic;                     -- Endereçamento Válido

        -- Interface de Trap (Hardware)

        Trap_Enter_i    : in  std_logic;                     -- Entrar no Trap (Salva PC)
        Trap_Return_i   : in  std_logic;                     -- Retorno (MRET)
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

        Global_Irq_En_o : out std_logic;                     -- Bit MIE do mstatus
        Mie_o           : out std_logic_vector(31 downto 0); -- Máscara de Enables
        Mip_o           : out std_logic_vector(31 downto 0)  -- Pendências Reais

    );

end entity;

------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação comportamental do banco de CSRs
------------------------------------------------------------------------------------------------------------------

architecture rtl of csr_file is

    -- Endereços dos CSRs (Padrão RISC-V Privileged)

    constant c_ADDR_MSTATUS : std_logic_vector(11 downto 0) := x"300";
    constant c_ADDR_MIE     : std_logic_vector(11 downto 0) := x"304";
    constant c_ADDR_MTVEC   : std_logic_vector(11 downto 0) := x"305";
    constant c_ADDR_MEPC    : std_logic_vector(11 downto 0) := x"341";
    constant c_ADDR_MCAUSE  : std_logic_vector(11 downto 0) := x"342";
    constant c_ADDR_MIP     : std_logic_vector(11 downto 0) := x"344";

    -- Índices de Bits no mstatus

    constant c_MIE_BIT  : integer := 3; -- Machine Interrupt Enable
    constant c_MPIE_BIT : integer := 7; -- Machine Previous Interrupt Enable

    -- Registradores internos

    signal r_mtvec   : std_logic_vector(31 downto 0);
    signal r_mepc    : std_logic_vector(31 downto 0);
    signal r_mcause  : std_logic_vector(31 downto 0);
    signal r_mie     : std_logic_vector(31 downto 0); -- Interrupt Enable Register
    signal r_mstatus : std_logic_vector(31 downto 0); -- Status Register

    -- Sinais combinacionais

    signal s_mip_comb : std_logic_vector(31 downto 0);

begin

    -- ===========================================================================================================
    -- 1. Construção do Vetor MIP (Machine Interrupt Pending)
    -- ===========================================================================================================
    -- Bits definidos pela spec RISC-V:
    -- Bit 11: MEIP (Machine External Interrupt Pending)
    -- Bit  7: MTIP (Machine Timer Interrupt Pending)
    -- Bit  3: MSIP (Machine Software Interrupt Pending)

    s_mip_comb <= (
        11 => Irq_Ext_i, 
        7  => Irq_Timer_i, 
        3  => Irq_Soft_i, 
        others => '0'
    );

    -- ===========================================================================================================
    -- 2. Processo de Escrita (Síncrono)
    -- ===========================================================================================================

    process(Clk_i, Reset_i)
    begin
        if rising_edge(Clk_i) then
            if Reset_i = '1' then
                
                r_mtvec   <= (others => '0');
                r_mepc    <= (others => '0');
                r_mcause  <= (others => '0');
                r_mie     <= (others => '0');
                
                -- mstatus reset: MIE=0, MPIE=1, MPP=11 (Machine Mode)
                r_mstatus <= (others => '0');
                r_mstatus(c_MPIE_BIT) <= '1'; 
                r_mstatus(12 downto 11) <= "11"; -- Hardwired Machine Mode

            else
                
                -- -----------------------------------------------------------
                -- EVENTO 1: ENTRADA EM TRAP (Prioridade Máxima)
                -- -----------------------------------------------------------
                if Trap_Enter_i = '1' then
                    r_mepc   <= Trap_PC_i;    
                    r_mcause <= Trap_Cause_i;
                    
                    -- Salva contexto de interrupção
                    r_mstatus(c_MPIE_BIT) <= r_mstatus(c_MIE_BIT); -- Backup MIE -> MPIE
                    r_mstatus(c_MIE_BIT)  <= '0';                  -- Desabilita Interrupções Globais

                -- -----------------------------------------------------------
                -- EVENTO 2: RETORNO DE TRAP (MRET)
                -- -----------------------------------------------------------
                elsif Trap_Return_i = '1' then
                    -- Restaura contexto
                    r_mstatus(c_MIE_BIT)  <= r_mstatus(c_MPIE_BIT); -- Restaura MIE <- MPIE
                    r_mstatus(c_MPIE_BIT) <= '1';                   -- Define MPIE como 1 (padrão spec)

                -- -----------------------------------------------------------
                -- EVENTO 3: ESCRITA VIA SOFTWARE (CSRRW)
                -- -----------------------------------------------------------
                elsif Csr_Write_i = '1' then
                    case Csr_Addr_i is
                        when c_ADDR_MTVEC   => 

                            -- Força os bits de modo [1:0] para "00" (Direct Mode Only)
                            -- E garante alinhamento de 4 bytes na base.
                            r_mtvec(31 downto 2) <= Csr_WData_i(31 downto 2);
                            r_mtvec(1 downto 0)  <= "00"; -- Hardwired to Direct

                        when c_ADDR_MEPC    => r_mepc    <= Csr_WData_i;
                        when c_ADDR_MCAUSE  => r_mcause  <= Csr_WData_i;
                        when c_ADDR_MIE     => r_mie     <= Csr_WData_i;
                        when c_ADDR_MSTATUS => 

                            -- Proteção: Apenas bits writable (MIE, MPIE) podem ser alterados via SW
                            r_mstatus(c_MIE_BIT)  <= Csr_WData_i(c_MIE_BIT);  -- Bit 3
                            r_mstatus(c_MPIE_BIT) <= Csr_WData_i(c_MPIE_BIT); -- Bit 7
                            -- MPP (bits 12:11) deve ser sempre "11" (Machine) e não mudamos aqui.
                            -- Os demais bits são Hardwired 0.

                        when others         => null;
                    end case;
                end if;

            end if;
        end if;
    end process;

    -- ===========================================================================================================
    -- 3. Processo de Leitura (Assíncrono)
    -- ===========================================================================================================

    process(Csr_Addr_i, r_mtvec, r_mepc, r_mcause, r_mie, r_mstatus, s_mip_comb)
    begin

        -- Default: endereço é válido
        -- Sobrescrevemos na cláusula 'others'

        Csr_Valid_o <= '1';

        case Csr_Addr_i is

            when c_ADDR_MTVEC   => Csr_RData_o <= r_mtvec;
            when c_ADDR_MEPC    => Csr_RData_o <= r_mepc;
            when c_ADDR_MCAUSE  => Csr_RData_o <= r_mcause;
            when c_ADDR_MIE     => Csr_RData_o <= r_mie;
            when c_ADDR_MSTATUS => Csr_RData_o <= r_mstatus;
            when c_ADDR_MIP     => Csr_RData_o <= s_mip_comb; -- MIP é Read-Only (Hardware driven)

            when others => 

                -- Sinaliza CSR inexistente
                Csr_RData_o <= (others => '0');
                Csr_Valid_o <= '0';

        end case;
    end process;

    -- ===========================================================================================================
    -- 4. Saídas para Controle
    -- ===========================================================================================================

    Mtvec_o         <= r_mtvec;
    Mepc_o          <= r_mepc;
    Global_Irq_En_o <= r_mstatus(c_MIE_BIT);
    Mie_o           <= r_mie;
    Mip_o           <= s_mip_comb;

    -- ===========================================================================================================

end architecture; -- rtl 

------------------------------------------------------------------------------------------------------------------