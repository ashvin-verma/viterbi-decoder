/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ashvin_viterbi #(
    parameter K = 7,
    parameter D_TB = 42,
    parameter RATE = 2,
    parameter G0_OCT = 'o171,
    parameter G1_OCT = 'o133,
    parameter G2_OCT = 'o0
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

  // ---------------------------------------------------------------
  // Mode select: ui_in[7]
  //   0 = raw symbol streaming  (backward-compatible)
  //   1 = UART byte batch mode  (sym_unpacker_4x + bit_packer_8x)
  // ---------------------------------------------------------------
  wire mode = ui_in[7];

  // Reset (active-high for internal modules)
  wire rst_i = ~rst_n;

  // ---------------------------------------------------------------
  // Internal signals for Viterbi core
  // ---------------------------------------------------------------
  logic              rx_sym_valid_i;
  logic              rx_sym_ready_i;
  logic [RATE-1:0]   rx_sym_i;
  logic        dec_bit_valid_i;
  logic        dec_bit_i;
  logic        force_state0_i;

  // ---------------------------------------------------------------
  // Viterbi core instance (shared by both modes)
  // ---------------------------------------------------------------
  tt_um_viterbi_core #(
    .K(K),
    .D(D_TB),
    .Wm(8),
    .RATE(RATE),
    .G0_OCT(G0_OCT),
    .G1_OCT(G1_OCT),
    .G2_OCT(G2_OCT)
  ) viterbi_core_inst (
    .clk           (clk),
    .rst           (rst_i),
    .rx_sym_valid  (rx_sym_valid_i),
    .rx_sym_ready  (rx_sym_ready_i),
    .rx_sym        (rx_sym_i),
    .dec_bit_valid (dec_bit_valid_i),
    .dec_bit       (dec_bit_i),
    .force_state0  (force_state0_i)
  );

  // ---------------------------------------------------------------
  // Mode 1: Symbol unpacker
  //   RATE=2: sym_unpacker_4x  (byte -> 4 x 2-bit symbols)
  //   RATE=3: sym_unpacker_2x3 (byte -> 2 x 3-bit symbols)
  // ---------------------------------------------------------------
  wire             unp_in_valid;
  wire             unp_in_ready;
  wire [7:0]       unp_in_byte;
  wire             unp_rx_sym_valid;
  wire [RATE-1:0]  unp_rx_sym;

  generate
    if (RATE == 3) begin : gen_unp_r3
      sym_unpacker_2x3 sym_unpacker_inst (
        .clk          (clk),
        .rst          (rst_i),
        .in_valid     (unp_in_valid),
        .in_ready     (unp_in_ready),
        .in_byte      (unp_in_byte),
        .rx_sym_valid (unp_rx_sym_valid),
        .rx_sym_ready (rx_sym_ready_i),
        .rx_sym       (unp_rx_sym)
      );
    end else begin : gen_unp_r2
      sym_unpacker_4x sym_unpacker_inst (
        .clk          (clk),
        .rst          (rst_i),
        .in_valid     (unp_in_valid),
        .in_ready     (unp_in_ready),
        .in_byte      (unp_in_byte),
        .rx_sym_valid (unp_rx_sym_valid),
        .rx_sym_ready (rx_sym_ready_i),
        .rx_sym       (unp_rx_sym)
      );
    end
  endgenerate

  // ---------------------------------------------------------------
  // Mode 1: bit_packer_8x  (8 decoded bits -> byte)
  // ---------------------------------------------------------------
  wire        pck_out_valid;
  wire        pck_out_ready;
  wire [7:0]  pck_out_byte;

  bit_packer_8x bit_packer_inst (
    .clk           (clk),
    .rst           (rst_i),
    .dec_bit_valid (dec_bit_valid_i),
    .dec_bit       (dec_bit_i),
    .out_valid     (pck_out_valid),
    .out_ready     (pck_out_ready),
    .out_byte      (pck_out_byte)
  );

  // ---------------------------------------------------------------
  // Mode 1 input mapping
  //   uio_in[7:0]  = input byte (4 packed 2-bit symbols)
  //   ui_in[0]     = byte_valid
  //   ui_in[3]     = force_state0 (tail termination)
  //   ui_in[4]     = read_ack
  // ---------------------------------------------------------------
  assign unp_in_valid = mode ? ui_in[0]    : 1'b0;
  assign unp_in_byte  = mode ? uio_in[7:0] : 8'b0;
  assign pck_out_ready = mode ? ui_in[4]   : 1'b0;

  // ---------------------------------------------------------------
  // Busy / Done indicators for Mode 1
  //   busy = unpacker has data OR packer has not yet produced output
  //   done = packer output is valid (byte ready to read)
  // ---------------------------------------------------------------
  wire batch_busy = ~unp_in_ready | pck_out_valid;
  wire batch_done = pck_out_valid;

  // ---------------------------------------------------------------
  // Mux core inputs based on mode
  // ---------------------------------------------------------------
  // Mode 0: raw streaming from ui_in
  // Mode 1: from sym_unpacker (4x for RATE=2, 2x3 for RATE=3)
  assign rx_sym_valid_i = mode ? unp_rx_sym_valid : ui_in[0];
  assign rx_sym_i       = mode ? unp_rx_sym       : ui_in[RATE:1];
  assign force_state0_i = ui_in[3]; // same pin in both modes

  // ---------------------------------------------------------------
  // Output mux
  // ---------------------------------------------------------------
  // Mode 0 outputs (backward compatible):
  //   uo_out[0] = dec_bit_valid
  //   uo_out[1] = dec_bit
  //   uo_out[2] = rx_sym_ready
  //   uo_out[7:3] = 0
  //
  // Mode 1 outputs:
  //   uo_out[0] = byte_in_ready  (unpacker ready for next byte)
  //   uo_out[1] = byte_out_valid (packer has output byte)
  //   uo_out[2] = rx_sym_ready   (still visible)
  //   uo_out[3] = busy
  //   uo_out[4] = done
  //   uo_out[7:5] = 0

  assign uo_out[0] = mode ? unp_in_ready     : dec_bit_valid_i;
  assign uo_out[1] = mode ? pck_out_valid     : dec_bit_i;
  assign uo_out[2] = rx_sym_ready_i; // visible in both modes
  assign uo_out[3] = mode ? batch_busy        : 1'b0;
  assign uo_out[4] = mode ? batch_done        : 1'b0;
  assign uo_out[7:5] = 3'b0;

  // ---------------------------------------------------------------
  // Bidirectional I/O
  // ---------------------------------------------------------------
  // Mode 0: uio unused (all inputs)
  // Mode 1: uio_out = packer output byte (all outputs)
  assign uio_out = mode ? pck_out_byte : 8'h00;
  assign uio_oe  = mode ? 8'hFF       : 8'h00;

  // ---------------------------------------------------------------
  // Unused signals
  // ---------------------------------------------------------------
  wire _unused = &{ena, ui_in[6:5], 1'b0};

endmodule
