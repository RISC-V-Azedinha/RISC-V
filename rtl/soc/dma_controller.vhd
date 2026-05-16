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
--             [ATUALIZADO: Edge Guard de Configuração e Pipeline de Leitura Desimpedido]
--
-- Autor     : André Maiolini
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_controller is
    port (
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        soc_en_i    : in  std_logic;

        cfg_addr_i  : in  std_logic_vector(3 downto 0);
        cfg_data_i  : in  std_logic_vector(31 downto 0);
        cfg_data_o  : out std_logic_vector(31 downto 0);
        cfg_we_i    : in  std_logic;
        cfg_vld_i   : in  std_logic;
        cfg_rdy_o   : out std_logic;

        m_rd_addr_o : out std_logic_vector(31 downto 0);
        m_rd_vld_o  : out std_logic;
        m_rd_data_i : in  std_logic_vector(31 downto 0);
        m_rd_rdy_i  : in  std_logic;

        m_wr_addr_o : out std_logic_vector(31 downto 0);
        m_wr_data_o : out std_logic_vector(31 downto 0);
        m_wr_we_o   : out std_logic;
        m_wr_vld_o  : out std_logic;
        m_wr_rdy_i  : in  std_logic;
        
        irq_done_o  : out std_logic
    );
end entity;

architecture rtl of dma_controller is

    signal r_src_addr       : unsigned(31 downto 0);
    signal r_dst_addr       : unsigned(31 downto 0);
    signal r_rd_count       : unsigned(31 downto 0);
    signal r_wr_count       : unsigned(31 downto 0);
    signal r_ctrl_fixed_dst : std_logic;
    signal r_busy           : std_logic;

    type fifo_t is array (0 to 7) of std_logic_vector(31 downto 0);
    signal r_fifo       : fifo_t;
    signal r_fifo_wr    : unsigned(2 downto 0);
    signal r_fifo_rd    : unsigned(2 downto 0);
    signal r_fifo_count : unsigned(3 downto 0);

    signal r_wr_stall : std_logic;

    signal s_rd_req : std_logic;
    signal s_wr_req : std_logic;

    -- Edge Guard
    signal r_cfg_rdy : std_logic := '0';

begin

    cfg_rdy_o <= r_cfg_rdy;

    s_rd_req <= '1' when (r_busy = '1' and r_rd_count > 0 and r_fifo_count < 8 and soc_en_i /= '0') else '0';
    s_wr_req <= '1' when (r_busy = '1' and r_wr_count > 0 and r_fifo_count > 0 and soc_en_i /= '0' and r_wr_stall = '0') else '0';

    m_rd_vld_o  <= s_rd_req;
    m_rd_addr_o <= std_logic_vector(r_src_addr);

    m_wr_vld_o  <= s_wr_req;
    m_wr_we_o   <= s_wr_req;
    m_wr_addr_o <= std_logic_vector(r_dst_addr);
    m_wr_data_o <= r_fifo(to_integer(r_fifo_rd));

    process(clk_i)
        variable v_fifo_push : boolean;
        variable v_fifo_pop  : boolean;
    begin
        if rising_edge(clk_i) then
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
                r_wr_stall       <= '0';
                r_cfg_rdy        <= '0';
                irq_done_o       <= '0';
            else
                v_fifo_push := false;
                v_fifo_pop  := false;
                irq_done_o  <= '0';

                -- 1. ESCRITA DE CONFIGURAÇÃO (Blindada)
                r_cfg_rdy <= '0';
                
                if cfg_vld_i = '1' and r_cfg_rdy = '0' then
                    r_cfg_rdy <= '1';
                    if cfg_we_i = '1' and r_busy = '0' then
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
                                    r_wr_stall   <= '0';
                                end if;
                                r_ctrl_fixed_dst <= cfg_data_i(1);
                            when others => null;
                        end case;
                    end if;
                end if;

                if r_busy = '1' and r_rd_count = 0 and r_wr_count = 0 and r_fifo_count = 0 then
                    r_busy <= '0';
                end if;

                -- 2. READ ENGINE (Pipeline Desimpedido)
                -- Sem o 'r_rd_stall', o DMA capta dados imediatamente ao receber o rdy.
                if s_rd_req = '1' and m_rd_rdy_i = '1' then
                    r_fifo(to_integer(r_fifo_wr)) <= m_rd_data_i;
                    r_fifo_wr  <= r_fifo_wr + 1;
                    r_src_addr <= r_src_addr + 4;
                    r_rd_count <= r_rd_count - 1;
                    v_fifo_push := true;
                end if;

                -- 3. WRITE ENGINE (Consumidor com Pacing mantido para IPs)
                if s_wr_req = '1' and m_wr_rdy_i = '1' then
                    r_fifo_rd <= r_fifo_rd + 1;
                    if r_ctrl_fixed_dst = '0' then
                        r_dst_addr <= r_dst_addr + 4;
                    end if;
                    r_wr_count <= r_wr_count - 1;
                    v_fifo_pop := true;
                    r_wr_stall <= '1'; 

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
        end if;
    end process;

    cfg_data_o <= std_logic_vector(r_src_addr) when cfg_addr_i = x"0" else
                  std_logic_vector(r_dst_addr) when cfg_addr_i = x"4" else
                  std_logic_vector(r_wr_count) when cfg_addr_i = x"8" else 
                  (0 => r_busy, 1 => r_ctrl_fixed_dst, others => '0') when cfg_addr_i = x"C" else
                  (others => '0');

end architecture;