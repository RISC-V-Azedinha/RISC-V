------------------------------------------------------------------------------------------------------------------
-- 
-- File: vga_sync.vhd
-- 
-- ██╗   ██╗ ██████╗  █████╗     ███████╗██╗   ██╗███╗   ██╗ ██████╗
-- ██║   ██║██╔════╝ ██╔══██╗    ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝
-- ██║   ██║██║  ███╗███████║    ███████╗ ╚████╔╝ ██╔██╗ ██║██║     
-- ╚██╗ ██╔╝██║   ██║██╔══██║    ╚════██║  ╚██╔╝  ██║╚██╗██║██║     
--  ╚████╔╝ ╚██████╔╝██║  ██║    ███████║   ██║   ██║ ╚████║╚██████╗
--   ╚═══╝   ╚═════╝ ╚═╝  ╚═╝    ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝
-- 
-- Descrição : Componente Gerador de Sinais de Sincronismo VGA (VGA Sync Generator).
-- 
-- Autor     : [André Maiolini]
-- Data      : [02/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Gerador de Sinais de Sincronismo VGA (VGA Sync Generator)
-------------------------------------------------------------------------------------------------------------------

entity vga_sync is
    port (
        clk      : in  std_logic;                -- Clock de entrada (100MHz)
        rst      : in  std_logic;                -- Sinal de reset
        h_count  : out integer range 0 to 799;   -- Contador horizontal
        v_count  : out integer range 0 to 524;   -- Contador vertical
        h_sync   : out std_logic;                -- Sinal de sincronismo horizontal
        v_sync   : out std_logic;                -- Sinal de sincronismo vertical
        video_on : out std_logic                 -- Sinal indicando área ativa de vídeo
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Definição do comportamento do Gerador de Sinais de Sincronismo VGA (VGA Sync Generator)
-------------------------------------------------------------------------------------------------------------------

architecture rtl of vga_sync is

    -- Parâmetros VGA 640x480 @ 60Hz (Clock 25MHz necessário)
    -- -- O clock de entrada é 100MHz, então é utilizado um divisor de clock (pixel enable).
    -- -- A cada pulso de clock, o contador avança somente se pixel_en estiver ativo,
    -- -- sendo pixel_en ativo a cada 4 ciclos de clock (25MHz efetivos).
        
        signal pixel_en : std_logic;
        signal count_div : integer range 0 to 3 := 0;

    -- Contadores internos 

    -- OBS.: a quantidade de píxeis visíveis é de 640x480, mas os contadores precisam contar 
    -- até 800x525 para incluir os intervalos de sincronismo. Na horizontal, tem 160 píxeis extras, já
    -- na vertical, 45 linhas extras.

        signal h_cnt_reg : integer range 0 to 799 := 0;
        signal v_cnt_reg : integer range 0 to 524 := 0;

    -- Dessa forma, 800x525 é o total de ciclos para completar um frame - que devem ser renderizados
    -- a uma taxa de 60Hz. Isso totaliza em uma taxa de varredura de 25 MHz.

begin

    ---------------------------------------------------------------------------------------------------------
    -- Divisor de Frequência (100MHz -> 25MHz)
    ---------------------------------------------------------------------------------------------------------

        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    count_div <= 0;
                    pixel_en <= '0';
                else
                    if count_div = 3 then
                        count_div <= 0;
                        pixel_en <= '1'; -- Pulso a cada 4 ciclos (25MHz efetivos)
                    else
                        count_div <= count_div + 1;
                        pixel_en <= '0';
                    end if;
                end if;
            end if;
        end process;

    ---------------------------------------------------------------------------------------------------------
    -- Contadores Horizontal e Vertical 
    ---------------------------------------------------------------------------------------------------------

    -- Esses contadores avançam somente quando pixel_en está ativo. Esses contadores são responsáveis
    -- por determinar a posição exata sendo renderizada na tela. Ou seja, a coordenada (pixel_x, pixel_y).

        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    h_cnt_reg <= 0;
                    v_cnt_reg <= 0;
                elsif pixel_en = '1' then
                    if h_cnt_reg = 799 then
                        h_cnt_reg <= 0;
                        if v_cnt_reg = 524 then
                            v_cnt_reg <= 0;
                        else
                            v_cnt_reg <= v_cnt_reg + 1;
                        end if;
                    else
                        h_cnt_reg <= h_cnt_reg + 1;
                    end if;
                end if;
            end if;
        end process;

    -- Saídas

        h_count <= h_cnt_reg;
        v_count <= v_cnt_reg;
    
    -- Sincronismo (Polaridade Negativa)
    -- Os sinais são determinados como ativos em nível lógico baixo durante os intervalos de sincronismo.
    
        h_sync <= '0' when (h_cnt_reg >= 656 and h_cnt_reg < 752) else '1';
        v_sync <= '0' when (v_cnt_reg >= 490 and v_cnt_reg < 492) else '1';
    
    -- Área Ativa de Vídeo (640x480)
        
        video_on <= '1' when (h_cnt_reg < 640 and v_cnt_reg < 480) else '0';

    -- NOTA: o sinal de área ativa (video_on) indica quando os contadores estão dentro da área visível
    -- de 640x480. Isso evita que sejam exibidos dados dentro dos intervalos de sincronismo.

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------