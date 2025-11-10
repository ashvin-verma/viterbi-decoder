## How it works

Multi-mode convolutional encoder with three modes:

Mode 00 (K=3): Small encoder, G0=7, G1=5 octal
Mode 01 (K=7): NASA standard, G0=171, G1=133 octal  
Mode 10: UART byte interface with K=3 encoder

Each mode implements rate 1/2 encoding: 1 input bit produces 2 output bits.

## How to test

Mode selection via ui_in[7:6]. For direct modes (00/01), send bits via ui_in[0:1]. For UART mode (10), send bytes via uio_in[7:0]. Read encoded output from uo_out.

## External hardware

Microcontroller or FPGA for pattern generation and output capture.
