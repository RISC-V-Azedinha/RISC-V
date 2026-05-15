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
-- Descrição : Controlador DMA Avançado 1D (Mem-to-Mem / Mem-to-IP)
--             Arquitetura Produtor-Consumidor totalmente desacoplada via FIFO interna.
--             Com Pipeline de Leitura de 2 ciclos (Retenção de Crossbar) para BRAMs.
--
-- Autor     : André Maiolini
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_controller is
    port (
        -- Sinais de Controle (Globais)
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        soc_en_i    : in  std_logic;

        -- Interface Slave (Configuração pela CPU)
        cfg_addr_i  : in  std_logic_vector(3 downto 0);
        cfg_data_i  : in  std_logic_vector(31 downto 0);
        cfg_data_o  : out std_logic_vector(31 downto 0);
        cfg_we_i    : in  std_logic;
        cfg_vld_i   : in  std_logic;
        cfg_rdy_o   : out std_logic;

        -- Interface Master 1: READ (Source)
        m_rd_addr_o : out std_logic_vector(31 downto 0);
        m_rd_vld_o  : out std_logic;
        m_rd_data_i : in  std_logic_vector(31 downto 0);
        m_rd_rdy_i  : in  std_logic;

        -- Interface Master 2: WRITE (Destination)
        m_wr_addr_o : out std_logic_vector(31 downto 0);
        m_wr_data_o : out std_logic_vector(31 downto 0);
        m_wr_we_o   : out std_logic;
        m_wr_vld_o  : out std_logic;
        m_wr_rdy_i  : in  std_logic;
        
        -- Interrupção
        irq_done_o  : out std_logic
    );
end entity;

architecture rtl of dma_controller is

    -- Registradores de Configuração
    signal r_src_addr       : unsigned(31 downto 0);
    signal r_dst_addr       : unsigned(31 downto 0);
    signal r_rd_count       : unsigned(31 downto 0);
    signal r_wr_count       : unsigned(31 downto 0);
    signal r_ctrl_fixed_dst : std_logic;
    signal r_busy           : std_logic;

    -- FIFO Interna (Circular Buffer - Profundidade 8)
    type fifo_t is array (0 to 7) of std_logic_vector(31 downto 0);
    signal r_fifo       : fifo_t;
    signal r_fifo_wr    : unsigned(2 downto 0);
    signal r_fifo_rd    : unsigned(2 downto 0);
    signal r_fifo_count : unsigned(3 downto 0);

    -- Pacing Stalls
    signal r_rd_stall : std_logic;
    signal r_wr_stall : std_logic;

    -- Sinais Combinacionais de Requisição
    signal s_rd_req : std_logic;
    signal s_wr_req : std_logic;

begin

    -- ============================================================================================================
    -- LÓGICA DE DESACOPLAMENTO E ROTEAMENTO
    -- ============================================================================================================

    -- Produtor: Pede leitura se houver contagem e espaço na FIFO.
    -- FIX: Removido o bloqueio combinacional do stall para FORÇAR o barramento a ficar retido!
    s_rd_req <= '1' when (r_busy = '1' and r_rd_count > 0 and r_fifo_count < 8 and soc_en_i /= '0') else '0';

    -- Consumidor: Pede escrita se houver contagem, dado na FIFO e NÃO estiver em ciclo de stall
    s_wr_req <= '1' when (r_busy = '1' and r_wr_count > 0 and r_fifo_count > 0 and soc_en_i /= '0' and r_wr_stall = '0') else '0';

    m_rd_vld_o  <= s_rd_req;
    m_rd_addr_o <= std_logic_vector(r_src_addr);

    m_wr_vld_o  <= s_wr_req;
    m_wr_we_o   <= s_wr_req;
    m_wr_addr_o <= std_logic_vector(r_dst_addr);
    m_wr_data_o <= r_fifo(to_integer(r_fifo_rd));

    -- ============================================================================================================
    -- MÁQUINA DE CONTROLE SÍNCRONA
    -- ============================================================================================================
    process(clk_i, rst_i)
        variable v_fifo_push : boolean;
        variable v_fifo_pop  : boolean;
    begin
        if rst_i = '1' then
            r_src_addr       <= (others => '0');
            r_dst_addr       <= (others => '0');
            r_rd_count       <= (others => '0');
            r_wr_count       <= (others => '0');
            r_ctrl_fixed_dst <= '0';
            r_busy           <= '0';
            r_fifo_wr        <= (others => '0');
            r_fifo_rd        <= (others => '0');
            r_fifo_count     <= (others => '0');
            r_rd_stall       <= '0';
            r_wr_stall       <= '0';
            irq_done_o       <= '0';

        elsif rising_edge(clk_i) then
            v_fifo_push := false;
            v_fifo_pop  := false;
            irq_done_o  <= '0';

            -- 1. ESCRITA DE CONFIGURAÇÃO
            if cfg_vld_i = '1' and cfg_we_i = '1' and r_busy = '0' then
                case cfg_addr_i is
                    when x"0" => r_src_addr <= unsigned(cfg_data_i);
                    when x"4" => r_dst_addr <= unsigned(cfg_data_i);
                    when x"8" => 
                        r_rd_count <= unsigned(cfg_data_i);
                        r_wr_count <= unsigned(cfg_data_i);
                    when x"C" =>
                        if cfg_data_i(0) = '1' then
                            r_busy       <= '1';
                            r_fifo_wr    <= (others => '0');
                            r_fifo_rd    <= (others => '0');
                            r_fifo_count <= (others => '0');
                            r_rd_stall   <= '0';
                            r_wr_stall   <= '0';
                        end if;
                        r_ctrl_fixed_dst <= cfg_data_i(1);
                    when others => null;
                end case;
            end if;

            if r_busy = '1' and r_rd_count = 0 and r_wr_count = 0 and r_fifo_count = 0 then
                r_busy <= '0';
            end if;

            -- 2. READ ENGINE (Produtor) - Safe 2-Cycle Pipeline
            if s_rd_req = '1' and m_rd_rdy_i = '1' then
                if r_rd_stall = '0' then
                    -- FASE 1: Memória avalia o endereço. VLD continua alto na próxima borda!
                    r_rd_stall <= '1';
                else
                    -- FASE 2: Com a Crossbar ainda conectada, capturamos o dado estável.
                    r_fifo(to_integer(r_fifo_wr)) <= m_rd_data_i;
                    r_fifo_wr  <= r_fifo_wr + 1;
                    r_src_addr <= r_src_addr + 4;
                    r_rd_count <= r_rd_count - 1;
                    v_fifo_push := true;
                    r_rd_stall <= '0'; -- Prepara para a próxima palavra
                end if;
            end if;

            -- 3. WRITE ENGINE (Consumidor)
            if s_wr_req = '1' and m_wr_rdy_i = '1' then
                r_fifo_rd <= r_fifo_rd + 1;
                
                if r_ctrl_fixed_dst = '0' then
                    r_dst_addr <= r_dst_addr + 4;
                end if;
                
                r_wr_count <= r_wr_count - 1;
                v_fifo_pop := true;
                r_wr_stall <= '1'; -- Pacing seguro para a NPU

                if r_wr_count = 1 then
                    r_busy <= '0';
                    irq_done_o <= '1';
                end if;
            elsif r_wr_stall = '1' then
                r_wr_stall <= '0';
            end if;

            -- 4. ATUALIZAÇÃO DO ESTADO DA FIFO
            if v_fifo_push and not v_fifo_pop then
                r_fifo_count <= r_fifo_count + 1;
            elsif v_fifo_pop and not v_fifo_push then
                r_fifo_count <= r_fifo_count - 1;
            end if;

        end if;
    end process;

    -- ============================================================================================================
    -- LEITURA DE CONFIGURAÇÃO (Slave Interface)
    -- ============================================================================================================
    
    cfg_data_o <= std_logic_vector(r_src_addr) when cfg_addr_i = x"0" else
                  std_logic_vector(r_dst_addr) when cfg_addr_i = x"4" else
                  std_logic_vector(r_wr_count) when cfg_addr_i = x"8" else 
                  (0 => r_busy, 1 => r_ctrl_fixed_dst, others => '0') when cfg_addr_i = x"C" else
                  (others => '0');
                  
    cfg_rdy_o <= '1';

end architecture;