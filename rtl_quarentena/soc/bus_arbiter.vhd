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
-- ARQUITETURA: Implementação comportamental do Árbitro do Barramento (Bus Arbiter)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of bus_arbiter is

    -- ============================================================================================================
    -- Máquina de Estados (FSM) - Prioridade Fixa
    -- ============================================================================================================

    --
    -- IDLE:     Estado ocioso. Nenhum mestre está acessando o barramento. Monitora requisições de ambos
    --           os mestres (m0_vld_i e m1_vld_i). Quando uma requisição chega, arbitra entre eles.
    --           Prioridade: Se ambos solicitam simultaneamente, DMA (M1) ganha.
    --
    -- GRANT_M0: Estado de concessão para a CPU (Master 0). O endereço, dados e sinais de controle
    --           provenientes da CPU são multiplexados para o escravo. O árbitro mantém este estado
    --           enquanto a CPU mantiver m0_vld_i ativo e aguarda o handshake com o escravo (s_rdy_i).
    --           Ao completar o handshake (s_rdy_i='1'), move para WAIT_M0.
    --
    -- GRANT_M1: Estado de concessão para o DMA (Master 1). Similar ao GRANT_M0, mas para o DMA.
    --           Todos os sinais do DMA são roteados até o escravo. 
    --           Ao completar o handshake (s_rdy_i='1'), move para WAIT_M1.
    --
    -- WAIT_M0:  Estado de espera de segurança para a CPU.
    --           Ocorre imediatamente após o slave confirmar a transação (Ready=1).
    --           Objetivo: Esperar que o Mestre (CPU) perceba o Ready e baixe o sinal Valid.
    --           Isso evita que o árbitro interprete o 'Valid' antigo como uma nova requisição (Double Write).
    --
    -- WAIT_M1:  Estado de espera de segurança para o DMA.
    --           Similar ao WAIT_M0, aguarda o DMA baixar o sinal Valid antes de liberar o barramento.
    --

    type state_type is (IDLE, GRANT_M0, GRANT_M1, WAIT_M0, WAIT_M1);
    signal current_state, next_state : state_type;

    -- ============================================================================================================
    -- Sinais Internos de Registro
    -- ============================================================================================================

    -- Sinais registrados para saída, implementando a multiplexação e roteamento de dados

    signal s_addr_r, s_wdata_r    : std_logic_vector(31 downto 0);
    signal s_we_r                 : std_logic_vector( 3 downto 0);
    signal s_vld_r                : std_logic;
    signal m0_rdata_r, m1_rdata_r : std_logic_vector(31 downto 0);
    signal m0_rdy_r, m1_rdy_r     : std_logic;

    -- ============================================================================================================

begin

    -- ========================================================================================================
    -- Conexão das Saídas Registradas (Multiplexagem Síncrona)
    -- ========================================================================================================

    -- Os sinais internos registrados são conectados diretamente às portas de saída.
    -- Isso garante que as mudanças de arbitragem ocorrem de forma síncrona com o clock.

    s_addr_o   <= s_addr_r;
    s_wdata_o  <= s_wdata_r;
    s_we_o     <= s_we_r;
    s_vld_o    <= s_vld_r;
    m0_rdata_o <= m0_rdata_r;
    m1_rdata_o <= m1_rdata_r;
    m0_rdy_o   <= m0_rdy_r;
    m1_rdy_o   <= m1_rdy_r;

    -- ========================================================================================================
    -- Registrador de Estado da FSM
    -- ========================================================================================================

    -- Transição síncrona entre estados baseada na lógica combinacional (next_state).
    -- Em reset, o árbitro retorna ao estado IDLE, pronto para arbitrar novamente.

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

    --
    -- Implementa a lógica de arbitragem com prioridade fixa.
    --
    -- Algoritmo Atualizado:
    -- 1. IDLE: Avalia requisições. DMA > CPU.
    --
    -- 2. GRANT_M1 / GRANT_M0: Mantém concessão até o handshake (s_rdy_i='1').
    --    Assim que o Ready chega, passamos para os estados de WAIT.
    --
    -- 3. WAIT_M1 / WAIT_M0: Segura o barramento (sem gerar novos Valids para o Slave)
    --    até que o Mestre coloque seu sinal de Valid em '0'. Só então voltamos para IDLE.
    --

    process(current_state, m0_vld_i, m1_vld_i, s_rdy_i)
    begin

        -- Default: manter estado
        next_state <= current_state;

        case current_state is
            when IDLE =>

                -- Arbitragem em IDLE: Prioridade DMA > CPU

                if m1_vld_i = '1' then
                    next_state <= GRANT_M1;  -- DMA solicita: aloca para DMA

                elsif m0_vld_i = '1' then
                    next_state <= GRANT_M0;  -- CPU solicita: aloca para CPU

                else
                    next_state <= IDLE;      -- Ninguém solicitou: permanece ocioso

                end if;

            when GRANT_M1 =>

                -- Se o mestre desistir antes do fim (Timeout ou Abort), volta pro IDLE

                if m1_vld_i = '0' then
                     next_state <= IDLE;

                -- Se o slave respondeu com Ready, a transação acabou
                -- Vamos para WAIT_M1 para garantir que o Valid do DMA desça
                elsif s_rdy_i = '1' then
                     next_state <= WAIT_M1;

                end if;

            when GRANT_M0 =>

                -- Se o mestre desistir antes do fim, volta pro IDLE
                if m0_vld_i = '0' then
                     next_state <= IDLE;

                -- Transação completa (Ready=1). Vai para espera.
                elsif s_rdy_i = '1' then
                     next_state <= WAIT_M0;

                end if;

            when WAIT_M1 =>

                -- Só libera o barramento quando o DMA baixar o Valid
                if m1_vld_i = '0' then
                    next_state <= IDLE;

                else
                    next_state <= WAIT_M1;

                end if;

            when WAIT_M0 =>

                -- Só libera o barramento quando a CPU baixar o Valid
                if m0_vld_i = '0' then
                    next_state <= IDLE;

                else
                    next_state <= WAIT_M0;

                end if;

            when others => next_state <= IDLE;
            
        end case;
    end process;

    -- ========================================================================================================
    -- Lógica de Saída Registrada (Multiplexagem e Roteamento de Dados)
    -- ========================================================================================================

    -- Este processo realiza a multiplexação sincronizada dos sinais de entrada e saída.

    -- Fluxo de Dados:
    --
    -- IDLE / WAITs: As saídas de controle (vld) retornam a zero para proteger o Slave.
    --
    -- GRANT_M1 (DMA tem concessão):
    --   - Saídas para escravo (s_*):  Provenientes do DMA (m1_*_i)
    --   - Saídas para DMA (m1_rdy_o): Resposta do escravo (s_rdy_i)
    --   - Dados de leitura (m1_rdata_o): Dados do escravo (s_rdata_i)
    --
    -- GRANT_M0 (CPU tem concessão):
    --   - Saídas para escravo (s_*):  Provenientes da CPU (m0_*_i)
    --   - Saídas para CPU (m0_rdy_o): Resposta do escravo (s_rdy_i)
    --   - Dados de leitura (m0_rdata_o): Dados do escravo (s_rdata_i)
    
    process(clk_i, rst_i)
    begin

        if rst_i = '1' then

            s_addr_r    <= (others => '0');
            s_wdata_r   <= (others => '0');
            s_we_r      <= (others => '0');
            s_vld_r     <= '0';
            m0_rdata_r  <= (others => '0');
            m1_rdata_r  <= (others => '0');
            m0_rdy_r    <= '0';
            m1_rdy_r    <= '0';

        elsif rising_edge(clk_i) then

            -- Defaults: Todas as saídas retornam a zero

            s_addr_r    <= (others => '0');
            s_wdata_r   <= (others => '0');
            s_we_r      <= (others => '0');
            s_vld_r     <= '0';
            m0_rdy_r    <= '0';
            m1_rdy_r    <= '0';
            m0_rdata_r  <= (others => '0');
            m1_rdata_r  <= (others => '0');

            case current_state is

                when IDLE => null; -- Barramento desocupado

                when GRANT_M1 =>   -- DMA tem prioridade e concessão. Roteia sinais do DMA para o escravo.
                    
                    s_addr_r    <= m1_addr_i;      -- Endereço do DMA para escravo
                    s_wdata_r   <= m1_wdata_i;     -- Dados de escrita do DMA para escravo
                    s_we_r      <= m1_we_i;        -- Sinal de escrita do DMA
                    s_vld_r     <= m1_vld_i;       -- Validação da requisição do DMA
                    m1_rdy_r    <= s_rdy_i;        -- Ready do escravo retorna para DMA
                    m1_rdata_r  <= s_rdata_i;      -- Dados de leitura do escravo para DMA

                when GRANT_M0 =>   -- CPU tem concessão. Roteia sinais da CPU para o escravo.

                    s_addr_r    <= m0_addr_i;      -- Endereço da CPU para escravo
                    s_wdata_r   <= m0_wdata_i;     -- Dados de escrita da CPU para escravo
                    s_we_r      <= m0_we_i;        -- Sinal de escrita da CPU
                    s_vld_r     <= m0_vld_i;       -- Validação da requisição da CPU
                    m0_rdy_r    <= s_rdy_i;        -- Ready do escravo retorna para CPU
                    m0_rdata_r  <= s_rdata_i;      -- Dados de leitura do escravo para CPU

                -- Nos estados de WAIT, confiamos nos Defaults definidos acima (s_vld_r <= '0').
                -- Isso impede que o Slave receba um pulso fantasma de escrita.
                
                when WAIT_M1 => null;
                when WAIT_M0 => null;

                when others => null;
                
            end case;

        end if;

    end process;

    -- ============================================================================================================

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------
