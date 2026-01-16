-- ===============================================================================================================================================
--
-- File: processor_top.vhd (Top Level do Processador RISC-V RV32I)
-- 
--   ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗
--   ██╔══██╗██║   ██║╚════██╗╚════██╗██║
--   ██████╔╝██║   ██║ █████╔╝ █████╔╝██║
--   ██╔══██╗╚██╗ ██╔╝ ╚═══██╗██╔═══╝ ██║    ->> PROJETO: Processador RISC-V (RV32I) - Implementação em VHDL
--   ██║  ██║ ╚████╔╝ ██████╔╝███████╗██║    ->> AUTOR: André Solano F. R. Maiolini 
--   ╚═╝  ╚═╝  ╚═══╝  ╚═════╝ ╚══════╝╚═╝    ->> DATA: 15/09/2025
--
-- ============+=================================================================================================================================
--   Descrição |
-- ------------+
--
-- Este código VHDL descreve a arquitetura RISC-V de 32 bits (RV32I), organizada em duas principais seções: o datapath e o control path.
--
-- O datapath é responsável pelo processamento dos dados, incluindo a Unidade Lógica e Aritmética (ALU),
-- o banco de registradores, o acesso à memória de instruções e de dados, e os multiplexadores que direcionam o fluxo de dados.
--
-- O control path gera os sinais de controle a partir da instrução atual, determinando o comportamento do datapath,
-- como qual operação a ALU deve executar, quando escrever em registradores ou memória, e quando atualizar o PC.
--
-- =====================+=========================================================================================================================
--  Diagrama de Blocos  |
-- ---------------------+                     Arquitetura de Harvard Modificada                    ____________________________
--                                                                                                /                           /\
--                  +--------+             +-----+   addr   +-----+   addr   +-----+             /         RISC-V           _/ /\
--       Reset_i >--|        |             |     | <------- |     | -------> |     |            /       (Harvard Mod)      / \/
--         CLK_i >--|  CPU   |     ==>     | ROM |   inst   | CPU |   data   | RAM |           /                           /\
--                  |        |             |     | -------> |     | <------> |     |          /___________________________/ /
--                  +--------+             +-----+          +-----+          +-----+          \___________________________\/
--                                                  (IMEM)           (DMEM)                    \ \ \ \ \ \ \ \ \ \ \ \ \ \ \
--
--
--  A arquitetura de Harvard modificada permite que o processador acesse simultaneamente a memória de instruções (IMEM) e a memória de dados (DMEM),
--  melhorando o desempenho geral. A CPU busca instruções da IMEM enquanto lê ou escreve dados na DMEM.
--
-- ===============================================================================================================================================

-- ==| Libraries |================================================================================================================================

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)
use work.riscv_uarch_pkg.all;     -- Contém todas as definições específicas para a microarquitetura

-- ==| PROCESSOR_TOP |============================================================================================================================

entity processor_top is

  port (
    
    -- Sinais de controle

    CLK_i               : in  std_logic;                          -- Clock principal do processador
    Reset_i             : in  std_logic;                          -- Sinal de reset síncrono (ativo em nível alto)

    -- Barramento de memória de instruções (IMEM)

    IMem_addr_o         : out std_logic_vector(31 downto 0);      -- Endereço de 32 bits para a memória de instruções
    IMem_data_i         : in  std_logic_vector(31 downto 0);      -- Instrução de 32 bits vinda da memória de instruções

    -- Barramento de memória de dados (DMEM)

    DMem_addr_o         : out std_logic_vector(31 downto 0);      -- Endereço de 32 bits para a memória de dados
    DMem_data_o         : out std_logic_vector(31 downto 0);      -- Dados de 32 bits a serem escritos na memória de dados
    DMem_data_i         : in  std_logic_vector(31 downto 0);      -- Dados de 32 bits lidos da memória de dados
    DMem_we_o           : out std_logic_vector( 3 downto 0);      -- Sinal de habilitação de escrita na memória de dados (ativo em nível alto)

    -- Handshake 
    
    IMem_rdy_i          : in  std_logic;
    IMem_vld_o          : out std_logic;
    DMem_rdy_i          : in  std_logic;                          -- Barramento indica que dado está pronto/escrito
    DMem_vld_o          : out std_logic                           -- Processador indica intenção de transação

  ) ;

end processor_top ;

-- ==| ARQUITETURA |==============================================================================================================================

-- Faz conexão estrutural dos dois principais blocos do processador:
--  1) Control Path (U_CONTROLPATH)  -> circuito de comando (gera sinais de controle)
--  2) Datapath (U_DATAPATH)         -> circuito de potência (lida com os dados)

architecture rtl of processor_top is

    -- ============== DECLARAÇÃO DOS SINAIS INTERMEDIÁRIOS ============== --
    
        -- Estes sinais conectam controlpath ao datapath, 
        -- indicando o que deve ser feito a cada ciclo de clock.

        -- 1. Pacote de Controle (Substitui RegWrite, ALUSrc, MemWrite, etc.)
        
            signal s_ctrl : t_control;

        -- 2. Feedback do Datapath para o Control

            signal s_alu_zero     : std_logic := '0';
            signal s_instruction  : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- ============== CONTROL PATH ======================== 

        -- Este bloco recebe a instrução atual da memória de programa
        -- e gera todos os sinais de controle necessários para o datapath executar a instrução corretamente.

            U_CONTROLPATH: entity work.control
                port map (
                    -- Sinais de Sincronismo 
                    Clk_i              => CLK_i,          -- CLOCK global
                    Reset_i            => Reset_i,        -- Master-Reset

                    -- Interface de Handshake 
                    imem_rdy_i         => IMem_rdy_i,
                    imem_vld_o         => IMem_vld_o,
                    dmem_rdy_i         => DMem_rdy_i,
                    dmem_vld_o         => DMem_vld_o,

                    -- Interface de dados
                    Instruction_i      => s_instruction,  -- Instrução buscada na memória
                    ALU_Zero_i         => s_alu_zero,     -- Flag zero da ALU
                    Control_o          => s_ctrl          -- Todos os sinais de controle embalados
                );

    -- ============== DATAPATH =============================

        -- O datapath realiza todas as operações aritméticas, lógicas e de movimentação de dados.
        -- Ele também atualiza o PC (program counter) e acessa a memória de dados conforme os sinais de controle.

            U_DATAPATH: entity work.datapath
                port map (
                    CLK_i              => CLK_i,
                    Reset_i            => Reset_i,
                    IMem_addr_o        => IMem_addr_o,
                    IMem_data_i        => IMem_data_i,
                    DMem_addr_o        => DMem_addr_o,
                    DMem_data_o        => DMem_data_o,
                    DMem_data_i        => DMem_data_i,
                    DMem_writeEnable_o => DMem_we_o,
                    Control_i          => s_ctrl,
                    Instruction_o      => s_instruction,
                    ALU_Zero_o         => s_alu_zero
                );

end architecture rtl; -- rtl

-- ===============================================================================================================================================