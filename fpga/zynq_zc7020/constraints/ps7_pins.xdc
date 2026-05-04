## =============================================================================
## ps7_pins.xdc -- Pin constraints for PS7 block design on PYNQ-Z2
##
## Only PL I/O pins need constraints here.  PS7 DDR and MIO pins are
## automatically constrained by the processing_system7 IP.
## =============================================================================

## -------------------------------------------------------------------------
## LEDs (accent LEDs directly on PL)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led0 }]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led1 }]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led2 }]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led3 }]

## -------------------------------------------------------------------------
## LED timing -- not critical
## -------------------------------------------------------------------------
set_false_path -to [get_ports { led0 led1 led2 led3 }]

## -------------------------------------------------------------------------
## Configuration voltage
## -------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
