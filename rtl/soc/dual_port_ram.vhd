------------------------------------------------------------------------------------------------------------------
-- 
-- File: dual_port_ram.vhd
--
-- ██████╗  █████╗ ███╗   ███╗
-- ██╔══██╗██╔══██╗████╗ ████║
-- ██████╔╝███████║██╔████╔██║
-- ██╔══██╗██╔══██║██║╚██╔╝██║
-- ██║  ██║██║  ██║██║ ╚═╝ ██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝
--  
-- Descrição : Módulo de RAM dual-port para leitura e escrita simultâneas
--    em duas portas independentes - usando BRAM inferida.
--    [ATUALIZADO: Edge Guard (r_rdy_a / r_rdy_b) para barramento atômico]
-- 
-- Autor     : [André Maiolini]
-- Data      : [30/12/2025]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

entity dual_port_ram is
    generic (
        ADDR_WIDTH : integer := 12; 
        DATA_WIDTH : integer := 32
    );
    port (
        clk        : in  std_logic;
        
        -- Porta A
        vld_a_i    : in  std_logic; 
        we_a       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        addr_a     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_a_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_a_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rdy_a_o    : out std_logic;
        
        -- Porta B
        vld_b_i    : in  std_logic;
        we_b       : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        addr_b     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        data_b_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_b_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rdy_b_o    : out std_logic

    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

architecture rtl of dual_port_ram is

    -- Tipo de dado para a RAM
    type t_ram is array (0 to (2**ADDR_WIDTH)-1)
        of std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Usar shared variable permite que múltiplos processos acessem a memória sem conflito.
    shared variable ram : t_ram := (others => (others => '0'));

    -- Atributo para forçar inferência de Block RAM 
    attribute ram_style : string;
    attribute ram_style of ram : variable is "block";

    -- Desabilita a otimização de cascata profunda que causa o erro de pino ADDR15.
    attribute cascade_height : integer;
    attribute cascade_height of ram : variable is 0;

    -- ====================================================================
    -- SINAIS DE GUARDA PARA O HANDSHAKE
    -- ====================================================================
    signal r_rdy_a : std_logic := '0';
    signal r_rdy_b : std_logic := '0';

    -- ====================================================================
    -- PORTA B: LEITURA SEQUENCIAL (PRÉ-BUSCA) E ESCRITA EM 1 CICLO
    -- ====================================================================
    -- Ao responder uma leitura no endereço A, a porta já lê A+1. Se o pedido seguinte for
    -- exatamente A+1 (leitura), a resposta sai no mesmo ciclo (rdy combinacional), e assim por
    -- diante: uma palavra por ciclo em leituras sequenciais (DMA). Qualquer outro pedido,
    -- inclusive uma escrita, descarta a pré-busca e espera um ciclo, então o dado nunca fica
    -- velho (a porta A é só de leitura). Escritas são confirmadas no próprio ciclo (rdy
    -- combinacional). O endereço das BRAMs só depende de registradores para escolher entre a
    -- pré-busca e o pedido (o seletor tem fanout para todas as BRAMs da memória).
    signal r_pf_valid : std_logic := '0';
    signal r_pf_addr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal s_pf_hit   : std_logic;
    signal s_wr_b     : std_logic;
    signal s_pf_sel   : std_logic;                       -- Este ciclo lê o endereço pré-buscado + 1 (registrado)
    signal s_wr_ok    : std_logic;                       -- Escrita aceita neste ciclo
    signal s_addr_b   : unsigned(ADDR_WIDTH-1 downto 0); -- Endereço único da porta (inferência de BRAM)

begin

    -- Roteamento contínuo
    rdy_a_o <= r_rdy_a;
    s_wr_b   <= '1' when we_b /= (we_b'range => '0') else '0';
    s_pf_hit <= '1' when vld_b_i = '1' and s_wr_b = '0' and r_pf_valid = '1' and unsigned(addr_b) = r_pf_addr else '0';

    -- Um único endereço por ciclo na porta B: com pré-busca ativa (ou no ciclo da resposta de
    -- uma leitura nova), o seguinte ao pré-buscado; senão, o do pedido
    s_pf_sel <= r_pf_valid or r_rdy_b;
    s_addr_b <= r_pf_addr + 1 when s_pf_sel = '1' else unsigned(addr_b);
    s_wr_ok  <= vld_b_i and s_wr_b and not s_pf_sel;

    rdy_b_o <= r_rdy_b or s_pf_hit or s_wr_ok;

    -- ============================================================================================================
    -- PORTA A
    -- ============================================================================================================
    process(clk)
    begin

        if rising_edge(clk) then

            -- Default: Remove o ACK para garantir que dure apenas 1 ciclo
            r_rdy_a <= '0';

            -- Edge Guard: Executa o acesso APENAS se tem pedido e ainda não respondemos
            if vld_a_i = '1' and r_rdy_a = '0' then
                
                r_rdy_a <= '1';
                
                -- Leitura (Read-First)
                data_a_o <= ram(to_integer(unsigned(addr_a)));
                
                -- Escrita controlada por byte enable
                for i in 0 to (DATA_WIDTH/8)-1 loop
                    if we_a(i) = '1' then
                        ram(to_integer(unsigned(addr_a)))(8*i+7 downto 8*i) := data_a_i(8*i+7 downto 8*i);
                    end if;
                end loop;
                
            end if;

        end if;
        
    end process;

    -- ============================================================================================================
    -- PORTA B
    -- ============================================================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            -- Default: Remove o ACK para garantir que dure apenas 1 ciclo
            r_rdy_b <= '0';

            -- Memória: uma leitura (read-first) e, se for o caso, uma escrita, no mesmo endereço
            data_b_o <= ram(to_integer(s_addr_b));
            -- Write enable por byte: só vld, o próprio we(i) e o seletor registrado (sem passar pelo
            -- OU dos bytes, que fica só no rdy)
            if vld_b_i = '1' and s_pf_sel = '0' then
                for i in 0 to (DATA_WIDTH/8)-1 loop
                    if we_b(i) = '1' then
                        ram(to_integer(s_addr_b))(8*i+7 downto 8*i) := data_b_i(8*i+7 downto 8*i);
                    end if;
                end loop;
            end if;

            -- Controle do handshake e da pré-busca
            if s_pf_hit = '1' then
                -- Leitura sequencial: respondida neste ciclo com o dado pré-buscado; busca o próximo
                r_pf_addr <= r_pf_addr + 1;

            elsif r_rdy_b = '1' then
                -- Ciclo da resposta: o mestre ainda mostra o pedido atendido; pré-busca o seguinte
                r_pf_addr  <= r_pf_addr + 1;
                r_pf_valid <= '1';

            elsif s_wr_ok = '1' then
                -- Escrita: confirmada neste ciclo (rdy combinacional)
                null;

            elsif vld_b_i = '1' and r_pf_valid = '1' then
                -- Pedido fora da sequência: descarta a pré-busca e atende no ciclo seguinte
                r_pf_valid <= '0';

            elsif vld_b_i = '1' then
                -- Leitura nova (Edge Guard): responde no ciclo seguinte
                r_rdy_b    <= '1';
                r_pf_valid <= '0';
                r_pf_addr  <= unsigned(addr_b);

            else
                r_pf_valid <= '0';
            end if;
        end if;
    end process;

end architecture;

-------------------------------------------------------------------------------------------------------------------