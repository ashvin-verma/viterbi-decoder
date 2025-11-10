<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This is a convolutional encoder that encodes input bits into symbols for error correction. It implements a rate 1/2 convolutional encoder with constraint length K=3, using generator polynomials G0=7 (octal) and G1=5 (octal). For each input bit, it produces two output symbol bits.

## How to test

Provide input bits through the BIT_IN pin with BIT_VALID high. The encoder will output two symbol bits (SYM_OUT0, SYM_OUT1) when SYM_VALID goes high.

## External hardware

FPGA or microcontroller to provide input bits and capture encoded symbols.