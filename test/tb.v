`default_nettype none
`timescale 1ns / 1ps

/* Simple structural wrapper that instantiates the viterbi_core directly so
   cocotb can exercise the symbol-rate handshake. */
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Expose clock/reset so cocotb can drive them.
  reg clk;
  reg rst;

  // Symbol-rate interface
  reg        rx_sym_valid;
  wire       rx_sym_ready;
  reg  [1:0] rx_sym;

  // Optional tail forcing control
  reg        force_state0;

  // Decoder output stream
  wire       dec_bit_valid;
  wire       dec_bit;

  // Clock generation (100 MHz default)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Default signal initialization; cocotb will drive thereafter.
  initial begin
    rst           = 1'b1;
    rx_sym_valid  = 1'b0;
    rx_sym        = 2'b00;
    force_state0  = 1'b0;
  end

  tt_um_viterbi_core #(
      .K      (4),
      .D      (24),
      .Wm     (6),
      .G0_OCT ('o17),
      .G1_OCT ('o13)
  ) dut (
      .clk          (clk),
      .rst          (rst),
      .rx_sym_valid (rx_sym_valid),
      .rx_sym_ready (rx_sym_ready),
      .rx_sym       (rx_sym),
      .dec_bit_valid(dec_bit_valid),
      .dec_bit      (dec_bit),
      .force_state0 (force_state0)
  );

endmodule
