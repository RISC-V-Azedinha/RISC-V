------------------------------------------------------------------------------------------------------------------
-- 
-- File: vga_peripheral.vhd
-- 
-- ██╗   ██╗ ██████╗  █████╗ 
-- ██║   ██║██╔════╝ ██╔══██╗
-- ██║   ██║██║  ███╗███████║
-- ╚██╗ ██╔╝██║   ██║██╔══██║
--  ╚████╔╝ ╚██████╔╝██║  ██║
--   ╚═══╝   ╚═════╝ ╚═╝  ╚═╝
-- 
-- Descrição : Controlador do Periférico VGA para o SoC RISC-V.
-- 
-- Autor     : [André Maiolini]
-- Data      : [02/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do Controlador do Periférico VGA
-------------------------------------------------------------------------------------------------------------------

entity vga_peripheral is
    port (

        -- === Sinais de Controle === -----------------------------------------------------------------------------

        clk         : in  std_logic;                       -- Clock de entrada (100MHz)
        rst         : in  std_logic;                       -- Sinal de reset
        
        -- === Interface com o Processador (CPU) === --------------------------------------------------------------
        
        we_i    : in  std_logic;                       -- Sinal de escrita 
        addr_i  : in  std_logic_vector(16 downto 0);   -- Endereço de 17 bits (320x240 = 76800 endereços)
        data_i  : in  std_logic_vector(31 downto 0);   -- Dados de 32 bits para escrita
        data_o  : out std_logic_vector(31 downto 0);   -- Dados de 32 bits lidos
        vld_i   : in  std_logic;
        rdy_o   : out std_logic;
        
        -- === Interface Física (VGA Monitor) === -----------------------------------------------------------------

        vga_hs_o    : out std_logic;                       -- Sinal de sincronismo horizontal
        vga_vs_o    : out std_logic;                       -- Sinal de sincronismo vertical
        vga_r_o     : out std_logic_vector(3 downto 0);    -- Sinal de cor vermelha (4 bits)
        vga_g_o     : out std_logic_vector(3 downto 0);    -- Sinal de cor verde (4 bits)
        vga_b_o     : out std_logic_vector(3 downto 0)     -- Sinal de cor azul (4 bits)
    
    );
end entity;

-------------------------------------------------------------------------------------------------------------------
-- Arquitetura: Definição do comportamento do Controlador do Periférico VGA
-------------------------------------------------------------------------------------------------------------------

-- Abstrai a comunicação usando o conceito de MMIO (Memory-Mapped I/O).
-- O processador acessa o periférico VGA através de endereços específicos na memória.
-- A VRAM é mapeada em um espaço de 17 bits (0x00000 a 0x1FFFF).

architecture rtl of vga_peripheral is

    -- Sinais internos

    signal pixel_x    : integer range 0 to 799;            -- Contador horizontal completo
    signal pixel_y    : integer range 0 to 524;            -- Contador vertical completo
    signal video_on   : std_logic;                         -- Sinal de área ativa de vídeo
    signal s_vsync    : std_logic;                         -- Sinal interno de VSYNC
    
    signal vram_addr  : std_logic_vector(16 downto 0);     -- Endereço para a Video RAM
    signal vram_data  : std_logic_vector(7 downto 0);      -- Dados lidos da Video RAM
    signal s_vram_we  : std_logic;
    
    -- Sinal para o dado alinhado

    signal s_data_aligned : std_logic_vector(7 downto 0);  -- Dado alinhado para escrita na VRAM

    -- Sinais para coordenadas escaladas

    -- A resolução da VRAM é 320x240, então é necessário escalar as coordenadas
    -- do VGA (640x480) para acessar a VRAM corretamente.

    -- Isso econômiza espaço na VRAM, já que cada pixel usa apenas 8 bits (RRRGGGBB).
    -- As coordenadas são divididas por 2 para fazer o escalonamento.

    signal x_scaled   : integer range 0 to 400;            -- Coordenada X escalada para 320x240
    signal y_scaled   : integer range 0 to 300;            -- Coordenada Y escalada para 320x240

begin

    -- O sinal de escrita só é real se o mestre disser que a transação é VÁLIDA
    s_vram_we <= we_i and vld_i;

    -- LÓGICA DE ALINHAMENTO (MUX) --------------------------------------------------------------------------------

    -- Escolhe o byte certo baseado nos 2 últimos bits do endereço 
        
        process(addr_i, data_i)
        begin
            case addr_i(1 downto 0) is
                when "00"   => s_data_aligned <= data_i(7 downto 0);
                when "01"   => s_data_aligned <= data_i(15 downto 8);
                when "10"   => s_data_aligned <= data_i(23 downto 16);
                when "11"   => s_data_aligned <= data_i(31 downto 24);
                when others => s_data_aligned <= (others => '0');
            end case;
        end process;

    -- Instância da Memória (usa o dado alinhado) -----------------------------------------------------------------

        U_VRAM: entity work.video_ram
            port map (
                clk     => clk,
                we_a    => s_vram_we,
                addr_a  => addr_i,
                data_a  => s_data_aligned,
                addr_b  => vram_addr,
                data_b  => vram_data
            );

    -- Instância do Sync Generator --------------------------------------------------------------------------------

        U_SYNC: entity work.vga_sync
            port map (
                clk      => clk,
                rst      => rst,
                h_count  => pixel_x,
                v_count  => pixel_y,
                h_sync   => vga_hs_o,
                v_sync   => s_vsync,
                video_on => video_on
            );

    -- Sinal interno na saída -------------------------------------------------------------------------------------
        
        vga_vs_o <= s_vsync;

    -- Lógica de Endereço de Leitura e Saída de Cor ---------------------------------------------------------------
        
    -- -- Cálculo do processo de upscaling das coordenadas (divisão por 2),
    -- -- para mapear as coordenadas de 640x480 para 320x240.

    -- -- Como a resolução 640x480 tem o dobro de pixels em ambas as direções,
    -- -- cada coordenada é dividida por 2 para que cada pixel da memória seja "esticado"
    -- -- para ocupar 2 pixels na tela.

        x_scaled <= pixel_x / 2;
        y_scaled <= pixel_y / 2;
        vram_addr <= std_logic_vector(to_unsigned(y_scaled * 320 + x_scaled, 17));

    -- Lógica de Saída de Cor para o Monitor VGA

        process(clk)
        begin
            if rising_edge(clk) then
                if video_on = '1' then
                    vga_r_o <= vram_data(7 downto 5) & "0";
                    vga_g_o <= vram_data(4 downto 2) & "0";
                    vga_b_o <= vram_data(1 downto 0) & "00";
                else
                    vga_r_o <= (others => '0');
                    vga_g_o <= (others => '0');
                    vga_b_o <= (others => '0');
                end if;
            end if;
        end process;

    -- Interface de Leitura e Handshake (RDY/VLD) -----------------------------------------------------------------

        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    rdy_o  <= '0';
                    data_o <= (others => '0');
                else
                    -- Default
                    rdy_o  <= '0';
                    data_o <= (others => '0');

                    if vld_i = '1' then
                        -- Handshake: Resposta no ciclo T+1
                        rdy_o <= '1';
                        
                        -- Leitura de Registradores (Ex: VSYNC)
                        if we_i = '0' then
                            if addr_i = "11111111111111111" then -- Endereço 0x1FFFF
                                data_o <= (0 => s_vsync, others => '0'); -- Retorna bit 0 = VSYNC
                            end if;
                        end if;
                        
                        -- Para escritas (WE=1), o 'rdy_o' serve apenas como ACK,
                        -- pois a escrita na BRAM já foi engatilhada pelo s_vram_we.
                    end if;
                end if;
            end if;
        end process;

    ---------------------------------------------------------------------------------------------------------------

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------------