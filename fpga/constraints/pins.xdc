## =========================================================================================================================
## Clock Signal (100 MHz)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK_i }]; 
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK_i }];

## =========================================================================================================================
## Configurações de Tensão Elétrica - Voltage (CFGBVS)
## =========================================================================================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## =========================================================================================================================
##  Pinos para NEXYS 4 
## =========================================================================================================================

## Reset (Botão Central - BTNC) --------------------------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { Reset_i }];

## Switches (SW0 - SW15) ---------------------------------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN U9    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[0] }];
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[1] }];
set_property -dict { PACKAGE_PIN R7    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[2] }];
set_property -dict { PACKAGE_PIN R6    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[3] }];
set_property -dict { PACKAGE_PIN R5    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[4] }];
set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[5] }];
set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[6] }];
set_property -dict { PACKAGE_PIN V5    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[7] }];
set_property -dict { PACKAGE_PIN U4    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[8] }];
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[9] }];
set_property -dict { PACKAGE_PIN U2    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[10] }];
set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[11] }];
set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[12] }];
set_property -dict { PACKAGE_PIN R3    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[13] }];
set_property -dict { PACKAGE_PIN P3    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[14] }];
set_property -dict { PACKAGE_PIN P4    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[15] }];

## LEDs (LED0 - LED15) -----------------------------------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[0] }];
set_property -dict { PACKAGE_PIN V9    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[1] }];
set_property -dict { PACKAGE_PIN R8    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[2] }];
set_property -dict { PACKAGE_PIN T6    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[3] }];
set_property -dict { PACKAGE_PIN T5    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[4] }];
set_property -dict { PACKAGE_PIN T4    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[5] }];
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[6] }];
set_property -dict { PACKAGE_PIN U6    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[7] }];
set_property -dict { PACKAGE_PIN V4    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[8] }];
set_property -dict { PACKAGE_PIN U3    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[9] }];
set_property -dict { PACKAGE_PIN V1    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[10] }];
set_property -dict { PACKAGE_PIN R1    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[11] }];
set_property -dict { PACKAGE_PIN P5    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[12] }];
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[13] }];
set_property -dict { PACKAGE_PIN R2    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[14] }];
set_property -dict { PACKAGE_PIN P2    IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[15] }];

## USB-UART Interface (Conecta ao Chip FTDI que vai pro USB do PC) ---------------------------------------------------------

set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { UART_RX_i }];
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_TX_o }];
set_property -dict { PACKAGE_PIN E5    IOSTANDARD LVCMOS33 } [get_ports { UART_RTS_i }];

## =========================================================================================================================
## Interface VGA
## =========================================================================================================================

set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { VGA_R_o[0] }]; 
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { VGA_R_o[1] }]; 
set_property -dict { PACKAGE_PIN C5    IOSTANDARD LVCMOS33 } [get_ports { VGA_R_o[2] }]; 
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { VGA_R_o[3] }]; 

set_property -dict { PACKAGE_PIN C6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G_o[0] }]; 
set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { VGA_G_o[1] }]; 
set_property -dict { PACKAGE_PIN B6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G_o[2] }]; 
set_property -dict { PACKAGE_PIN A6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G_o[3] }]; 

set_property -dict { PACKAGE_PIN B7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B_o[0] }]; 
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B_o[1] }]; 
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B_o[2] }]; 
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { VGA_B_o[3] }]; 

set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { VGA_HS_o }]; 
set_property -dict { PACKAGE_PIN B12   IOSTANDARD LVCMOS33 } [get_ports { VGA_VS_o }];

## =========================================================================================================================