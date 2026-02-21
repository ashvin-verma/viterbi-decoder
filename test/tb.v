`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // TB_K can be set via -DTB_K=N on the command line
`ifndef TB_K
  `define TB_K 5
`endif

  localparam TB_K = `TB_K;

  // Generator polynomials for each K
  localparam TB_G0 = (TB_K == 3) ? 'o7  :
                     (TB_K == 5) ? 'o23 :
                     (TB_K == 7) ? 'o171 : 'o23;

  localparam TB_G1 = (TB_K == 3) ? 'o5  :
                     (TB_K == 5) ? 'o35 :
                     (TB_K == 7) ? 'o133 : 'o35;

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

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  tt_um_ashvin_viterbi
`ifndef GL_TEST
      #(
          .K      (TB_K),
          .G0_OCT (TB_G0),
          .G1_OCT (TB_G1)
      )
`endif
      dut (
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

  // Encoder state - sized for max K=7 (6-bit state)
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

  // K=5: G0=23 (10011), G1=35 (11101)
  function [1:0] encode_k5;
    input in_bit;
    reg [4:0] r;
    begin
      r = {enc_state[3:0], in_bit};
      encode_k5[1] = ^(r & 5'b10011);
      encode_k5[0] = ^(r & 5'b11101);
    end
  endfunction

  // K=7: G0=171 (1111001), G1=133 (1011011)
  function [1:0] encode_k7;
    input in_bit;
    reg [6:0] r;
    begin
      r = {enc_state, in_bit};
      encode_k7[1] = ^(r & 7'b1111001);
      encode_k7[0] = ^(r & 7'b1011011);
    end
  endfunction

  // Generic encode using TB_K
  function [1:0] encode_bit;
    input in_bit;
    begin
      case (TB_K)
        3: encode_bit = encode_k3(in_bit);
        5: encode_bit = encode_k5(in_bit);
        7: encode_bit = encode_k7(in_bit);
        default: encode_bit = encode_k5(in_bit);
      endcase
      case (TB_K)
        3: enc_state[1:0] = {enc_state[0], in_bit};
        5: enc_state[3:0] = {enc_state[2:0], in_bit};
        7: enc_state[5:0] = {enc_state[4:0], in_bit};
        default: enc_state[3:0] = {enc_state[2:0], in_bit};
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
  reg [1:0] syms [0:37];
  reg [31:0] test_pattern;
  reg [31:0] decoded;
  reg [7:0] sym_byte;
  reg [7:0] out_byte;
  integer timeout;

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

  task send_byte;
    input [7:0] data;
    begin
      timeout = 0;
      while (!byte_in_ready && timeout < 1000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 1000)
        $display("ERROR: Timeout waiting for byte_in_ready");
      uio_in = data;
      ui_in = 8'b00000001;
      @(posedge clk);
      ui_in = 0;
      @(posedge clk);
    end
  endtask

  task read_byte;
    output [7:0] data;
    begin
      timeout = 0;
      while (!byte_out_valid && timeout < 100000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 100000) begin
        $display("WARNING: Timeout waiting for byte_out_valid");
        data = 8'hXX;
      end else begin
        data = uio_out;
        ui_in = 8'b00010000;
        @(posedge clk);
        ui_in = 0;
        @(posedge clk);
      end
    end
  endtask

  task run_test;
    input [255:0] test_name;
    input [31:0] pattern;
    input integer num_bits;
    integer k2, err, num_sym_bytes, num_out_bytes;
    reg [31:0] dec;
    begin
      test_count = test_count + 1;
      $display("\n--- Test %0d: %0s (%0d bits) ---", test_count, test_name, num_bits);

      reset_dut();

      enc_state = 0;
      // Encode data bits
      for (k2 = 0; k2 < num_bits; k2 = k2 + 1)
        syms[k2] = encode_bit(pattern[k2]);
      // Encode M tail zeros
      for (k2 = num_bits; k2 < num_bits + (TB_K - 1); k2 = k2 + 1)
        syms[k2] = encode_bit(1'b0);

      num_sym_bytes = (num_bits + (TB_K - 1) + 3) / 4;
      for (k2 = 0; k2 < num_sym_bytes; k2 = k2 + 1) begin
        sym_byte = pack_symbols(
          (k2*4 < num_bits + (TB_K-1))   ? syms[k2*4]   : 2'b00,
          (k2*4+1 < num_bits + (TB_K-1)) ? syms[k2*4+1] : 2'b00,
          (k2*4+2 < num_bits + (TB_K-1)) ? syms[k2*4+2] : 2'b00,
          (k2*4+3 < num_bits + (TB_K-1)) ? syms[k2*4+3] : 2'b00
        );
        send_byte(sym_byte);
      end

      repeat(10) @(posedge clk);

      ui_in = 8'b00001000;
      @(posedge clk);
      ui_in = 0;

      timeout = 0;
      while (busy && timeout < 500000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 500000)
        $display("ERROR: Timeout waiting for decode to complete");

      dec = 0;
      num_out_bytes = (num_bits + 7) / 8;
      for (k2 = 0; k2 < num_out_bytes; k2 = k2 + 1) begin
        read_byte(out_byte);
        for (j = 0; j < 8 && (k2*8 + j) < num_bits; j = j + 1)
          dec[k2*8 + j] = out_byte[j];
      end

      err = 0;
      for (k2 = 0; k2 < num_bits; k2 = k2 + 1)
        if (dec[k2] !== pattern[k2]) err = err + 1;

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

`ifndef COCOTB
  initial begin
    $display("\n========================================================");
    $display("  Viterbi Decoder K=%0d Testbench", TB_K);
    case (TB_K)
      3: $display("  G0=7, G1=5 (octal)");
      5: $display("  G0=23, G1=35 (octal)");
      7: $display("  G0=171, G1=133 (octal)");
      default: $display("  Unknown K value");
    endcase
    $display("========================================================");

    ena = 1;
    total_errors = 0;
    test_count = 0;
    pass_count = 0;

    run_test("All Zeros 8-bit",      8'b00000000, 8);
    run_test("All Ones 8-bit",       8'b11111111, 8);
    run_test("Alternating 10",       8'b10101010, 8);
    run_test("Alternating 01",       8'b01010101, 8);
    run_test("Pattern 10110100",     8'b10110100, 8);
    run_test("16-bit mixed",         16'b1010110011100010, 16);

    // Additional patterns — single-bit isolation
    run_test("Single 1 at start",     8'b00000001, 8);
    run_test("Single 1 at end",       8'b10000000, 8);
    run_test("Single 0 in ones",      8'b11111110, 8);

    // Burst and transition
    run_test("Burst 11001100",        8'b11001100, 8);
    run_test("Transition 0->1",       8'b00001111, 8);
    run_test("Transition 1->0",       8'b11110000, 8);

    // 4-bit minimal
    run_test("4-bit 1010",            4'b1010, 4);

    // 24-bit patterns (fits all K with tails)
    run_test("24-bit zeros",          24'b000000000000000000000000, 24);
    run_test("24-bit ones",           24'b111111111111111111111111, 24);
    run_test("24-bit checker",        24'b101010101010101010101010, 24);

    $display("\n========================================================");
    $display("  TEST SUMMARY");
    $display("========================================================");
    $display("  Tests run:    %0d", test_count);
    $display("  Tests passed: %0d", pass_count);
    $display("  Tests failed: %0d", test_count - pass_count);
    $display("  Total errors: %0d", total_errors);

    if (total_errors == 0)
      $display("\n  *** ALL TESTS PASSED ***\n");
    else
      $display("\n  *** SOME TESTS FAILED ***\n");

    $display("========================================================\n");
    $finish;
  end

  initial begin
    #50000000;
    $display("\nTIMEOUT!");
    $finish;
  end
`endif

endmodule
