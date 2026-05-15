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
--             Adaptado para a nova Crossbar Interconnect com Dual-Master (Read/Write).
--
-- Autor     : André Maiolini
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
        -- Interface Master 1: READ (Source)
        -- ========================================================================================================
        m_rd_addr_o : out std_logic_vector(31 downto 0);
        m_rd_vld_o  : out std_logic;
        m_rd_data_i : in  std_logic_vector(31 downto 0);
        m_rd_rdy_i  : in  std_logic;

        -- ========================================================================================================
        -- Interface Master 2: WRITE (Destination)
        -- ========================================================================================================
        m_wr_addr_o : out std_logic_vector(31 downto 0);
        m_wr_data_o : out std_logic_vector(31 downto 0);
        m_wr_we_o   : out std_logic;
        m_wr_vld_o  : out std_logic;
        m_wr_rdy_i  : in  std_logic;
        
        -- Interrupção (sinal de interrupção)
        irq_done_o  : out std_logic
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação Ágil do Controlador DMA (Sem estados mortos)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of dma_controller is

    signal r_src_addr  : unsigned(31 downto 0);
    signal r_dst_addr  : unsigned(31 downto 0);
    signal r_count     : unsigned(31 downto 0);
    
    signal r_ctrl_fixed_dst : std_logic;
    signal r_busy           : std_logic;
    signal r_data_buffer    : std_logic_vector(31 downto 0);

    type state_type is (IDLE, READ_REQ, WRITE_REQ);
    signal current_state, next_state : state_type;

begin

    -- ============================================================================================================
    -- Registradores e Atualizações Síncronas (Data Path)
    -- ============================================================================================================
    process(clk_i, rst_i)
    begin
        if rst_i = '1' then
            r_src_addr       <= (others => '0');
            r_dst_addr       <= (others => '0');
            r_count          <= (others => '0');
            r_ctrl_fixed_dst <= '0';
            r_busy           <= '0';
            current_state    <= IDLE;
            r_data_buffer    <= (others => '0');

        elsif rising_edge(clk_i) then
            -- 1. Atualiza Estado
            current_state <= next_state;

            -- 2. Escrita de Configuração (Pela CPU, apenas se não Busy)
            if cfg_vld_i = '1' and cfg_we_i = '1' and r_busy = '0' then
                case cfg_addr_i is
                    when x"0" => r_src_addr <= unsigned(cfg_data_i);
                    when x"4" => r_dst_addr <= unsigned(cfg_data_i);
                    when x"8" => r_count    <= unsigned(cfg_data_i);
                    when x"C" =>
                        if cfg_data_i(0) = '1' then
                            r_busy <= '1';
                        end if;
                        r_ctrl_fixed_dst <= cfg_data_i(1);
                    when others => null;
                end case;
            end if;

            -- Limpeza automática do r_busy se a CPU enviar Start com Count = 0
            if r_busy = '1' and r_count = 0 and current_state = IDLE then
                r_busy <= '0';
            end if;

            -- 3. Captura de Dados da RAM (Porta de Leitura)
            if current_state = READ_REQ and m_rd_rdy_i = '1' then
                r_data_buffer <= m_rd_data_i;
            end if;

            -- 4. Atualização de endereços e contadores "On-the-Fly" (Porta de Escrita)
            if current_state = WRITE_REQ and m_wr_rdy_i = '1' then
                if r_count > 0 then
                    r_src_addr <= r_src_addr + 4;
                    if r_ctrl_fixed_dst = '0' then
                        r_dst_addr <= r_dst_addr + 4;
                    end if;
                    r_count <= r_count - 1;
                end if;
                
                -- Se for a última palavra, baixa a flag Busy imediatamente
                if r_count <= 1 then
                    r_busy <= '0';
                end if;
            end if;

        end if;
    end process;

    cfg_data_o <= std_logic_vector(r_src_addr) when cfg_addr_i = x"0" else
                  std_logic_vector(r_dst_addr) when cfg_addr_i = x"4" else
                  std_logic_vector(r_count)    when cfg_addr_i = x"8" else
                  (0 => r_busy, 1 => r_ctrl_fixed_dst, others => '0') when cfg_addr_i = x"C" else
                  (others => '0');
                  
    cfg_rdy_o <= '1';

    -- ============================================================================================================
    -- Lógica Combinacional: Próximo Estado e Saídas dos Mestres
    -- ============================================================================================================
    process(current_state, r_busy, r_count, m_rd_rdy_i, m_wr_rdy_i, r_src_addr, r_dst_addr, r_data_buffer, soc_en_i)
    begin
        next_state  <= current_state;
        
        -- Sinais Default Master Read
        m_rd_vld_o  <= '0';
        m_rd_addr_o <= (others => '0');
        
        -- Sinais Default Master Write
        m_wr_vld_o  <= '0';
        m_wr_we_o   <= '0';
        m_wr_addr_o <= (others => '0');
        m_wr_data_o <= (others => '0');
        
        irq_done_o  <= '0';

        case current_state is
            
            when IDLE =>
                if r_busy = '1' and r_count > 0 and soc_en_i /= '0' then
                    next_state <= READ_REQ;
                end if;

            when READ_REQ =>
                m_rd_addr_o <= std_logic_vector(r_src_addr);
                m_rd_vld_o  <= '1';
                
                if m_rd_rdy_i = '1' then
                    next_state <= WRITE_REQ;
                end if;

            when WRITE_REQ =>
                m_wr_addr_o <= std_logic_vector(r_dst_addr);
                m_wr_data_o <= r_data_buffer;
                m_wr_vld_o  <= '1';
                m_wr_we_o   <= '1'; 

                if m_wr_rdy_i = '1' then
                    if r_count <= 1 then
                        next_state <= IDLE;
                        irq_done_o <= '1';
                    elsif soc_en_i /= '0' then
                        next_state <= READ_REQ;
                    end if;
                end if;
                
            when others => 
                next_state <= IDLE;
            
        end case;
    end process;

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------