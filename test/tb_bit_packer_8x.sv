module tb_bit_packer_8x;
  logic clk = 0;
  logic rst = 1;
  logic dec_bit_valid;
  logic dec_bit;
  logic out_valid;
  logic out_ready;
  logic [7:0] out_byte;
  
  // Test tracking
  int test_num = 0;
  int pass_count = 0;
  int fail_count = 0;
  logic test_pass;

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

  task push_bit(input bit b);
    begin
      @(posedge clk);
      #1;  // Avoid race with DUT sampling
      dec_bit       = b;
      dec_bit_valid = 1;
      @(posedge clk);
      #1;
      dec_bit_valid = 0;
    end
  endtask
  
  task push_byte_lsb_first(input logic [7:0] byte_val);
    begin
      for (int i = 0; i < 8; i++) begin
        @(posedge clk);
        #1;
        dec_bit = byte_val[i];
        dec_bit_valid = 1;
      end
      @(posedge clk);
      #1;
      dec_bit_valid = 0;
    end
  endtask
  
  task wait_for_valid(input int max_cycles = 100);
    begin
      fork
        begin
          wait (out_valid);
        end
        begin
          repeat (max_cycles) @(posedge clk);
          $fatal(1, "Timeout waiting for out_valid");
        end
      join_any
      disable fork;
    end
  endtask
  
  task apply_reset();
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
  
  task start_test(input string description);
    begin
      test_num++;
      test_pass = 1;
      $display("\n--- Test %0d: %s ---", test_num, description);
    end
  endtask
  
  task end_test();
    begin
      if (test_pass) begin
        $display("✓ Test %0d PASS", test_num);
        pass_count++;
      end else begin
        $display("✗ Test %0d FAIL", test_num);
        fail_count++;
      end
    end
  endtask

  // Timeout watchdog
  initial begin
    #1000000;
    $display("\n*** TIMEOUT - test did not complete ***");
    $fatal(1, "Testbench timeout");
  end

  initial begin
    $display("\n=======================================================");
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
    
    logic [7:0] test_byte = 8'b1010_1101;
    push_byte_lsb_first(test_byte);
    
    wait_for_valid();
    
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
    
    logic [7:0] patterns[5] = '{8'h00, 8'hFF, 8'h01, 8'h80, 8'h96};
    
    for (int p = 0; p < 5; p++) begin
      apply_reset();
      out_ready = 1;
      
      $display("  Testing pattern: 8'h%02h", patterns[p]);
      push_byte_lsb_first(patterns[p]);
      wait_for_valid();
      
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
    
    logic [7:0] bp_byte = 8'hA5;
    push_byte_lsb_first(bp_byte);
    wait_for_valid();
    
    if (out_byte !== bp_byte) begin
      $display("  ✗ Initial byte mismatch");
      test_pass = 0;
    end
    
    // Hold backpressure
    @(posedge clk);
    #1;
    out_ready = 0;
    logic [7:0] saved_byte = out_byte;
    
    repeat (5) begin
      @(posedge clk);
      #1;
      if (!out_valid) begin
        $display("  ✗ out_valid dropped during backpressure");
        test_pass = 0;
      end
      if (out_byte !== saved_byte) begin
        $display("  ✗ out_byte changed during backpressure");
        test_pass = 0;
      end
    end
    
    $display("  ✓ Byte held stable during backpressure");
    
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
    
    logic [7:0] gap_byte = 8'b1100_0011;
    
    // Send first 3 bits
    for (int i = 0; i < 3; i++) begin
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
    for (int i = 3; i < 8; i++) begin
      @(posedge clk);
      #1;
      dec_bit = gap_byte[i];
      dec_bit_valid = 1;
    end
    
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    wait_for_valid();
    
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
    
    logic [7:0] burst_bytes[4] = '{8'h12, 8'h34, 8'h56, 8'h78};
    
    // Send all 32 bits continuously
    for (int b = 0; b < 4; b++) begin
      for (int i = 0; i < 8; i++) begin
        @(posedge clk);
        #1;
        dec_bit = burst_bytes[b][i];
        dec_bit_valid = 1;
      end
    end
    
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    
    // Collect 4 bytes
    for (int b = 0; b < 4; b++) begin
      wait_for_valid();
      
      if (out_byte !== burst_bytes[b]) begin
        $display("  ✗ Byte %0d mismatch: got %b, expected %b", b, out_byte, burst_bytes[b]);
        test_pass = 0;
      end else begin
        $display("  ✓ Byte %0d correct: 8'h%02h", b, out_byte);
      end
      
      @(posedge clk);
      #1;
    end
    
    end_test();

    // ==================================================================
    // Test 7: Interleaved I/O backpressure
    // ==================================================================
    start_test("Interleaved I/O backpressure");
    
    apply_reset();
    
    logic [7:0] interleaved_bytes[3] = '{8'hAA, 8'h55, 8'hF0};
    int byte_idx = 0;
    int bit_idx = 0;
    int collected = 0;
    
    // Send bits with random backpressure
    for (int cycle = 0; cycle < 100 && collected < 3; cycle++) begin
      @(posedge clk);
      #1;
      
      // Random backpressure
      out_ready = ($urandom % 3) != 0;  // ~66% ready
      
      // Send bits
      if (byte_idx < 3 && bit_idx < 8) begin
        dec_bit = interleaved_bytes[byte_idx][bit_idx];
        dec_bit_valid = 1;
        bit_idx++;
        if (bit_idx == 8) begin
          bit_idx = 0;
          byte_idx++;
        end
      end else begin
        dec_bit_valid = 0;
      end
      
      // Check output
      if (out_valid && out_ready) begin
        if (out_byte !== interleaved_bytes[collected]) begin
          $display("  ✗ Byte %0d mismatch with backpressure", collected);
          test_pass = 0;
        end
        collected++;
      end
    end
    
    if (collected !== 3) begin
      $display("  ✗ Expected 3 bytes, got %0d", collected);
      test_pass = 0;
    end else begin
      $display("  ✓ All bytes correct with interleaved backpressure");
    end
    
    end_test();

    // ==================================================================
    // Test 8: Partial final byte
    // ==================================================================
    start_test("Partial final byte");
    
    apply_reset();
    out_ready = 1;
    
    // Send only 5 bits
    for (int i = 0; i < 5; i++) begin
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
    // Test 9: Mid-byte reset
    // ==================================================================
    start_test("Mid-byte reset");
    
    apply_reset();
    out_ready = 1;
    
    // Send 5 bits
    for (int i = 0; i < 5; i++) begin
      @(posedge clk);
      #1;
      dec_bit = 1;
      dec_bit_valid = 1;
    end
    
    // Assert reset
    apply_reset();
    
    // Check state cleared
    if (dut.bit_count !== 0) begin
      $display("  ✗ bit_count not cleared after mid-byte reset");
      test_pass = 0;
    end else begin
      $display("  ✓ bit_count cleared after reset");
    end
    
    // Send clean 8 bits
    logic [7:0] clean_byte = 8'h3C;
    push_byte_lsb_first(clean_byte);
    wait_for_valid();
    
    if (out_byte !== clean_byte) begin
      $display("  ✗ First byte after reset corrupted");
      test_pass = 0;
    end else begin
      $display("  ✓ Clean byte after mid-byte reset");
    end
    
    end_test();

    // ==================================================================
    // Test 10: Double-width stress (simplified)
    // ==================================================================
    start_test("Stress test (1000 bits)");
    
    apply_reset();
    
    int bits_sent = 0;
    int bytes_received = 0;
    logic [7:0] reference_bytes[125];
    
    // Generate reference
    for (int i = 0; i < 125; i++) begin
      reference_bytes[i] = $urandom & 8'hFF;
    end
    
    // Send 1000 bits (125 bytes) with random backpressure
    for (int i = 0; i < 1000; i++) begin
      @(posedge clk);
      #1;
      
      out_ready = ($urandom % 4) != 0;  // 75% ready
      
      dec_bit = reference_bytes[i/8][i%8];
      dec_bit_valid = 1;
      bits_sent++;
      
      if (out_valid && out_ready) begin
        if (out_byte !== reference_bytes[bytes_received]) begin
          $display("  ✗ Byte %0d mismatch in stress test", bytes_received);
          test_pass = 0;
          break;
        end
        bytes_received++;
      end
    end
    
    @(posedge clk);
    #1;
    dec_bit_valid = 0;
    out_ready = 1;
    
    // Collect remaining bytes
    while (bytes_received < 125) begin
      @(posedge clk);
      #1;
      if (out_valid) begin
        if (out_byte !== reference_bytes[bytes_received]) begin
          $display("  ✗ Byte %0d mismatch in cleanup", bytes_received);
          test_pass = 0;
          break;
        end
        bytes_received++;
      end
      
      if (bytes_received >= 200) break;  // Safety
    end
    
    if (bytes_received !== 125) begin
      $display("  ✗ Expected 125 bytes, got %0d", bytes_received);
      test_pass = 0;
    end else begin
      $display("  ✓ All 125 bytes correct in stress test");
    end
    
    // Scoreboard check
    int expected_bits = bytes_received * 8 + dut.bit_count;
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
    $display("\n=======================================================");
    $display("Test Summary");
    $display("=======================================================");
    $display("Total:  %0d", test_num);
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);
    
    if (fail_count == 0) begin
      $display("\n*** ALL TESTS PASSED! ***");
    end else begin
      $display("\n*** SOME TESTS FAILED ***");
    end
    $display("=======================================================");
    
    $finish;
  end
endmodule
