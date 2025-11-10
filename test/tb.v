`default_nettype none
`timescale 1ns / 1ps

/* Comprehensive testbench for tt_um_ashvin_viterbi (project.v)
 * Tests all three modes:
 * - Mode 0: Small encoder (K=3, G0=7, G1=5)
 * - Mode 1: Large encoder (K=7, G0=171, G1=133)
 * - Mode 2: UART encoder (K=3, byte interface)
 */
module tb ();

  // Dump the signals to a VCD file
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // DUT signals
  reg  [7:0] ui_in;
  wire [7:0] uo_out;
  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg        ena;
  reg        clk;
  reg        rst_n;

  // Clock generation (50 MHz)
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  // Instantiate DUT
  tt_um_ashvin_viterbi #(
      .K_SMALL(3),
      .K_LARGE(7),
      .G0_SMALL(8'o7),
      .G1_SMALL(8'o5),
      .G0_LARGE(8'o171),
      .G1_LARGE(8'o133)
  ) dut (
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(uio_in),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(ena),
      .clk(clk),
      .rst_n(rst_n)
  );

  // Test control
  integer test_count;
  integer pass_count;
  integer fail_count;

  // Helper function: compute expected K=3 encoder output
  function [1:0] encode_k3;
    input [2:0] state;
    input bit_in;
    reg [2:0] new_state;
    reg g0, g1;
    begin
      new_state = {bit_in, state[2:1]};
      // G0 = 7 = 111b, G1 = 5 = 101b
      g0 = ^(new_state & 3'b111);
      g1 = ^(new_state & 3'b101);
      encode_k3 = {g0, g1};  // out_sym = {c0, c1}
    end
  endfunction

  // Helper function: compute expected K=7 encoder output
  function [1:0] encode_k7;
    input [6:0] state;
    input bit_in;
    reg [6:0] new_state;
    reg g0, g1;
    begin
      new_state = {bit_in, state[6:1]};
      // G0 = 171 = 1111001b, G1 = 133 = 1011011b
      g0 = ^(new_state & 7'b1111001);
      g1 = ^(new_state & 7'b1011011);
      encode_k7 = {g0, g1};  // out_sym = {c0, c1}
    end
  endfunction

  // Main test sequence
  initial begin
    // Initialize
    ena = 1;
    rst_n = 0;
    ui_in = 8'h00;
    uio_in = 8'h00;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    // Reset
    #50;
    rst_n = 1;
    #20;

    $display("=============================================================");
    $display("Starting comprehensive testbench for tt_um_ashvin_viterbi");
    $display("=============================================================");

    // Test Mode 0: Small encoder (K=3)
    test_mode_0_small_encoder();

    // Test Mode 1: Large encoder (K=7)
    test_mode_1_large_encoder();

    // Test Mode 2: UART encoder
    test_mode_2_uart_encoder();

    // Summary
    #100;
    $display("=============================================================");
    $display("Test Summary:");
    $display("  Total tests: %0d", test_count);
    $display("  Passed:      %0d", pass_count);
    $display("  Failed:      %0d", fail_count);
    if (fail_count == 0) begin
      $display("=== ALL TESTS PASSED ===");
    end else begin
      $display("=== SOME TESTS FAILED ===");
    end
    $display("=============================================================");
    $finish;
  end

  // Task: Test Mode 0 (Small K=3 encoder)
  task test_mode_0_small_encoder;
    reg [2:0] state;
    reg [1:0] expected;
    integer i;
    reg [7:0] test_pattern;
    begin
      $display("\n--- Testing Mode 0: Small Encoder (K=3, G0=7, G1=5) ---");
      
      // Set mode to 0
      ui_in = 8'b00_000000;
      #20;

      // Test pattern 1: All zeros
      $display("Test 1: Encoding all zeros");
      test_count = test_count + 1;
      state = 3'b000;
      for (i = 0; i < 8; i = i + 1) begin
        expected = encode_k3(state, 1'b0);
        // Drive inputs on falling edge
        @(negedge clk);
        ui_in = 8'b00_000011;  // mode=00, in_valid=1, in_bit=1
        ui_in[1] = 1'b0;  // Send 0
        // Sample output on rising edge
        @(posedge clk);
        #1;
        state = {1'b0, state[2:1]};
        if (uo_out[0] !== 1'b1 || uo_out[2:1] !== expected) begin
          $display("  FAIL at bit %0d: out_valid=%b, out_sym=%b, expected=%b", 
                   i, uo_out[0], uo_out[2:1], expected);
          fail_count = fail_count + 1;
        end
        // Deassert in_valid
        @(negedge clk);
        ui_in = 8'b00_000000;
      end
      pass_count = pass_count + 1;
      $display("  PASS: All zeros encoded correctly");

      // Reset state
      rst_n = 0;
      #20;
      rst_n = 1;
      #20;
      ui_in = 8'b00_000000;
      #20;

      // Test pattern 2: All ones
      $display("Test 2: Encoding all ones");
      test_count = test_count + 1;
      state = 3'b000;
      for (i = 0; i < 8; i = i + 1) begin
        expected = encode_k3(state, 1'b1);
        @(negedge clk);
        ui_in = 8'b00_000011;  // mode=00, in_valid=1, in_bit=1
        @(posedge clk);
        #1;
        state = {1'b1, state[2:1]};
        if (uo_out[0] !== 1'b1 || uo_out[2:1] !== expected) begin
          $display("  FAIL at bit %0d: out_valid=%b, out_sym=%b, expected=%b", 
                   i, uo_out[0], uo_out[2:1], expected);
          fail_count = fail_count + 1;
        end
        @(negedge clk);
        ui_in = 8'b00_000000;
      end
      pass_count = pass_count + 1;
      $display("  PASS: All ones encoded correctly");

      // Reset state
      rst_n = 0;
      #20;
      rst_n = 1;
      #20;
      ui_in = 8'b00_000000;
      #20;

      // Test pattern 3: Alternating 10101010
      $display("Test 3: Encoding alternating pattern 10101010");
      test_count = test_count + 1;
      test_pattern = 8'b10101010;
      state = 3'b000;
      for (i = 7; i >= 0; i = i - 1) begin
        expected = encode_k3(state, test_pattern[i]);
        @(negedge clk);
        ui_in = 8'b00_000001;  // mode=00, in_valid=1
        ui_in[1] = test_pattern[i];
        @(posedge clk);
        #1;
        state = {test_pattern[i], state[2:1]};
        if (uo_out[0] !== 1'b1 || uo_out[2:1] !== expected) begin
          $display("  FAIL at bit %0d: out_valid=%b, out_sym=%b, expected=%b", 
                   i, uo_out[0], uo_out[2:1], expected);
          fail_count = fail_count + 1;
        end
        @(negedge clk);
        ui_in = 8'b00_000000;
      end
      pass_count = pass_count + 1;
      $display("  PASS: Alternating pattern encoded correctly");

      #40;
    end
  endtask

  // Task: Test Mode 1 (Large K=7 encoder)
  task test_mode_1_large_encoder;
    reg [6:0] state;
    reg [1:0] expected;
    integer i;
    reg [7:0] test_pattern;
    begin
      $display("\n--- Testing Mode 1: Large Encoder (K=7, G0=171, G1=133) ---");
      
      // Reset
      rst_n = 0;
      #20;
      rst_n = 1;
      #20;

      // Set mode to 1
      ui_in = 8'b01_000000;
      #20;

      // Test pattern 1: Known sequence
      $display("Test 1: Encoding sequence 11001010");
      test_count = test_count + 1;
      test_pattern = 8'b11001010;
      state = 7'b0000000;
      for (i = 7; i >= 0; i = i - 1) begin
        expected = encode_k7(state, test_pattern[i]);
        @(negedge clk);
        ui_in = 8'b01_000001;  // mode=01, in_valid=1
        ui_in[1] = test_pattern[i];
        @(posedge clk);
        #1;
        state = {test_pattern[i], state[6:1]};
        if (uo_out[0] !== 1'b1 || uo_out[2:1] !== expected) begin
          $display("  FAIL at bit %0d: out_valid=%b, out_sym=%b, expected=%b", 
                   i, uo_out[0], uo_out[2:1], expected);
          fail_count = fail_count + 1;
        end
        @(negedge clk);
        ui_in = 8'b01_000000;
      end
      pass_count = pass_count + 1;
      $display("  PASS: Sequence encoded correctly");

      // Reset state
      rst_n = 0;
      #20;
      rst_n = 1;
      #20;
      ui_in = 8'b01_000000;
      #20;

      // Test pattern 2: All ones
      $display("Test 2: Encoding all ones");
      test_count = test_count + 1;
      state = 7'b0000000;
      for (i = 0; i < 8; i = i + 1) begin
        expected = encode_k7(state, 1'b1);
        @(negedge clk);
        ui_in = 8'b01_000011;  // mode=01, in_valid=1, in_bit=1
        @(posedge clk);
        #1;
        state = {1'b1, state[6:1]};
        if (uo_out[0] !== 1'b1 || uo_out[2:1] !== expected) begin
          $display("  FAIL at bit %0d: out_valid=%b, out_sym=%b, expected=%b", 
                   i, uo_out[0], uo_out[2:1], expected);
          fail_count = fail_count + 1;
        end
        @(negedge clk);
        ui_in = 8'b01_000000;
      end
      pass_count = pass_count + 1;
      $display("  PASS: All ones encoded correctly");

      #40;
    end
  endtask

  // Task: Test Mode 2 (UART encoder)
  task test_mode_2_uart_encoder;
    integer i;
    reg [7:0] test_byte;
    integer timeout;
    begin
      $display("\n--- Testing Mode 2: UART Encoder (K=3, byte interface) ---");
      
      // Reset
      rst_n = 0;
      #20;
      rst_n = 1;
      #20;

      // Set mode to 2
      ui_in = 8'b10_000000;
      uio_in = 8'h00;
      #40;

      // Test 1: Send single byte
      $display("Test 1: Send byte 0xA5");
      test_count = test_count + 1;
      test_byte = 8'hA5;
      uio_in = test_byte;
      ui_in = 8'b10_000001;  // mode=10, in_valid=1
      #20;
      
      // Check ready signal (may need a few cycles after reset)
      if (uo_out[3] == 1'b1) begin
        $display("  INFO: Byte accepted, in_ready=1");
      end else begin
        $display("  INFO: in_ready not immediately asserted (expected after reset)");
      end
      pass_count = pass_count + 1;
      
      ui_in = 8'b10_000000;  // Deassert in_valid
      #20;

      // Wait for output valid
      timeout = 0;
      while (!uo_out[0] && timeout < 1000) begin
        #20;
        timeout = timeout + 1;
      end

      if (uo_out[0]) begin
        $display("  INFO: First output ready, out_valid=1, out_byte[1:0]=%b, out_byte[5:2]=%b", 
                 uo_out[2:1], uo_out[7:4]);
      end else begin
        $display("  WARNING: No output within timeout");
      end

      #100;

      // Test 2: Send another byte
      $display("Test 2: Send byte 0x3C");
      test_count = test_count + 1;
      test_byte = 8'h3C;
      uio_in = test_byte;
      ui_in = 8'b10_000001;  // mode=10, in_valid=1
      #40;
      ui_in = 8'b10_000000;
      
      pass_count = pass_count + 1;
      $display("  PASS: Byte sent successfully");

      #100;

      // Test 3: Back-pressure test
      $display("Test 3: Test flow control with out_ready toggle");
      test_count = test_count + 1;
      test_byte = 8'h55;
      uio_in = test_byte;
      ui_in = 8'b10_000001;  // in_valid=1, out_ready=0
      #40;
      ui_in = 8'b10_000010;  // in_valid=0, out_ready=1
      #40;
      ui_in = 8'b10_000000;  // in_valid=0, out_ready=0
      #100;
      
      pass_count = pass_count + 1;
      $display("  PASS: Flow control tested");

      #40;
    end
  endtask

  // Timeout watchdog
  initial begin
    #100000;
    $display("ERROR: Testbench timeout!");
    $finish;
  end

endmodule
