`default_nettype none
`timescale 1ns / 1ps

// Comprehensive Testbench for tt_um_ashvin_viterbi (Viterbi decoder wrapper)
// Tests multiple patterns matching C golden model (viterbi_golden.c)
// When used with cocotb, define COCOTB to disable built-in tests
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

  integer i, errors, total_errors, test_count, pass_count;
  reg [1:0] syms [0:31];
  reg [31:0] test_pattern;
  reg [31:0] decoded;
  reg [7:0] test_pattern_8;
  reg [7:0] decoded_8;
  reg [15:0] test_pattern_16;
  reg [15:0] decoded_16;

  // Task to reset the DUT
  task reset_dut;
    begin
      rst_n = 0;
      ui_in = 0;
      repeat(5) @(posedge clk);
      rst_n = 1;
      repeat(2) @(posedge clk);
    end
  endtask

  // Task to run a test with n-bit pattern (up to 32 bits)
  task run_test;
    input [255:0] test_name;
    input [31:0] pattern;
    input integer num_bits;
    integer j, err;
    reg [31:0] dec;
    begin
      test_count = test_count + 1;
      $display("\n--- Test %0d: %0s (%0d bits) ---", test_count, test_name, num_bits);

      reset_dut();

      // Encode test pattern
      enc_state = 0;
      for (j = 0; j < num_bits; j = j + 1) begin
        syms[j] = encode(pattern[j]);
      end

      // Feed symbols
      for (j = 0; j < num_bits; j = j + 1) begin
        while (!rx_ready) @(posedge clk);
        ui_in = {3'b0, 1'b0, 1'b0, syms[j], 1'b1};
        @(posedge clk);
        ui_in = 0;
        @(posedge clk);
      end

      // Start decode
      ui_in = 8'b00001000;
      @(posedge clk);
      ui_in = 0;
      @(posedge clk);

      // Wait for completion
      while (busy) @(posedge clk);

      // Read decoded bits
      dec = 0;
      for (j = 0; j < num_bits; j = j + 1) begin
        while (!out_valid) begin
          @(posedge clk);
          if (frame_done && !out_valid) begin
            j = num_bits;
          end
        end
        if (j < num_bits) begin
          dec[j] = out_bit;
          ui_in = 8'b00010000;
          @(posedge clk);
          ui_in = 0;
          @(posedge clk);
        end
      end

      // Count errors
      err = 0;
      for (j = 0; j < num_bits; j = j + 1) begin
        if (dec[j] !== pattern[j]) err = err + 1;
      end

      if (err == 0) begin
        $display("  PASS: 0 errors");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: %0d errors", err);
        $display("  Input:   %h", pattern);
        $display("  Decoded: %h", dec);
      end
      total_errors = total_errors + err;
    end
  endtask

  // Generate PRBS-7 pattern
  function [31:0] gen_prbs;
    reg [2:0] lfsr;
    integer k;
    reg newbit;
    begin
      lfsr = 3'b111;
      gen_prbs = 0;
      for (k = 0; k < 32; k = k + 1) begin
        gen_prbs[k] = lfsr[0];
        newbit = lfsr[2] ^ lfsr[1];
        lfsr = {lfsr[1:0], newbit};
      end
    end
  endfunction

  // Self-contained test sequence - disabled when COCOTB is defined
  // Run with: iverilog -g2012 -o tb.vvp tb.v ../src/project.v && vvp tb.vvp
`ifndef COCOTB
  initial begin
    $display("\n========================================================");
    $display("  Viterbi Decoder K=3 Comprehensive Testbench");
    $display("  Matching C Golden Model (viterbi_golden.c)");
    $display("========================================================");

    ena = 1;
    uio_in = 0;
    total_errors = 0;
    test_count = 0;
    pass_count = 0;

    // ================================================================
    // 8-bit tests (matching C golden model)
    // ================================================================
    run_test("All Zeros 8-bit",      8'b00000000, 8);
    run_test("All Ones 8-bit",       8'b11111111, 8);
    run_test("Alternating 10",       8'b10101010, 8);
    run_test("Alternating 01",       8'b01010101, 8);
    run_test("Single 1 at start",    8'b10000000, 8);
    run_test("Single 1 at end",      8'b00000001, 8);
    run_test("Pattern 10110100",     8'b10110100, 8);
    run_test("Transition 0->1->0",   8'b00011100, 8);
    run_test("Burst 1100",           8'b11001100, 8);

    // ================================================================
    // 16-bit tests
    // ================================================================
    run_test("16-bit mixed",         16'b1010110011100010, 16);
    run_test("16-bit random",        16'b0110001110100110, 16);

    // ================================================================
    // 32-bit tests (full frame)
    // ================================================================
    run_test("32-bit all zeros",     32'h00000000, 32);
    run_test("32-bit all ones",      32'hFFFFFFFF, 32);
    run_test("32-bit repeating",     32'hB4B4B4B4, 32);  // 10110100 x4
    run_test("32-bit PRBS",          gen_prbs(), 32);

    // ================================================================
    // Summary
    // ================================================================
    $display("\n========================================================");
    $display("  TEST SUMMARY");
    $display("========================================================");
    $display("  Tests run:    %0d", test_count);
    $display("  Tests passed: %0d", pass_count);
    $display("  Tests failed: %0d", test_count - pass_count);
    $display("  Total errors: %0d", total_errors);

    if (total_errors == 0) begin
      $display("\n  *** ALL TESTS PASSED ***\n");
    end else begin
      $display("\n  *** SOME TESTS FAILED ***\n");
    end

    $display("========================================================\n");
    $finish;
  end

  // Timeout
  initial begin
    #2000000;
    $display("\nTIMEOUT!");
    $finish;
  end
`endif

endmodule
