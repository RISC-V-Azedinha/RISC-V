------------------------------------------------------------------------------------------------------------------
--
-- File: bus_arbiter.vhd
--
--  █████╗ ██████╗ ██████╗ ██╗████████╗███████╗██████╗ 
-- ██╔══██╗██╔══██╗██╔══██╗██║╚══██╔══╝██╔════╝██╔══██╗
-- ███████║██████╔╝██████╔╝██║   ██║   █████╗  ██████╔╝
-- ██╔══██║██╔══██╗██╔══██╗██║   ██║   ██╔══╝  ██╔══██╗
-- ██║  ██║██║  ██║██████╔╝██║   ██║   ███████╗██║  ██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
--                                                     
-- Descrição  : Árbitro de Barramento com Prioridade Fixa
--              Multiplexação entre dois mestres (CPU e DMA) para um único escravo
--              Implementa lógica de handshake com prioridade: DMA > CPU
--
-- Função     : Arbitrar acesso ao barramento compartilhado entre:
--              - Master 0 (CPU):  Processador RISC-V (Baixa Prioridade)
--              - Master 1 (DMA):  Controlador de Acesso Direto à Memória (Alta Prioridade)
--              - Slave:           Interconnect do Sistema
--
-- Estratégia : Prioridade Fixa com FSM de 5 estados (IDLE, GRANTs e WAITs)
--              O DMA sempre toma precedência sobre a CPU quando ambos solicitam acesso.
--
-- Autor      : [André Maiolini]
-- Data       : [18/01/2026]
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Árbitro do Barramento (Bus Arbiter)
-------------------------------------------------------------------------------------------------------------------

entity bus_arbiter is
    port (

        -- Clock e reset
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;

        -- Master 0: CPU (Baixa Prioridade)
        m0_addr_i   : in  std_logic_vector(31 downto 0);
        m0_wdata_i  : in  std_logic_vector(31 downto 0);
        m0_we_i     : in  std_logic_vector(3 downto 0);
        m0_vld_i    : in  std_logic;
        m0_rdata_o  : out std_logic_vector(31 downto 0);
        m0_rdy_o    : out std_logic;

        -- Master 1: DMA (Alta Prioridade)
        m1_addr_i   : in  std_logic_vector(31 downto 0);
        m1_wdata_i  : in  std_logic_vector(31 downto 0);
        m1_we_i     : in  std_logic_vector(3 downto 0);
        m1_vld_i    : in  std_logic;
        m1_rdata_o  : out std_logic_vector(31 downto 0);
        m1_rdy_o    : out std_logic;

        -- Slave
        s_addr_o    : out std_logic_vector(31 downto 0);
        s_wdata_o   : out std_logic_vector(31 downto 0);
        s_we_o      : out std_logic_vector(3 downto 0);
        s_vld_o     : out std_logic;
        s_rdata_i   : in  std_logic_vector(31 downto 0);
        s_rdy_i     : in  std_logic

    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação otimizada do Árbitro do Barramento (Bus Arbiter)
-------------------------------------------------------------------------------------------------------------------
architecture rtl of bus_arbiter is

    -- FSM simplificada sem estados de WAIT mortos
    type state_type is (IDLE, GRANT_M0, GRANT_M1);
    signal current_state, next_state : state_type;

begin

    -- ========================================================================================================
    -- Registrador de Estado da FSM
    -- ========================================================================================================
    process(clk_i, rst_i)
    begin
        if rst_i = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk_i) then
            current_state <= next_state;
        end if;
    end process;

    -- ========================================================================================================
    -- Lógica Combinacional: Próximo Estado (FSM)
    -- ========================================================================================================
    process(current_state, m0_vld_i, m1_vld_i)
    begin
        next_state <= current_state;
        
        case current_state is
            when IDLE =>
                -- Arbitragem: DMA (M1) tem prioridade sobre CPU (M0)
                if m1_vld_i = '1' then
                    next_state <= GRANT_M1;
                elsif m0_vld_i = '1' then
                    next_state <= GRANT_M0;
                else
                    next_state <= IDLE;
                end if;

            when GRANT_M1 =>
                -- Mantém a concessão até que o DMA baixe o sinal Valid (Fim da transação ou burst)
                if m1_vld_i = '0' then
                    -- Otimização: Se a CPU estiver na fila, já concede direto
                    if m0_vld_i = '1' then
                        next_state <= GRANT_M0;
                    else
                        next_state <= IDLE;
                    end if;
                end if;

            when GRANT_M0 =>
                -- Mantém a concessão até que a CPU baixe o sinal Valid
                if m0_vld_i = '0' then
                    -- Otimização: Se o DMA estiver na fila, já concede direto
                    if m1_vld_i = '1' then
                        next_state <= GRANT_M1;
                    else
                        next_state <= IDLE;
                    end if;
                end if;

            when others => 
                next_state <= IDLE;
                
        end case;
    end process;

    -- ========================================================================================================
    -- Lógica de Saída Combinacional (Multiplexagem Direta sem Atraso de Clock)
    -- ========================================================================================================
    -- Ao removermos o rising_edge(clk_i) daqui, os sinais fluem instantaneamente
    -- entre o Master e o Slave assim que o estado é concedido.
    process(current_state, m0_addr_i, m0_wdata_i, m0_we_i, m0_vld_i,
            m1_addr_i, m1_wdata_i, m1_we_i, m1_vld_i, s_rdata_i, s_rdy_i)
    begin
        -- Defaults para evitar a inferência de Latch pelo sintetizador
        s_addr_o   <= (others => '0');
        s_wdata_o  <= (others => '0');
        s_we_o     <= (others => '0');
        s_vld_o    <= '0';
        m0_rdata_o <= (others => '0');
        m1_rdata_o <= (others => '0');
        m0_rdy_o   <= '0';
        m1_rdy_o   <= '0';

        if current_state = GRANT_M1 then
            -- Roteia sinais do DMA (Alta Prioridade)
            s_addr_o   <= m1_addr_i;
            s_wdata_o  <= m1_wdata_i;
            s_we_o     <= m1_we_i;
            s_vld_o    <= m1_vld_i;
            m1_rdata_o <= s_rdata_i;
            m1_rdy_o   <= s_rdy_i;
            
        elsif current_state = GRANT_M0 then
            -- Roteia sinais da CPU (Baixa Prioridade)
            s_addr_o   <= m0_addr_i;
            s_wdata_o  <= m0_wdata_i;
            s_we_o     <= m0_we_i;
            s_vld_o    <= m0_vld_i;
            m0_rdata_o <= s_rdata_i;
            m0_rdy_o   <= s_rdy_i;
        end if;
        
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------
