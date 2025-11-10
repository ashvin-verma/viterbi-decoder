/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ashvin_viterbi #(
    parameter K = 3,
    parameter D_TB = 8,
    parameter G0_OCT = 07,
    parameter G1_OCT = 05
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

  // All output pins must be assigned. If not used, assign to 0. // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};

  
  // Internal signals for Viterbi core
    logic        rx_sym_valid_i;
    logic        rx_sym_ready_i;
    logic [1:0]  rx_sym_i;
    logic        dec_bit_valid_i;
    logic        dec_bit_i;
    logic        force_state0_i;
    logic        rst_i;

    // Instantiate Viterbi core
    tt_um_viterbi_core #(
      .K(K),
      .D(D_TB),
      .Wm(4),
      .G0_OCT(G0_OCT),
      .G1_OCT(G1_OCT)
    ) viterbi_core_inst (
      .clk(clk),
      .rst(rst_i),
      .rx_sym_valid(rx_sym_valid_i),
      .rx_sym_ready(rx_sym_ready_i),
      .rx_sym(rx_sym_i),
      .dec_bit_valid(dec_bit_valid_i),
      .dec_bit(dec_bit_i),
      .force_state0(force_state0_i)
    );

    // Drive Viterbi core input signals
    assign rst_i = ~rst_n;
    assign rx_sym_valid_i = ui_in[0];
    assign rx_sym_i = ui_in[2:1];
    assign force_state0_i = ui_in[3];
    
    // Connect Viterbi core outputs
    assign uo_out[0] = dec_bit_valid_i;
    assign uo_out[1] = dec_bit_i;
    assign uo_out[2] = rx_sym_ready_i;
    assign uo_out[7:3] = 5'b0;


endmodule
