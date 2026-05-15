------------------------------------------------------------------------------------------------------------------
-- 
-- File: bus_interconnect.vhd
-- 
--  ██████╗ ██╗   ██╗███████╗ 
--  ██╔══██╗██║   ██║██╔════╝ 
--  ██████╔╝██║   ██║███████╗ 
--  ██╔══██╗██║   ██║╚════██║ 
--  ██████╔╝╚██████╔╝███████║ 
--  ╚═════╝  ╚═════╝ ╚══════╝ 
-- 
-- Descrição : Interconectador de Barramento (Crossbar) para o SoC RISC-V.
--             Arquitetura Dual-Master + Sticky Arbitration refatorada usando
--             Records e Arrays (VHDL-2008).
-- 
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_interconnect is
    port (
        -- ========================================================================================
        -- SINAIS GERAIS DO SISTEMA
        -- ========================================================================================
        clk_i               : in  std_logic;
        rst_i               : in  std_logic;

        -- ========================================================================================
        -- INTERFACE CORE: IMem (Instruções - Porta A) - Bypassa o Crossbar principal
        -- ========================================================================================
        imem_addr_i         : in  std_logic_vector(31 downto 0);
        imem_data_o         : out std_logic_vector(31 downto 0);
        imem_vld_i          : in  std_logic; 
        imem_rdy_o          : out std_logic;

        -- ========================================================================================
        -- INTERFACE CROSSBAR: MESTRES DE DADOS (Portas B)
        -- ========================================================================================
        -- Master 0: CPU
        cpu_addr_i          : in  std_logic_vector(31 downto 0);
        cpu_data_i          : in  std_logic_vector(31 downto 0);
        cpu_we_i            : in  std_logic_vector( 3 downto 0);
        cpu_vld_i           : in  std_logic;
        cpu_data_o          : out std_logic_vector(31 downto 0);
        cpu_rdy_o           : out std_logic;

        -- Master 1: DMA Read (Apenas Leitura)
        dma_rd_addr_i       : in  std_logic_vector(31 downto 0);
        dma_rd_vld_i        : in  std_logic;
        dma_rd_data_o       : out std_logic_vector(31 downto 0);
        dma_rd_rdy_o        : out std_logic;

        -- Master 2: DMA Write (Apenas Escrita)
        dma_wr_addr_i       : in  std_logic_vector(31 downto 0);
        dma_wr_data_i       : in  std_logic_vector(31 downto 0);
        dma_wr_we_i         : in  std_logic;
        dma_wr_vld_i        : in  std_logic;
        dma_wr_rdy_o        : out std_logic;

        -- ========================================================================================
        -- INTERFACES DOS ESCRAVOS
        -- ========================================================================================
        -- Boot ROM
        rom_addr_a_o        : out std_logic_vector(31 downto 0);
        rom_data_a_i        : in  std_logic_vector(31 downto 0);
        rom_addr_b_o        : out std_logic_vector(31 downto 0);
        rom_data_b_i        : in  std_logic_vector(31 downto 0);
        rom_vld_a_o         : out std_logic;
        rom_rdy_a_i         : in  std_logic;
        rom_vld_b_o         : out std_logic;
        rom_rdy_b_i         : in  std_logic;

        -- RAM
        ram_addr_a_o        : out std_logic_vector(31 downto 0);
        ram_data_a_i        : in  std_logic_vector(31 downto 0);
        ram_addr_b_o        : out std_logic_vector(31 downto 0);
        ram_data_b_i        : in  std_logic_vector(31 downto 0);
        ram_data_b_o        : out std_logic_vector(31 downto 0);
        ram_we_b_o          : out std_logic_vector( 3 downto 0);
        ram_vld_a_o         : out std_logic;
        ram_rdy_a_i         : in  std_logic;
        ram_vld_b_o         : out std_logic;
        ram_rdy_b_i         : in  std_logic;

        -- UART
        uart_addr_o         : out std_logic_vector(3 downto 0);
        uart_data_i         : in  std_logic_vector(31 downto 0);
        uart_data_o         : out std_logic_vector(31 downto 0);
        uart_we_o           : out std_logic;
        uart_vld_o          : out std_logic;
        uart_rdy_i          : in  std_logic;

        -- GPIO
        gpio_addr_o         : out std_logic_vector(3 downto 0);
        gpio_data_i         : in  std_logic_vector(31 downto 0);
        gpio_data_o         : out std_logic_vector(31 downto 0);
        gpio_we_o           : out std_logic;
        gpio_vld_o          : out std_logic;
        gpio_rdy_i          : in  std_logic;

        -- VGA
        vga_addr_o          : out std_logic_vector(16 downto 0);
        vga_data_i          : in  std_logic_vector(31 downto 0);
        vga_data_o          : out std_logic_vector(31 downto 0);
        vga_we_o            : out std_logic;
        vga_vld_o           : out std_logic;
        vga_rdy_i           : in  std_logic;

        -- NPU
        npu_addr_o          : out std_logic_vector(31 downto 0);
        npu_data_i          : in  std_logic_vector(31 downto 0);
        npu_data_o          : out std_logic_vector(31 downto 0);
        npu_we_o            : out std_logic;
        npu_vld_o           : out std_logic;
        npu_rdy_i           : in  std_logic;

        -- DMA Config (Slave Interface)
        dma_addr_o          : out std_logic_vector(3 downto 0);
        dma_data_i          : in  std_logic_vector(31 downto 0);
        dma_data_o          : out std_logic_vector(31 downto 0);
        dma_we_o            : out std_logic;
        dma_vld_o           : out std_logic;
        dma_rdy_i           : in  std_logic;

        -- CLINT
        clint_addr_o        : out std_logic_vector(4 downto 0);
        clint_data_i        : in  std_logic_vector(31 downto 0);
        clint_data_o        : out std_logic_vector(31 downto 0);
        clint_we_o          : out std_logic;
        clint_vld_o         : out std_logic;
        clint_rdy_i         : in  std_logic;

        -- PLIC
        plic_addr_o         : out std_logic_vector(23 downto 0);
        plic_data_i         : in  std_logic_vector(31 downto 0);
        plic_data_o         : out std_logic_vector(31 downto 0);
        plic_we_o           : out std_logic;
        plic_vld_o          : out std_logic;
        plic_rdy_i          : in  std_logic
    );
end entity;

architecture rtl of bus_interconnect is

    -- ========================================================================================
    -- DEFINIÇÕES DE TIPOS E ABSTRAÇÕES
    -- ========================================================================================
    type slave_t is (SLV_NONE, SLV_ROM, SLV_RAM, SLV_UART, SLV_GPIO, SLV_VGA, SLV_NPU, SLV_DMA, SLV_CLINT, SLV_PLIC);
    type master_id_t is (MST_NONE, MST_CPU, MST_DMA_RD, MST_DMA_WR);

    -- Subtipos válidos para usar como índices de Array
    subtype valid_slave_t is slave_t range SLV_ROM to SLV_PLIC;
    subtype valid_master_t is master_id_t range MST_CPU to MST_DMA_WR;

    -- Records para encapsular os sinais do barramento
    type bus_req_t is record
        addr : std_logic_vector(31 downto 0);
        data : std_logic_vector(31 downto 0);
        we   : std_logic_vector(3 downto 0);
        vld  : std_logic;
    end record;

    type bus_rsp_t is record
        data : std_logic_vector(31 downto 0);
        rdy  : std_logic;
    end record;

    -- Arrays de Barramento indexados pelos Enums
    type master_req_arr_t is array (valid_master_t) of bus_req_t;
    type master_rsp_arr_t is array (valid_master_t) of bus_rsp_t;
    
    type slave_req_arr_t  is array (valid_slave_t) of bus_req_t;
    type slave_rsp_arr_t  is array (valid_slave_t) of bus_rsp_t;

    type owner_arr_t is array (valid_slave_t) of master_id_t;

    -- ========================================================================================
    -- SINAIS INTERNOS
    -- ========================================================================================
    signal m_req : master_req_arr_t;
    signal m_rsp : master_rsp_arr_t;
    signal s_req : slave_req_arr_t;
    signal s_rsp : slave_rsp_arr_t;

    -- Registros de Arbitragem (Locks)
    signal owner_reg, owner_comb : owner_arr_t;

    -- Decodificador do IMEM
    signal imem_slv : slave_t;

    -- Função de decodificação de memória
    function decodifica(addr : std_logic_vector(31 downto 0)) return slave_t is
        variable nibble : std_logic_vector(3 downto 0);
    begin
        nibble := addr(31 downto 28);
        case nibble is
            when x"0" => return SLV_ROM;
            when x"1" => return SLV_UART;
            when x"2" => return SLV_GPIO;
            when x"3" => return SLV_VGA;
            when x"4" => return SLV_DMA;
            when x"5" => return SLV_CLINT;
            when x"6" => return SLV_PLIC;
            when x"8" => return SLV_RAM;
            when x"9" => return SLV_NPU;
            when others => return SLV_NONE;
        end case;
    end function;

begin

    -- ========================================================================================
    -- 1. IMEM (FETCH) - Caminho Exclusivo e Isolado
    -- ========================================================================================
    imem_slv     <= decodifica(imem_addr_i) when imem_vld_i = '1' else SLV_NONE;
    
    rom_addr_a_o <= imem_addr_i;
    ram_addr_a_o <= imem_addr_i;
    rom_vld_a_o  <= imem_vld_i when imem_slv = SLV_ROM else '0';
    ram_vld_a_o  <= imem_vld_i when imem_slv = SLV_RAM else '0';
    
    imem_data_o  <= rom_data_a_i when imem_slv = SLV_ROM else
                    ram_data_a_i when imem_slv = SLV_RAM else (others => '0');
                    
    imem_rdy_o   <= rom_rdy_a_i  when imem_slv = SLV_ROM else
                    ram_rdy_a_i  when imem_slv = SLV_RAM else '0';

    -- ========================================================================================
    -- 2. MAPEAMENTO: ENTRADAS FÍSICAS -> ARRAYS DE MESTRES
    -- ========================================================================================
    -- Master 0: CPU
    m_req(MST_CPU).addr <= cpu_addr_i;
    m_req(MST_CPU).data <= cpu_data_i;
    m_req(MST_CPU).we   <= cpu_we_i;
    m_req(MST_CPU).vld  <= cpu_vld_i;
    cpu_data_o          <= m_rsp(MST_CPU).data;
    cpu_rdy_o           <= m_rsp(MST_CPU).rdy;

    -- Master 1: DMA Read
    m_req(MST_DMA_RD).addr <= dma_rd_addr_i;
    m_req(MST_DMA_RD).data <= (others => '0');
    m_req(MST_DMA_RD).we   <= "0000";
    m_req(MST_DMA_RD).vld  <= dma_rd_vld_i;
    dma_rd_data_o          <= m_rsp(MST_DMA_RD).data;
    dma_rd_rdy_o           <= m_rsp(MST_DMA_RD).rdy;

    -- Master 2: DMA Write
    m_req(MST_DMA_WR).addr <= dma_wr_addr_i;
    m_req(MST_DMA_WR).data <= dma_wr_data_i;
    m_req(MST_DMA_WR).we   <= (others => dma_wr_we_i); -- Replicado para os 4 bytes
    m_req(MST_DMA_WR).vld  <= dma_wr_vld_i;
    dma_wr_rdy_o           <= m_rsp(MST_DMA_WR).rdy;

    -- ========================================================================================
    -- 3. MAPEAMENTO: SAÍDAS FÍSICAS <- ARRAYS DE ESCRAVOS
    -- ========================================================================================
    -- Respostas dos Escravos (Para o Crossbar)
    s_rsp(SLV_ROM).data   <= rom_data_b_i; s_rsp(SLV_ROM).rdy   <= rom_rdy_b_i;
    s_rsp(SLV_RAM).data   <= ram_data_b_i; s_rsp(SLV_RAM).rdy   <= ram_rdy_b_i;
    s_rsp(SLV_UART).data  <= uart_data_i;  s_rsp(SLV_UART).rdy  <= uart_rdy_i;
    s_rsp(SLV_GPIO).data  <= gpio_data_i;  s_rsp(SLV_GPIO).rdy  <= gpio_rdy_i;
    s_rsp(SLV_VGA).data   <= vga_data_i;   s_rsp(SLV_VGA).rdy   <= vga_rdy_i;
    s_rsp(SLV_NPU).data   <= npu_data_i;   s_rsp(SLV_NPU).rdy   <= npu_rdy_i;
    s_rsp(SLV_DMA).data   <= dma_data_i;   s_rsp(SLV_DMA).rdy   <= dma_rdy_i;
    s_rsp(SLV_CLINT).data <= clint_data_i; s_rsp(SLV_CLINT).rdy <= clint_rdy_i;
    s_rsp(SLV_PLIC).data  <= plic_data_i;  s_rsp(SLV_PLIC).rdy  <= plic_rdy_i;

    -- Pedidos para os Escravos (Do Crossbar, fatiando os endereços corretamente)
    rom_addr_b_o  <= s_req(SLV_ROM).addr;
    rom_vld_b_o   <= s_req(SLV_ROM).vld;

    ram_addr_b_o  <= s_req(SLV_RAM).addr;
    ram_data_b_o  <= s_req(SLV_RAM).data;
    ram_we_b_o    <= s_req(SLV_RAM).we;
    ram_vld_b_o   <= s_req(SLV_RAM).vld;

    uart_addr_o   <= s_req(SLV_UART).addr(3 downto 0);
    uart_data_o   <= s_req(SLV_UART).data;
    uart_we_o     <= '1' when s_req(SLV_UART).we /= "0000" else '0';
    uart_vld_o    <= s_req(SLV_UART).vld;

    gpio_addr_o   <= s_req(SLV_GPIO).addr(3 downto 0);
    gpio_data_o   <= s_req(SLV_GPIO).data;
    gpio_we_o     <= '1' when s_req(SLV_GPIO).we /= "0000" else '0';
    gpio_vld_o    <= s_req(SLV_GPIO).vld;

    vga_addr_o    <= s_req(SLV_VGA).addr(16 downto 0);
    vga_data_o    <= s_req(SLV_VGA).data;
    vga_we_o      <= '1' when s_req(SLV_VGA).we /= "0000" else '0';
    vga_vld_o     <= s_req(SLV_VGA).vld;

    npu_addr_o    <= s_req(SLV_NPU).addr;
    npu_data_o    <= s_req(SLV_NPU).data;
    npu_we_o      <= '1' when s_req(SLV_NPU).we /= "0000" else '0';
    npu_vld_o     <= s_req(SLV_NPU).vld;

    dma_addr_o    <= s_req(SLV_DMA).addr(3 downto 0);
    dma_data_o    <= s_req(SLV_DMA).data;
    dma_we_o      <= '1' when s_req(SLV_DMA).we /= "0000" else '0';
    dma_vld_o     <= s_req(SLV_DMA).vld;

    clint_addr_o  <= s_req(SLV_CLINT).addr(4 downto 0);
    clint_data_o  <= s_req(SLV_CLINT).data;
    clint_we_o    <= '1' when s_req(SLV_CLINT).we /= "0000" else '0';
    clint_vld_o   <= s_req(SLV_CLINT).vld;

    plic_addr_o   <= s_req(SLV_PLIC).addr(23 downto 0);
    plic_data_o   <= s_req(SLV_PLIC).data;
    plic_we_o     <= '1' when s_req(SLV_PLIC).we /= "0000" else '0';
    plic_vld_o    <= s_req(SLV_PLIC).vld;


    -- ========================================================================================
    -- 4. O CORAÇÃO DO CROSSBAR: ROTEAMENTO E ARBITRAGEM COMBINACIONAL (VHDL-2008 'all')
    -- ========================================================================================
    process(all) 
        variable target  : slave_t;
        variable v_owner : owner_arr_t; -- VARIÁVEL: Atualiza imediatamente no laço!
    begin
        -- Estado padrão: Desconecta todos os escravos e carrega o lock atual para a variável
        for s in valid_slave_t loop
            s_req(s).addr <= (others => '0');
            s_req(s).data <= (others => '0');
            s_req(s).we   <= (others => '0');
            s_req(s).vld  <= '0';
            
            v_owner(s)    := owner_reg(s); -- Inicializa a variável com o estado sequencial
        end loop;

        -- Estado padrão: Mestres recebem rdy='1' e data=0 (Evita deadlock em bus fault)
        for m in valid_master_t loop
            m_rsp(m).data <= (others => '0');
            if m_req(m).vld = '1' then
                m_rsp(m).rdy <= '0'; -- Aguarda ser atendido
            else
                m_rsp(m).rdy <= '1'; -- Mestre ocioso
            end if;
        end loop;

        -- Resolução de Acessos (Prioridade fixa: CPU -> DMA_RD -> DMA_WR)
        for m in valid_master_t loop
            if m_req(m).vld = '1' then
                target := decodifica(m_req(m).addr);

                if target /= SLV_NONE then
                    -- AVALIA A VARIÁVEL: Se a CPU pegou, o DMA já vai enxergar ocupado!
                    if v_owner(target) = MST_NONE or v_owner(target) = m then
                        
                        v_owner(target) := m;                -- Atualiza a variável NA HORA
                        s_req(target)   <= m_req(m);         -- Conecta os sinais de ida
                        m_rsp(m)        <= s_rsp(target);    -- Conecta os sinais de volta
                        
                    end if;
                else
                    -- Bus Fault: Acesso a endereço não mapeado
                    m_rsp(m).rdy <= '1';
                end if;
            end if;
        end loop;

        -- Por fim, descarrega o resultado final da variável para o sinal que alimenta os registradores
        for s in valid_slave_t loop
            owner_comb(s) <= v_owner(s);
        end loop;
        
    end process;

    -- ========================================================================================
    -- 5. TRAVA SEQUENCIAL (STICKY LOCK)
    -- ========================================================================================
    process(clk_i, rst_i)
    begin
        if rst_i = '1' then
            owner_reg <= (others => MST_NONE);
        elsif rising_edge(clk_i) then
            for s in valid_slave_t loop
                if owner_comb(s) /= MST_NONE then
                    -- Se o periférico ainda não terminou a transação (wait state), retém a trava
                    if s_rsp(s).rdy = '0' then
                        owner_reg(s) <= owner_comb(s);
                    else
                        owner_reg(s) <= MST_NONE;
                    end if;
                else
                    owner_reg(s) <= MST_NONE;
                end if;
            end loop;
        end if;
    end process;

end architecture; -- rtl

-- ========================================================================================