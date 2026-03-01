## =============================================================================
## timing.xdc -- Timing constraints for PYNQ-Z2 (50 MHz clock)
## =============================================================================

## -------------------------------------------------------------------------
## Primary clock: 50 MHz from PS FCLK_CLK0
## Period = 20.000 ns
## -------------------------------------------------------------------------
create_clock -period 20.000 -name clk_50mhz -waveform {0.000 10.000} [get_ports { clk }]

## -------------------------------------------------------------------------
## Input delay constraints for UART RX
## UART at 115200 baud has ~8.68 us per bit -- timing is very relaxed.
## We set a conservative input delay to satisfy timing analysis.
## -------------------------------------------------------------------------
set_input_delay  -clock clk_50mhz -max 10.0 [get_ports { ja0 }]
set_input_delay  -clock clk_50mhz -min  0.0 [get_ports { ja0 }]

## -------------------------------------------------------------------------
## UART TX output -- not timing critical at 115200 baud (~8.68 us/bit)
## -------------------------------------------------------------------------
set_false_path -to [get_ports { ja1 }]

## -------------------------------------------------------------------------
## Asynchronous reset -- mark as false path
## The reset synchronizer handles the domain crossing.
## -------------------------------------------------------------------------
set_false_path -from [get_ports { btn0_n }]

## -------------------------------------------------------------------------
## LED outputs -- not timing critical
## -------------------------------------------------------------------------
set_false_path -to [get_ports { led0 led1 led2 led3 }]

## -------------------------------------------------------------------------
## UART RX is asynchronous input -- mark the double-flop path as false
## The synchronizer in uart_rx handles metastability.
## -------------------------------------------------------------------------
set_false_path -from [get_ports { ja0 }]
