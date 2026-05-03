------------------------------------------------------------------------------------------------------------------
--
-- File: dma_controller.vhd
--
-- ██████╗ ███╗   ███╗ █████╗ 
-- ██╔══██╗████╗ ████║██╔══██╗
-- ██║  ██║██╔████╔██║███████║
-- ██║  ██║██║╚██╔╝██║██╔══██║
-- ██████╔╝██║ ╚═╝ ██║██║  ██║
-- ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
--                            
-- Descrição : Controlador DMA Simples 1D (Mem-to-Mem / Mem-to-IP)
--             Suporta modo de destino fixo (para FIFOs) ou incremental.
--
-- Autor     : [André Maiolini]
-- Data      : [18/01/2026]   
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do controlador DMA (Direct Memory Access)
-------------------------------------------------------------------------------------------------------------------

entity dma_controller is

    port (

        -- ========================================================================================================
        -- Sinais de Controle (Globais)
        -- ========================================================================================================

        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        soc_en_i    : in  std_logic;

        -- ========================================================================================================
        -- Interface Slave (Configuração pela CPU)
        -- ========================================================================================================
        
        cfg_addr_i  : in  std_logic_vector(3 downto 0);  -- Apenas offset (4 regs)
        cfg_data_i  : in  std_logic_vector(31 downto 0);
        cfg_data_o  : out std_logic_vector(31 downto 0);
        cfg_we_i    : in  std_logic;
        cfg_vld_i   : in  std_logic;
        cfg_rdy_o   : out std_logic;

        -- ========================================================================================================
        -- Interface Master (Acesso ao Barramento)
        -- ========================================================================================================
        
        -- A decisão sobre o uso do barramento em configuração multi-master bus,
        -- será decidida pelo bus_arbiter

        m_addr_o    : out std_logic_vector(31 downto 0);
        m_data_o    : out std_logic_vector(31 downto 0);
        m_data_i    : in  std_logic_vector(31 downto 0);
        m_we_o      : out std_logic;
        m_vld_o     : out std_logic;
        m_rdy_i     : in  std_logic;
        
        -- Interrupção (sinal de interrupção)
        irq_done_o  : out std_logic

        -- ========================================================================================================

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação comportamental do controlador DMA (Direct Memory Access)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of dma_controller is

    -- Registradores Mapeados em Memória --------------------------------------------------------------------------

    -- 0x00: SRC_ADDR (Endereço de Origem)
    -- 0x04: DST_ADDR (Endereço de Destino)
    -- 0x08: COUNT    (Número de palavras de 32 bits a transferir)
    -- 0x0C: CONTROL  (Bit 0: Start, Bit 1: Fixed_Dst, Bit 2: Busy/Status)

    signal r_src_addr  : unsigned(31 downto 0);
    signal r_dst_addr  : unsigned(31 downto 0);
    signal r_count     : unsigned(31 downto 0);
    
    -- Flags de Controle

    signal r_ctrl_fixed_dst : std_logic; -- 1 = Não incrementa endereço de destino (NPU)
    signal r_busy           : std_logic;

    -- Buffer de Dados interno

    signal r_data_buffer    : std_logic_vector(31 downto 0);

    -- Máquina de Estados -----------------------------------------------------------------------------------------

    type state_type is (

        -- IDLE: o DMA está ocioso, o sinal r_busy desativado, a CPU pode escrever nos registradores,
        -- assim que a CPU escreve '1' em START (0x0C, Bit 0) o DMA levanta a flag r_busy e vai para o
        -- próximo estado.

        IDLE,    
        
        -- READ_REQ: o DMA coloca o endereço 'r_src_addr' no barramento e levanta 'm_vld_o', indicando
        -- que quer ler. Ele espera até que o barramento responda com m_rdy_i. Nesse momento, o DMA captura
        -- o dado vindo de m_data_i e guarda num registrador temporário (r_data_buffer) e transita
        -- para o estado WRITE_REQ.

        READ_REQ,     
        
        -- READ_WAIT: Estado de espera intermediário.
        -- O DMA baixa o sinal 'm_vld_o' por um ciclo. Isso é necessário para sinalizar ao bus_arbiter
        -- que a transação de leitura terminou, permitindo que ele saia do estado de travamento (WAIT_M1).
        
        READ_WAIT,

        -- WRITE_REQ: o DMA coloca o endereço 'r_dst_addr' e o dado guardado no 'r_data_buffer' no barramento.
        -- Levanta as flags 'm_vld_o' e 'm_we_o' - sinalizando requisição de escrita. Então, aguarda a 
        -- confirmação com 'm_rdy_i'. Por fim, transita parar o estado CHECK_DONE. 

        WRITE_REQ,             

        -- CHECK_DONE: neste estado, o DMA decrementa o contador 'r_count', incrementa o endereço de origem 
        -- 'r_src_addr' (+4 bytes) e aplica a lógica de destino: se 'fixed_dst = 0', incrementa 'r_dst_addr' (+4);
        -- caso 'fixed_dst = 1', mantém 'r_dst_addr' (para buffer FIFO).

        CHECK_DONE

    );

    signal current_state, next_state : state_type;

    ---------------------------------------------------------------------------------------------------------------

begin

    -- ============================================================================================================
    -- Registradores e Atualizações de Estado
    -- ============================================================================================================

    process(clk_i, rst_i)
    begin
        if rst_i = '1' then

            r_src_addr       <= (others => '0');
            r_dst_addr       <= (others => '0');
            r_count          <= (others => '0');
            r_ctrl_fixed_dst <= '0';
            r_busy           <= '0'; -- Auto-clears on finish
            current_state    <= IDLE;
            r_data_buffer    <= (others => '0');

        elsif rising_edge(clk_i) then

            -- Atualiza Estado
            current_state <= next_state;
            
            -- Limpa Busy quando termina
            if current_state = CHECK_DONE and next_state = IDLE then
                r_busy <= '0';
            end if;

            -- Escrita de Configuração (Apenas se não Busy)
            if cfg_vld_i = '1' and cfg_we_i = '1' and r_busy = '0' then
                case cfg_addr_i is
                    when x"0" => r_src_addr <= unsigned(cfg_data_i);
                    when x"4" => r_dst_addr <= unsigned(cfg_data_i);
                    when x"8" => r_count    <= unsigned(cfg_data_i);
                    when x"C" =>
                        -- Bit 0: Start (Dispara a FSM)
                        if cfg_data_i(0) = '1' then
                            r_busy <= '1';
                        end if;
                        -- Bit 1: Fixed Destination (Para NPU)
                        r_ctrl_fixed_dst <= cfg_data_i(1);
                    when others => null;
                end case;
            end if;

            -- Atualização interna de endereços pela FSM (Durante a transferência)
            if current_state = CHECK_DONE and r_count > 0 then
                r_src_addr <= r_src_addr + 4; -- Sempre incrementa origem (RAM)
                if r_ctrl_fixed_dst = '0' then
                    r_dst_addr <= r_dst_addr + 4; -- Só incrementa destino se não for fixo
                end if;
                r_count <= r_count - 1;
            end if;

            -- Captura de Dados (Data Path)
            -- Se o barramento indicou Ready no ciclo READ_REQ, guardamos o dado
            if current_state = READ_REQ and m_rdy_i = '1' then
                r_data_buffer <= m_data_i;
            end if;

        end if;
    end process;

    -- Leitura dos Registradores
    cfg_data_o <= std_logic_vector(r_src_addr) when cfg_addr_i = x"0" else
                  std_logic_vector(r_dst_addr) when cfg_addr_i = x"4" else
                  std_logic_vector(r_count)    when cfg_addr_i = x"8" else
                  (0 => r_busy, 1 => r_ctrl_fixed_dst, others => '0') when cfg_addr_i = x"C" else
                  (others => '0');

    -- Ready da config é sempre 1 (Single cycle write/read)
    cfg_rdy_o <= '1';


    -- ============================================================================================================
    -- Lógica Combinacional: Próximo Estado e Saídas do Mestre
    -- ============================================================================================================

    process(current_state, r_busy, r_count, m_rdy_i, r_src_addr, r_dst_addr, r_data_buffer, soc_en_i)
    begin
        next_state <= current_state;
        
        -- Defaults
        m_vld_o <= '0';
        m_we_o  <= '0';
        m_addr_o <= (others => '0');
        m_data_o <= (others => '0');
        irq_done_o <= '0';

        case current_state is
            
            when IDLE =>
                if r_busy = '1' then
                    if soc_en_i = '0' then
                        next_state <= IDLE; 
                    elsif r_count = 0 then
                        next_state <= CHECK_DONE; 
                    else
                        next_state <= READ_REQ;
                    end if;
                end if;

            when READ_REQ =>
                m_addr_o <= std_logic_vector(r_src_addr);
                m_vld_o  <= '1';
                m_we_o   <= '0'; -- Leitura
                
                if m_rdy_i = '1' then
                    -- Vamos para READ_WAIT em vez de WRITE_REQ diretamente.
                    -- Isso força m_vld_o a '0' por um ciclo, satisfazendo o Bus Arbiter.
                    next_state <= READ_WAIT;
                end if;

            when READ_WAIT =>
                
                -- m_vld_o está em '0' (pelos defaults).
                -- O Bus Arbiter verá isso, sairá do estado de travamento e estará pronto
                -- para aceitar a nova requisição (WRITE) no próximo ciclo.
                next_state <= WRITE_REQ;

            when WRITE_REQ =>
                m_addr_o <= std_logic_vector(r_dst_addr);
                m_data_o <= r_data_buffer;
                m_vld_o  <= '1';
                m_we_o   <= '1'; -- Escrita

                if m_rdy_i = '1' then
                   next_state <= CHECK_DONE; 
                end if;

            when CHECK_DONE =>
                -- Se count for 1 (último item transferido) OU 0 (caso borda), termina.
                -- O contador só será decrementado no rising_edge, mas a decisão de estado olha o valor atual.
                if r_count <= 1 then
                    next_state <= IDLE;
                    irq_done_o <= '1';
                elsif soc_en_i = '0' then
                    next_state <= CHECK_DONE; 
                else
                    next_state <= READ_REQ;
                end if;
                
            when others => next_state <= IDLE;
            
        end case;
    end process;

    -- ============================================================================================================

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------