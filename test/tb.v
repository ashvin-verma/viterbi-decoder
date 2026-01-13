`default_nettype none
`timescale 1ns / 1ps

// Testbench for tt_um_ashvin_viterbi (parameterizable Viterbi decoder)
// Supports K=3,5,7 - set TB_K parameter to match DUT
// UART byte interface only
module tb ();

  // Testbench parameter - must match DUT's K
  parameter TB_K = 5;  // Set to 3, 5, or 7

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

  // Power pins for gate-level simulation
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  tt_um_ashvin_viterbi dut (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
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
  wire byte_in_ready  = uo_out[0];
  wire byte_out_valid = uo_out[1];
  wire busy           = uo_out[3];
  wire frame_done     = uo_out[4];

  // Encoder state - sized for max K=7
  reg [5:0] enc_state;

  // K=3: G0=7 (111), G1=5 (101)
  function [1:0] encode_k3;
    input in_bit;
    reg [2:0] r;
    begin
      r = {enc_state[1:0], in_bit};
      encode_k3[1] = ^(r & 3'b111);
      encode_k3[0] = ^(r & 3'b101);
    end
  endfunction

  // K=5: G0=23 (10011), G1=35 (11101) - common standard
  function [1:0] encode_k5;
    input in_bit;
    reg [4:0] r;
    begin
      r = {enc_state[3:0], in_bit};
      encode_k5[1] = ^(r & 5'b10011);  // G0 = 23 octal
      encode_k5[0] = ^(r & 5'b11101);  // G1 = 35 octal
    end
  endfunction

  // K=7: G0=171 (1111001), G1=133 (1011011) - NASA standard
  function [1:0] encode_k7;
    input in_bit;
    reg [6:0] r;
    begin
      r = {enc_state, in_bit};
      encode_k7[1] = ^(r & 7'b1111001);
      encode_k7[0] = ^(r & 7'b1011011);
    end
  endfunction

  // Generic encode using TB_K parameter
  function [1:0] encode_bit;
    input in_bit;
    begin
      case (TB_K)
        3: encode_bit = encode_k3(in_bit);
        5: encode_bit = encode_k5(in_bit);
        7: encode_bit = encode_k7(in_bit);
        default: encode_bit = encode_k7(in_bit);
      endcase
      // Update state based on K
      case (TB_K)
        3: enc_state[1:0] = {enc_state[0], in_bit};
        5: enc_state[3:0] = {enc_state[2:0], in_bit};
        7: enc_state[5:0] = {enc_state[4:0], in_bit};
        default: enc_state[5:0] = {enc_state[4:0], in_bit};
      endcase
    end
  endfunction

  // Pack 4 symbols into a byte
  function [7:0] pack_symbols;
    input [1:0] s0, s1, s2, s3;
    begin
      pack_symbols = {s3, s2, s1, s0};
    end
  endfunction

  integer i, j, errors, total_errors, test_count, pass_count;
  reg [1:0] syms [0:31];
  reg [31:0] test_pattern;
  reg [31:0] decoded;
  reg [7:0] sym_byte;
  reg [7:0] out_byte;
  integer timeout;

  // Task to reset the DUT
  task reset_dut;
    begin
      rst_n = 0;
      ui_in = 0;
      uio_in = 0;
      repeat(10) @(posedge clk);
      rst_n = 1;
      repeat(5) @(posedge clk);
    end
  endtask

  // Task to send a symbol byte (4 symbols)
  task send_byte;
    input [7:0] data;
    begin
      timeout = 0;
      while (!byte_in_ready && timeout < 1000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 1000) begin
        $display("ERROR: Timeout waiting for byte_in_ready");
      end
      uio_in = data;
      ui_in = 8'b00000001;  // byte_valid
      @(posedge clk);
      ui_in = 0;
      @(posedge clk);
    end
  endtask

  // Task to read output byte
  task read_byte;
    output [7:0] data;
    begin
      timeout = 0;
      while (!byte_out_valid && timeout < 10000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 10000) begin
        $display("WARNING: Timeout waiting for byte_out_valid");
        data = 8'hXX;
      end else begin
        data = uio_out;
        ui_in = 8'b00010000;  // read_ack
        @(posedge clk);
        ui_in = 0;
        @(posedge clk);
      end
    end
  endtask

  // Task to run a test with n-bit pattern
  task run_test;
    input [255:0] test_name;
    input [31:0] pattern;
    input integer num_bits;
    integer k, err, num_sym_bytes, num_out_bytes;
    reg [31:0] dec;
    begin
      test_count = test_count + 1;
      $display("\n--- Test %0d: %0s (%0d bits) ---", test_count, test_name, num_bits);

      reset_dut();

      // Encode test pattern
      enc_state = 0;
      for (k = 0; k < num_bits; k = k + 1) begin
        syms[k] = encode_bit(pattern[k]);
      end

      // Send symbol bytes (4 symbols per byte)
      num_sym_bytes = (num_bits + 3) / 4;
      for (k = 0; k < num_sym_bytes; k = k + 1) begin
        sym_byte = pack_symbols(
          (k*4 < num_bits) ? syms[k*4] : 2'b00,
          (k*4+1 < num_bits) ? syms[k*4+1] : 2'b00,
          (k*4+2 < num_bits) ? syms[k*4+2] : 2'b00,
          (k*4+3 < num_bits) ? syms[k*4+3] : 2'b00
        );
        send_byte(sym_byte);
      end

      // Wait for symbols to be processed
      repeat(10) @(posedge clk);

      // Start decode
      ui_in = 8'b00001000;  // start
      @(posedge clk);
      ui_in = 0;

      // Wait for completion (K=7 takes longer: 64 states * num_bits cycles for ACS)
      timeout = 0;
      while (busy && timeout < 100000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 100000) begin
        $display("ERROR: Timeout waiting for decode to complete");
      end

      // Read decoded bytes
      dec = 0;
      num_out_bytes = (num_bits + 7) / 8;
      for (k = 0; k < num_out_bytes; k = k + 1) begin
        read_byte(out_byte);
        for (j = 0; j < 8 && (k*8 + j) < num_bits; j = j + 1) begin
          dec[k*8 + j] = out_byte[j];
        end
      end

      // Count errors
      err = 0;
      for (k = 0; k < num_bits; k = k + 1) begin
        if (dec[k] !== pattern[k]) err = err + 1;
      end

      // Always show input vs decoded (binary, LSB first as transmitted)
      $display("  Input:   %08b (hex: %02h)", pattern[7:0], pattern[7:0]);
      $display("  Decoded: %08b (hex: %02h)", dec[7:0], dec[7:0]);
      if (num_bits > 8) begin
        $display("  Input:   %08b (hex: %02h) [bits 15:8]", pattern[15:8], pattern[15:8]);
        $display("  Decoded: %08b (hex: %02h) [bits 15:8]", dec[15:8], dec[15:8]);
      end
      if (err == 0) begin
        $display("  PASS: 0 errors");
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: %0d errors", err);
      end
      total_errors = total_errors + err;
    end
  endtask

  // Self-contained test sequence - disabled when COCOTB is defined
`ifndef COCOTB
  initial begin
    $display("\n========================================================");
    $display("  Viterbi Decoder K=%0d Testbench", TB_K);
    case (TB_K)
      3: $display("  G0=7, G1=5 (octal)");
      5: $display("  G0=23, G1=35 (octal)");
      7: $display("  NASA Standard: G0=171, G1=133 (octal)");
      default: $display("  Unknown K value");
    endcase
    $display("========================================================");

    ena = 1;
    total_errors = 0;
    test_count = 0;
    pass_count = 0;

    // 8-bit tests
    run_test("All Zeros 8-bit",      8'b00000000, 8);
    run_test("All Ones 8-bit",       8'b11111111, 8);
    run_test("Alternating 10",       8'b10101010, 8);
    run_test("Alternating 01",       8'b01010101, 8);
    run_test("Pattern 10110100",     8'b10110100, 8);

    // 16-bit tests
    run_test("16-bit mixed",         16'b1010110011100010, 16);

    // Summary
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
    #50000000;
    $display("\nTIMEOUT!");
    $finish;
  end
`endif

endmodule
