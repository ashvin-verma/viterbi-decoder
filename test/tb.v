`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Expose clock/reset so cocotb can drive them.
  reg clk;
  reg rst_n;

  // TT wrapper interface
  reg  [7:0] ui_in;
  wire [7:0] uo_out;
  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg        ena;

  // Expose the Viterbi-level signals for cocotb convenience
  // Inputs (directly mapped to ui_in bits):
  //   ui_in[0] = rx_sym_valid
  //   ui_in[2:1] = rx_sym[1:0]
  //   ui_in[3] = force_state0
  // Outputs (from uo_out bits):
  //   uo_out[0] = dec_bit_valid
  //   uo_out[1] = dec_bit
  //   uo_out[2] = rx_sym_ready

  // Clock generation (100 MHz default)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Default signal initialization; cocotb will drive thereafter.
  initial begin
    rst_n   = 1'b0;
    ui_in   = 8'b0;
    uio_in  = 8'b0;
    ena     = 1'b1;
  end

  tt_um_ashvin_viterbi #(
`ifdef TB_K_VAL
      .K(`TB_K_VAL),
`endif
`ifdef TB_D_VAL
      .D_TB(`TB_D_VAL),
`endif
`ifdef TB_G0_VAL
      .G0_OCT(`TB_G0_VAL),
`endif
`ifdef TB_G1_VAL
      .G1_OCT(`TB_G1_VAL),
`endif
      .RATE(2)
  ) dut (
`ifdef USE_POWER_PINS
      .VPWR(1'b1),
      .VGND(1'b0),
`endif
      .ui_in   (ui_in),
      .uo_out  (uo_out),
      .uio_in  (uio_in),
      .uio_out (uio_out),
      .uio_oe  (uio_oe),
      .ena     (ena),
      .clk     (clk),
      .rst_n   (rst_n)
  );

endmodule
