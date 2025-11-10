`timescale 1ns/1ps

module tb_bit_packer_8x;
  reg clk;
  reg rst;
  reg dec_bit_valid;
  reg dec_bit;
  wire out_valid;
  reg out_ready;
  wire [7:0] out_byte;
  
  // Test tracking
  integer test_num;
  integer pass_count;
  integer fail_count;
  reg test_pass;
  
  // Loop variables
  integer i, j, b, p, cycle;
  integer byte_idx, bit_idx, collected;
  integer bits_sent, bytes_received;
  
  // Test data
  reg [7:0] test_byte;
  reg [7:0] patterns [0:4];
  reg [7:0] bp_byte;
  reg [7:0] saved_byte;
  reg [7:0] gap_byte;
  reg [7:0] burst_bytes [0:3];
  reg [7:0] interleaved_bytes [0:2];
  reg [7:0] clean_byte;
  reg [7:0] reference_bytes [0:124];
  integer expected_bits;

  bit_packer_8x dut(
    .clk(clk),
    .rst(rst),
    .dec_bit_valid(dec_bit_valid),
    .dec_bit(dec_bit),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_byte(out_byte)
  );

  always #5 clk = ~clk;

  task apply_reset;
    begin
      @(posedge clk);
      #1;
      rst = 1;
      @(posedge clk);
      @(posedge clk);
      #1;
      rst = 0;
      @(posedge clk);
    end
  endtask
  
  task push_byte_lsb_first;
    input [7:0] byte_val;
    integer idx;
    begin
      for (idx = 0; idx < 8; idx = idx + 1) begin
        @(posedge clk);
        #1;
        dec_bit = byte_val[idx];
        dec_bit_valid = 1;
      end
      @(posedge clk);
      #1;
      dec_bit_valid = 0;
    end
  endtask
  
  task wait_for_valid;
    integer timeout_count;
    begin
      timeout_count = 0;
      while (!out_valid && timeout_count < 100) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
      end
      if (timeout_count >= 100) begin
        $display("  ✗ Timeout waiting for out_valid");
        $fatal(1);
      end
    end
  endtask
  
  task start_test;
    input [255:0] description;
    begin
      test_num = test_num + 1;
      test_pass = 1;
      $display("");
      $display("--- Test %0d: %s ---", test_num, description);
    end
  endtask
  
  task end_test;
    begin
      if (test_pass) begin
        $display("✓ Test %0d PASS", test_num);
        pass_count = pass_count + 1;
      end else begin
        $display("✗ Test %0d FAIL", test_num);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // Timeout watchdog
  initial begin
    #1000000;
    $display("\n*** TIMEOUT - test did not complete ***");
    $finish;
  end

  initial begin
    clk = 0;
    rst = 1;
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    
    $display("");
    $display("=======================================================");
    $display("Bit Packer 8x Testbench");
    $display("=======================================================");
    
    out_ready = 1;
    dec_bit_valid = 0;
    dec_bit = 0;

    // ==================================================================
    // Test 1: Cold reset
    // ==================================================================
    start_test("Cold reset");
    
    apply_reset();
    
    #1;
    if (out_valid !== 0) begin
      $display("  ✗ out_valid should be 0 after reset, got %b", out_valid);
      test_pass = 0;
    end else begin
      $display("  ✓ out_valid = 0 after reset");
    end
    
    if (dut.bit_count !== 0) begin
      $display("  ✗ bit_count should be 0 after reset, got %0d", dut.bit_count);
      test_pass = 0;
    end else begin
      $display("  ✓ bit_count = 0 after reset");
    end
    
    end_test();

    // ==================================================================
    // Test 2: Exact 8-bit packet (no backpressure)
    // ==================================================================
    start_test("Exact 8-bit packet (no backpressure)");
    
    apply_reset();
    out_ready = 1;
    
    test_byte = 8'b1010_1101;
    push_byte_lsb_first(test_byte);
    
    wait_for_valid();
    #1;
    
    if (out_byte !== test_byte) begin
      $display("  ✗ Byte mismatch: got %b, expected %b", out_byte, test_byte);
      test_pass = 0;
    end else begin
      $display("  ✓ Correct byte output: %b", out_byte);
    end
    
    @(posedge clk);
    #1;
    if (out_valid !== 0) begin
      $display("  ✗ out_valid should drop after handshake, got %b", out_valid);
      test_pass = 0;
    end else begin
      $display("  ✓ out_valid dropped after handshake");
    end
    
    end_test();

    // ==================================================================
    // Test 3: Bit-order confirmation
    // ==================================================================
    start_test("Bit-order confirmation");
    
    patterns[0] = 8'h00;
    patterns[1] = 8'hFF;
    patterns[2] = 8'h01;
    patterns[3] = 8'h80;
    patterns[4] = 8'h96;
    
    for (p = 0; p < 5; p = p + 1) begin
      apply_reset();
      out_ready = 1;
      
      $display("  Testing pattern: 8'h%02h", patterns[p]);
      push_byte_lsb_first(patterns[p]);
      wait_for_valid();
      #1;
      
      if (out_byte !== patterns[p]) begin
        $display("    ✗ Mismatch: got %b, expected %b", out_byte, patterns[p]);
        test_pass = 0;
      end else begin
        $display("    ✓ Match: %b", out_byte);
      end
      
      @(posedge clk);
      @(posedge clk);
    end
    
    end_test();

    // ==================================================================
    // Test 4: Backpressure on output
    // ==================================================================
    start_test("Backpressure on output");
    
    apply_reset();
    out_ready = 1;
    
    bp_byte = 8'hA5;
    
    // Send 7 bits
    for (i = 0; i < 7; i = i + 1) begin
      @(posedge clk);
      #1;
      dec_bit = bp_byte[i];
      dec_bit_valid = 1;
    end
    
    // Before 8th bit, apply backpressure
    @(posedge clk);
    #1;
    out_ready = 0;
    dec_bit = bp_byte[7];
    dec_bit_valid = 1;
    
    // One more cycle to latch the 8th bit and assert out_valid
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    // Now out_valid should be high
    if (!out_valid) begin
      $display("  ✗ out_valid not asserted after 8 bits");
      test_pass = 0;
    end
    
    if (out_byte !== bp_byte) begin
      $display("  ✗ Initial byte mismatch");
      test_pass = 0;
    end
    
    saved_byte = out_byte;
    
    // Hold backpressure for 5 cycles
    for (i = 0; i < 5; i = i + 1) begin
      @(posedge clk);
      #1;
      if (!out_valid) begin
        $display("  ✗ out_valid dropped during backpressure at cycle %0d", i);
        test_pass = 0;
      end
      if (out_byte !== saved_byte) begin
        $display("  ✗ out_byte changed during backpressure");
        test_pass = 0;
      end
    end
    
    if (test_pass) begin
      $display("  ✓ Byte held stable during backpressure");
    end
    
    // Release backpressure
    out_ready = 1;
    @(posedge clk);
    #1;
    if (out_valid !== 0) begin
      $display("  ✗ out_valid should drop after backpressure release");
      test_pass = 0;
    end else begin
      $display("  ✓ out_valid dropped after backpressure release");
    end
    
    end_test();

    // ==================================================================
    // Test 5: Gaps on input
    // ==================================================================
    start_test("Gaps on input (valid deasserted)");
    
    apply_reset();
    out_ready = 1;
    
    gap_byte = 8'b1100_0011;
    
    // Send first 3 bits
    for (i = 0; i < 3; i = i + 1) begin
      @(posedge clk);
      #1;
      dec_bit = gap_byte[i];
      dec_bit_valid = 1;
    end
    
    // Idle for 3 cycles
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    repeat (3) @(posedge clk);
    
    // Send remaining 5 bits
    for (i = 3; i < 8; i = i + 1) begin
      @(posedge clk);
      #1;
      dec_bit = gap_byte[i];
      dec_bit_valid = 1;
    end
    
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    wait_for_valid();
    #1;
    
    if (out_byte !== gap_byte) begin
      $display("  ✗ Byte mismatch with gaps: got %b, expected %b", out_byte, gap_byte);
      test_pass = 0;
    end else begin
      $display("  ✓ Correct byte with input gaps");
    end
    
    end_test();

    // ==================================================================
    // Test 6: Burst stream
    // ==================================================================
    start_test("Burst stream (4 bytes)");
    
    apply_reset();
    out_ready = 1;
    
    burst_bytes[0] = 8'h12;
    burst_bytes[1] = 8'h34;
    burst_bytes[2] = 8'h56;
    burst_bytes[3] = 8'h78;
    
    // Send 4 bytes with ready=1 (consume immediately)
    byte_idx = 0;
    bit_idx = 0;
    collected = 0;
    
    for (i = 0; i < 100 && collected < 4; i = i + 1) begin
      @(posedge clk);
      #1;
      
      // Send bits when possible
      if (byte_idx < 4 && bit_idx < 8 && !out_valid) begin
        dec_bit = burst_bytes[byte_idx][bit_idx];
        dec_bit_valid = 1;
        bit_idx = bit_idx + 1;
        if (bit_idx == 8) begin
          bit_idx = 0;
          byte_idx = byte_idx + 1;
        end
      end else begin
        dec_bit_valid = 0;
      end
      
      // Collect output
      if (out_valid && out_ready) begin
        if (out_byte !== burst_bytes[collected]) begin
          $display("  ✗ Byte %0d mismatch: got 8'h%02h, expected 8'h%02h", 
                   collected, out_byte, burst_bytes[collected]);
          test_pass = 0;
        end else begin
          $display("  ✓ Byte %0d correct: 8'h%02h", collected, out_byte);
        end
        collected = collected + 1;
      end
    end
    
    if (collected !== 4) begin
      $display("  ✗ Expected 4 bytes, got %0d", collected);
      test_pass = 0;
    end
    
    end_test();

    // ==================================================================
    // Test 7: Partial final byte
    // ==================================================================
    start_test("Partial final byte");
    
    apply_reset();
    out_ready = 1;
    
    // Send only 5 bits
    for (i = 0; i < 5; i = i + 1) begin
      @(posedge clk);
      #1;
      dec_bit = i[0];  // alternating pattern
      dec_bit_valid = 1;
    end
    
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    // Wait a bit
    repeat (10) @(posedge clk);
    #1;
    
    // Should NOT have out_valid for partial byte
    if (out_valid) begin
      $display("  ✗ out_valid should not assert for partial byte");
      test_pass = 0;
    end else begin
      $display("  ✓ No out_valid for partial byte (hold behavior)");
    end
    
    if (dut.bit_count !== 5) begin
      $display("  ✗ bit_count should be 5, got %0d", dut.bit_count);
      test_pass = 0;
    end else begin
      $display("  ✓ bit_count = 5 for partial byte");
    end
    
    end_test();

    // ==================================================================
    // Test 8: Mid-byte reset
    // ==================================================================
    start_test("Mid-byte reset");
    
    apply_reset();
    out_ready = 1;
    
    // Send 5 bits
    for (i = 0; i < 5; i = i + 1) begin
      @(posedge clk);
      #1;
      dec_bit = 1;
      dec_bit_valid = 1;
    end
    
    // Clear valid before reset
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    // Assert reset
    apply_reset();
    @(posedge clk);
    #1;
    
    $display("  DEBUG: bit_count after reset = %0d", dut.bit_count);
    
    // Check state cleared
    if (dut.bit_count !== 0) begin
      $display("  ✗ bit_count not cleared after mid-byte reset");
      test_pass = 0;
    end else begin
      $display("  ✓ bit_count cleared after reset");
    end
    
    // Send clean 8 bits
    clean_byte = 8'h3C;
    push_byte_lsb_first(clean_byte);
    wait_for_valid();
    #1;
    
    if (out_byte !== clean_byte) begin
      $display("  ✗ First byte after reset corrupted");
      test_pass = 0;
    end else begin
      $display("  ✓ Clean byte after mid-byte reset");
    end
    
    end_test();

    // ==================================================================
    // Test 9: Stress test (100 bits / 12 bytes)
    // ==================================================================
    start_test("Stress test (100 bits)");
    
    apply_reset();
    out_ready = 1;
    
    bits_sent = 0;
    bytes_received = 0;
    
    // Generate 12 reference bytes (96 bits)
    reference_bytes[0]  = 8'hA3;
    reference_bytes[1]  = 8'h5C;
    reference_bytes[2]  = 8'h71;
    reference_bytes[3]  = 8'h8E;
    reference_bytes[4]  = 8'h42;
    reference_bytes[5]  = 8'hD9;
    reference_bytes[6]  = 8'h6F;
    reference_bytes[7]  = 8'hB1;
    reference_bytes[8]  = 8'h2A;
    reference_bytes[9]  = 8'h94;
    reference_bytes[10] = 8'hC5;
    reference_bytes[11] = 8'h3E;
    
    // Send all bits byte by byte using helper
    for (i = 0; i < 12; i = i + 1) begin
      push_byte_lsb_first(reference_bytes[i]);
      bits_sent = bits_sent + 8;
      
      // Check output
      wait_for_valid();
      if (out_byte !== reference_bytes[bytes_received]) begin
        $display("  ✗ Byte %0d mismatch: got %02h, expected %02h", 
                 bytes_received, out_byte, reference_bytes[bytes_received]);
        test_pass = 0;
      end
      bytes_received = bytes_received + 1;
    end
    
    if (bytes_received !== 12) begin
      $display("  ✗ Expected 12 bytes, got %0d", bytes_received);
      test_pass = 0;
    end else begin
      $display("  ✓ All 12 bytes correct in stress test");
    end
    
    // Scoreboard check
    expected_bits = bytes_received * 8 + dut.bit_count;
    if (expected_bits !== bits_sent) begin
      $display("  ✗ Scoreboard mismatch: sent %0d, accounted %0d", bits_sent, expected_bits);
      test_pass = 0;
    end else begin
      $display("  ✓ Scoreboard balanced: %0d bits", bits_sent);
    end
    
    end_test();

    // ==================================================================
    // Summary
    // ==================================================================
    $display("");
    $display("=======================================================");
    $display("Test Summary");
    $display("=======================================================");
    $display("Total:  %0d", test_num);
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);
    
    if (fail_count == 0) begin
      $display("");
      $display("*** ALL TESTS PASSED! ***");
    end else begin
      $display("");
      $display("*** SOME TESTS FAILED ***");
    end
    $display("=======================================================");
    
    $finish;
  end
endmodule
