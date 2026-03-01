## =============================================================================
## pynq_z2.xdc -- Pin constraints for PYNQ-Z2 board (XC7Z020-1CLG400C)
##
## UART on Pmod A (JA), LEDs for status, BTN0 for reset.
## No AXI / PS interaction -- pure PL design.
## =============================================================================

## -------------------------------------------------------------------------
## Clock: PS FCLK_CLK0 directly to PL fabric via BUFG
## On PYNQ-Z2, the 50 MHz PS clock appears at pin H16.
## (This is the direct PS-to-PL clock; no external oscillator needed.)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { clk }]

## -------------------------------------------------------------------------
## Reset: BTN0 (active-low pushbutton)
## PYNQ-Z2 BTN0 is directly connected to PL pin D19.
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn0_n }]

## -------------------------------------------------------------------------
## Pmod A (JA) -- UART pins
##
## PYNQ-Z2 Pmod A pin mapping:
##   JA[0] / Pin 1 = Y18    (top row, leftmost)
##   JA[1] / Pin 2 = Y19    (top row)
##   JA[2] / Pin 3 = Y16    (top row)
##   JA[3] / Pin 4 = Y17    (top row)
##   JA[4] / Pin 7 = U18    (bottom row, leftmost)
##   JA[5] / Pin 8 = U19    (bottom row)
##   JA[6] / Pin 9 = W18    (bottom row)
##   JA[7] / Pin 10= W19    (bottom row)
##
## We use:
##   ja0 (UART RX, FPGA input)  = JA Pin 1 = Y18
##   ja1 (UART TX, FPGA output) = JA Pin 2 = Y19
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { ja0 }]
set_property -dict { PACKAGE_PIN Y19   IOSTANDARD LVCMOS33 } [get_ports { ja1 }]

## Pull-up on UART RX to keep line idle-high when disconnected
set_property PULLUP TRUE [get_ports { ja0 }]

## -------------------------------------------------------------------------
## LEDs (accent LEDs directly on PL)
##
## PYNQ-Z2 LED mapping:
##   LD0 = R14
##   LD1 = P14
##   LD2 = N16
##   LD3 = M14
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led0 }]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led1 }]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led2 }]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led3 }]

## -------------------------------------------------------------------------
## Configuration voltage and CFGBVS
## Required for Zynq designs to avoid DRC warnings.
## -------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
