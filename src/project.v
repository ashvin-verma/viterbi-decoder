/*
 * Copyright (c) 2024 Ashvin Verma
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns/1ps

module tt_um_ashvin_viterbi #(
    parameter K_SMALL = 3,
    parameter K_LARGE = 7,
    parameter G0_SMALL = 8'o7,
    parameter G1_SMALL = 8'o5,
    parameter G0_LARGE = 8'o171,
    parameter G1_LARGE = 8'o133
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Reset is active low externally, active high internally
    wire rst = ~rst_n;
    
    // Mode selection: ui_in[7:6]
    // 00: Small encoder (K=3)
    // 01: Large encoder (K=7)
    // 10: UART encoder
    // 11: Reserved
    wire [1:0] mode = ui_in[7:6];
    
    // Small encoder (K=3, NASA standard for low complexity)
    wire small_in_valid = ui_in[0] && (mode == 2'b00);
    wire small_in_bit = ui_in[1];
    wire small_out_valid;
    wire [1:0] small_out_sym;
    
    conv_encoder_1_2 #(
        .K(K_SMALL),
        .G0_OCT(G0_SMALL),
        .G1_OCT(G1_SMALL)
    ) small_encoder (
        .clk(clk),
        .rst(rst),
        .seed_load(1'b0),
        .seed_value(2'b00),
        .in_valid(small_in_valid),
        .in_bit(small_in_bit),
        .out_valid(small_out_valid),
        .out_sym(small_out_sym)
    );
    
    // Large encoder (K=7, NASA standard for high performance)
    wire large_in_valid = ui_in[0] && (mode == 2'b01);
    wire large_in_bit = ui_in[1];
    wire large_out_valid;
    wire [1:0] large_out_sym;
    
    conv_encoder_1_2 #(
        .K(K_LARGE),
        .G0_OCT(G0_LARGE),
        .G1_OCT(G1_LARGE)
    ) large_encoder (
        .clk(clk),
        .rst(rst),
        .seed_load(1'b0),
        .seed_value(6'b000000),
        .in_valid(large_in_valid),
        .in_bit(large_in_bit),
        .out_valid(large_out_valid),
        .out_sym(large_out_sym)
    );
    
    // UART encoder (K=3, byte-oriented interface)
    wire uart_in_valid = ui_in[0] && (mode == 2'b10);
    wire uart_in_ready;
    wire [7:0] uart_in_byte = uio_in;
    wire uart_out_valid;
    wire uart_out_ready = ui_in[1];
    wire [7:0] uart_out_byte;
    
    uart_conv_encoder #(
        .K(K_SMALL),
        .G0_OCT(G0_SMALL),
        .G1_OCT(G1_SMALL)
    ) uart_encoder (
        .clk(clk),
        .rst(rst),
        .in_valid(uart_in_valid),
        .in_ready(uart_in_ready),
        .in_byte(uart_in_byte),
        .out_valid(uart_out_valid),
        .out_ready(uart_out_ready),
        .out_byte(uart_out_byte)
    );
    
    // Output multiplexing based on mode
    // uo_out[0] = out_valid
    // uo_out[2:1] = encoded symbol (for direct encoders) or status (for UART)
    // uo_out[3] = ready signal (for UART mode)
    // uo_out[7:4] = upper bits of output byte (for UART mode)
    
    assign uo_out[0] = (mode == 2'b00) ? small_out_valid :
                       (mode == 2'b01) ? large_out_valid :
                       (mode == 2'b10) ? uart_out_valid : 1'b0;
    
    assign uo_out[2:1] = (mode == 2'b00) ? small_out_sym :
                         (mode == 2'b01) ? large_out_sym :
                         (mode == 2'b10) ? uart_out_byte[1:0] : 2'b00;
    
    assign uo_out[3] = (mode == 2'b10) ? uart_in_ready : 1'b0;
    
    assign uo_out[7:4] = (mode == 2'b10) ? uart_out_byte[5:2] : 4'b0000;
    
    // Bidirectional I/O configuration
    // In UART mode: uio is input for data bytes
    // Otherwise: unused
    assign uio_out = 8'h00;
    assign uio_oe = 8'h00;  // All inputs
    
    // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[5:2], 1'b0};

endmodule
