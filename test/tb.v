`default_nettype none
`timescale 1ns / 1ps

// Testbench for tt_um_ashvin_viterbi (Viterbi decoder wrapper)
module tb ();

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
  end

  reg  [7:0] ui_in;
  wire [7:0] uo_out;
  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg        ena;
  reg        clk;
  reg        rst_n;

  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  tt_um_ashvin_viterbi dut (
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(uio_in),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(ena),
      .clk(clk),
      .rst_n(rst_n)
  );

  // Output signals
  wire rx_ready      = uo_out[0];
  wire out_valid     = uo_out[1];
  wire out_bit       = uo_out[2];
  wire busy          = uo_out[3];
  wire frame_done    = uo_out[4];

  // Encoder state for generating test symbols
  reg [1:0] enc_state;

  // Encode one bit using K=3, G0=7, G1=5 (LSB insertion)
  function [1:0] encode;
    input in_bit;
    reg [2:0] r;
    begin
      r = {enc_state, in_bit};
      encode[1] = ^(r & 3'b111);  // G0 = 7
      encode[0] = ^(r & 3'b101);  // G1 = 5
      enc_state = {enc_state[0], in_bit};
    end
  endfunction

  integer i, errors;
  reg [1:0] syms [0:31];
  reg [31:0] test_pattern;
  reg [31:0] decoded;

  initial begin
    $display("\n========================================");
    $display("  Viterbi Decoder K=3 - TT Testbench");
    $display("========================================\n");

    rst_n = 0;
    ena = 1;
    ui_in = 0;
    uio_in = 0;

    // Reset
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Test pattern: 10110100 repeated 4 times = 32 bits
    test_pattern = 32'hB4B4B4B4;

    // Encode test pattern
    $display("Encoding test pattern: %h", test_pattern);
    enc_state = 0;
    for (i = 0; i < 32; i = i + 1) begin
      syms[i] = encode(test_pattern[i]);
    end

    $display("Feeding 32 symbols to decoder...");

    // Feed all symbols first
    for (i = 0; i < 32; i = i + 1) begin
      // Wait for ready
      while (!rx_ready) @(posedge clk);

      // Send symbol: ui_in = {3'b0, read_ack, start, sym[1:0], valid}
      ui_in = {3'b0, 1'b0, 1'b0, syms[i], 1'b1};  // valid=1
      @(posedge clk);
      ui_in = 0;  // Clear valid
      @(posedge clk);
    end

    $display("Starting decode...");

    // Pulse start to begin decoding
    ui_in = 8'b00001000;  // start=1
    @(posedge clk);
    ui_in = 0;
    @(posedge clk);

    // Wait for decode to complete (busy goes low, or frame_done goes high)
    while (busy) @(posedge clk);

    $display("Reading decoded bits...");

    // Read decoded bits
    decoded = 0;
    for (i = 0; i < 32; i = i + 1) begin
      // Wait for valid output
      while (!out_valid) begin
        @(posedge clk);
        if (frame_done && !out_valid) begin
          $display("Warning: frame_done but only got %0d bits", i);
          i = 32;  // Exit loop
        end
      end
      if (i < 32) begin
        decoded[i] = out_bit;
        // Send read acknowledge
        ui_in = 8'b00010000;  // read_ack = 1
        @(posedge clk);
        ui_in = 0;
        @(posedge clk);
      end
    end

    // Count errors
    errors = 0;
    for (i = 0; i < 32; i = i + 1) begin
      if (decoded[i] !== test_pattern[i])
        errors = errors + 1;
    end

    $display("\n----------------------------------------");
    $display("  RESULTS");
    $display("----------------------------------------");
    $display("  Input pattern:   %h", test_pattern);
    $display("  Decoded pattern: %h", decoded);
    $display("  Bit errors:      %0d / 32", errors);

    if (errors == 0) begin
      $display("\n  *** TEST PASSED ***\n");
    end else begin
      $display("\n  *** TEST FAILED ***\n");
    end

    $finish;
  end

  // Timeout
  initial begin
    #500000;
    $display("\nTIMEOUT!");
    $finish;
  end

endmodule
