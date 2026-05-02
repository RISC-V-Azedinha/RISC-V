------------------------------------------------------------------------------------------------------------------
-- 
-- File: riscv_uarch_pkg.vhd
--
-- ██╗   ██╗ █████╗ ██████╗  ██████╗██╗  ██╗
-- ██║   ██║██╔══██╗██╔══██╗██╔════╝██║  ██║
-- ██║   ██║███████║██████╔╝██║     ███████║
-- ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
-- ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
--  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝                                                                                                                                                      
-- 
-- Descrição : Pacote que carrega as especificações para a micro-arquitetura específica (multi_cycle).
--
-- Autor     : [André Maiolini]
-- Data      : [25/12/2025]
--
-------------------------------------------------------------------------------------------------------------------

library ieee;                     -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;      -- Tipos lógicos (std_logic, std_logic_vector)
use ieee.numeric_std.all;         -- Biblioteca para operações aritméticas com vetores lógicos (signed, unsigned)

-------------------------------------------------------------------------------------------------------------------
-- PACOTE: Definição do pacote para especificações micro-arquiteturais
-------------------------------------------------------------------------------------------------------------------

package riscv_uarch_pkg is

    -- === TIPO DE REGISTRO PARA OS SINAIS DE CONTROLE (CONTROL) ==================================================
    -- Agrupa todas as saídas da unidade de controle (control.vhd) que vão para o datapath.
    -- Atualizado para suportar a arquitetura MULTI-CYCLE.

    type t_control is record
        
        ----------------------------------------------------------------------
        -- 1. Sinais de Habilitação de Escrita (Write Enables)
        ----------------------------------------------------------------------
        pc_write    : std_logic; -- Atualiza o PC (Jumps, Fetch ou Branch confirmado)
        opc_write   : std_logic; -- Atualiza o registrador OldPC (Salva PC atual)
        ir_write    : std_logic; -- Atualiza o Instruction Register (IR)
        mem_write   : std_logic; -- Habilita escrita na memória (SW)
        reg_write   : std_logic; -- Habilita escrita no Banco de Registradores (WB)
        
        -- Registradores Intermediários (Pipeline Registers)
        rs1_write   : std_logic; -- Captura rs1 do banco para o reg interno 'A'
        rs2_write   : std_logic; -- Captura rs2 do banco para o reg interno 'B'
        alur_write  : std_logic; -- Captura resultado da ALU no reg 'ALUOut'
        mdr_write   : std_logic; -- Captura dado da memória no 'MDR'

        ----------------------------------------------------------------------
        -- 2. Sinais de Seleção de Multiplexadores (Selects)
        ----------------------------------------------------------------------
        alu_src_a   : std_logic_vector(1 downto 0); -- 00:rs1, 01:OldPC, 10:Zero
        alu_src_b   : std_logic;                    -- 0:rs2, 1:Imediato
        wb_sel      : std_logic_vector(1 downto 0); -- 00:ALUOut, 01:MDR, 10:PC+4, 11:CSR
        pc_src      : std_logic_vector(1 downto 0); -- 00:PC+4, 01:Jump/Branch, 10:JALR

        ----------------------------------------------------------------------
        -- 3. Sinais Funcionais
        ----------------------------------------------------------------------
        alu_control : std_logic_vector(3 downto 0); -- Operação da ALU (ADD, SUB, XOR...)

        ----------------------------------------------------------------------
        -- 4. Controle de CSRs e Traps
        ----------------------------------------------------------------------

        csr_write   : std_logic;                     -- Escreve no banco de CSRs
        trap_enter  : std_logic;                     -- 1 = Entra em Trap (Salva PC, Pula p/ MTVEC)
        trap_return : std_logic;                     -- 1 = Retorna de Trap (Pula p/ MEPC)
        trap_cause  : std_logic_vector(31 downto 0); -- Código da causa (ex: 11 p/ ECALL)
        
    end record;

    -- === CONSTANTE NOP (RESET) ==================================================================================
    -- Inicializa todos os sinais com zero/segurança

    constant c_CONTROL_NOP : t_control := (
        pc_write    => '0',
        opc_write   => '0',
        ir_write    => '0',
        mem_write   => '0',
        reg_write   => '0',
        rs1_write   => '0',
        rs2_write   => '0',
        alur_write  => '0',
        mdr_write   => '0',
        alu_src_a   => "00",
        alu_src_b   => '0',
        wb_sel      => "00",
        pc_src      => "00",
        alu_control => "0000",
        csr_write   => '0',
        trap_enter  => '0',
        trap_return => '0',
        trap_cause  => (others => '0')
    );

end package riscv_uarch_pkg;

-------------------------------------------------------------------------------------------------------------------