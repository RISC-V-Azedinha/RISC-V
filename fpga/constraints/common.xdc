## =========================================================================================================================
## Constraints comuns a todas as placas (independentes de pinagem)
## =========================================================================================================================
##
## A pinagem de cada placa fica em <placa>.xdc (ex: nexys4.xdc, nexys_a7.xdc). Este arquivo é lido
## junto com ela pelo build.tcl.

## =========================================================================================================================
## Clock Signal (100 MHz)
## =========================================================================================================================

create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK_i }];

## =========================================================================================================================
## Configurações de Tensão Elétrica - Voltage (CFGBVS)
## =========================================================================================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## =========================================================================================================================
## Configurações para a Flash (Quad-SPI)
## =========================================================================================================================

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

## =========================================================================================================================
## Exceções de Timing (Multicycle Paths)
## =========================================================================================================================

## IR -> flag Zero da ALU (resolução de branch, S_EX_BR)
##
## O core multi_cycle mantém r_IR estável durante toda a execução de uma instrução (vários
## ciclos de clock), e no estado S_EX_BR a FSM só usa r_alu_zero no SEGUNDO microestado, quando
## esse registrador já teve um ciclo inteiro para se estabilizar (ver comentário em
## rtl/core/multi_cycle/core/main_fsm.vhd, sinal s_br_wait_q). O caminho combinacional
## IR -> gerador de imediato -> ALU -> flag Zero tem portanto 2 ciclos de clock disponíveis,
## não 1 (o padrão assumido pelo STA), daí o multicycle path abaixo.
set_multicycle_path -setup 2 -from [get_cells U_CORE/U_DATAPATH/r_IR_reg[*]] -to [get_cells U_CORE/U_CONTROLPATH/r_alu_zero_reg]
set_multicycle_path -hold  1 -from [get_cells U_CORE/U_DATAPATH/r_IR_reg[*]] -to [get_cells U_CORE/U_CONTROLPATH/r_alu_zero_reg]
