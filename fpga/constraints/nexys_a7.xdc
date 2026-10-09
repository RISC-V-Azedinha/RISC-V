## =========================================================================================================================
## Clock Signal (100 MHz) - período definido em common.xdc
## =========================================================================================================================

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK_i }];

## =========================================================================================================================
##  Pinos para NEXYS A7 (100T) - mesma pinagem da Nexys 4 DDR
## =========================================================================================================================

## Reset (Botão Central - BTNC) --------------------------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { Reset_i }];

## Switches (SW0 - SW15) ---------------------------------------------------------------------------------------------------
## Atenção: SW8 e SW9 ficam no banco 34, alimentado em 1.8V na Nexys A7 (LVCMOS18).

set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[3] }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[4] }];
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[5] }];
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[6] }];
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[7] }];
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS18 } [get_ports { GPIO_SW_i[8] }];
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS18 } [get_ports { GPIO_SW_i[9] }];
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[10] }];
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[11] }];
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[12] }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[13] }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[14] }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { GPIO_SW_i[15] }];

## LEDs (LED0 - LED15) -----------------------------------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { GPIO_LEDS_o[15] }];

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
## Displays de 7 Segmentos (Ânodos AN0 - AN7, ativos em nível baixo) - varridos pelo GPIO
## =========================================================================================================================

set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[0] }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[2] }];
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[3] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[4] }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[5] }];
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[6] }];
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { SEG_AN_o[7] }];

## =========================================================================================================================
## Displays de 7 Segmentos (Catodos CA - CG e DP, ativos em nível baixo)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[0] }];
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[1] }];
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[2] }];
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[3] }];
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[4] }];
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[5] }];
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { SEG_CAT_o[6] }];
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { SEG_DP_o }];

## =========================================================================================================================
## Botões (BTNU, BTND, BTNL, BTNR; o BTNC é o reset)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { GPIO_BTN_i[0] }];
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { GPIO_BTN_i[1] }];
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_BTN_i[2] }];
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { GPIO_BTN_i[3] }];

## =========================================================================================================================
## LEDs RGB (LD16 = RGB0, LD17 = RGB1; bit 0 = R, 1 = G, 2 = B)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { RGB0_o[0] }];
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { RGB0_o[1] }];
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { RGB0_o[2] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { RGB1_o[0] }];
set_property -dict { PACKAGE_PIN R11   IOSTANDARD LVCMOS33 } [get_ports { RGB1_o[1] }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { RGB1_o[2] }];

## =========================================================================================================================
## Pmod JA (bit i da porta = pino i: pinos 1-4 e 7-10 do conector)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[0] }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[1] }];
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[2] }];
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[3] }];
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[4] }];
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[5] }];
set_property -dict { PACKAGE_PIN F18   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[6] }];
set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JA_io[7] }];

## =========================================================================================================================
## Pmod JB (bit i da porta = pino i: pinos 1-4 e 7-10 do conector)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[0] }];
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[1] }];
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[2] }];
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[3] }];
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[4] }];
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[5] }];
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[6] }];
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { PMOD_JB_io[7] }];

## =========================================================================================================================
## Pmod JC (bit i da porta = pino i: pinos 1-4 e 7-10 do conector)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[0] }];
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[1] }];
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[2] }];
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[3] }];
set_property -dict { PACKAGE_PIN E7    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[4] }];
set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[5] }];
set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[6] }];
set_property -dict { PACKAGE_PIN E6    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JC_io[7] }];

## =========================================================================================================================
## Pmod JD (bit i da porta = pino i: pinos 1-4 e 7-10 do conector)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[0] }];
set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[1] }];
set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[2] }];
set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[3] }];
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[4] }];
set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[5] }];
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[6] }];
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { PMOD_JD_io[7] }];

## =========================================================================================================================
## Slot de microSD (modo SPI: SCK, CMD = MOSI, DAT0 = MISO, DAT3 = CS)
## =========================================================================================================================

set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { SD_RESET_o }];
set_property -dict { PACKAGE_PIN A1    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { SD_CD_i }];
set_property -dict { PACKAGE_PIN B1    IOSTANDARD LVCMOS33 } [get_ports { SD_SCK_o }];
set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { SD_CMD_o }];
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { SD_DAT0_i }];
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT_o[1] }];
set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT_o[2] }];
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT_o[3] }];
