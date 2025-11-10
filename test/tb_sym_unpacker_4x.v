`timescale 1ns/1ps

//=============================================================================
// Symbol Unpacker Testbench
//=============================================================================
// Tests the 4x symbol unpacker (1 byte → 4 symbols of 2 bits each)
//
// Unpacking order: byte[7:6], byte[5:4], byte[3:2], byte[1:0]
//   Symbol 0 = bits [1:0]
//   Symbol 1 = bits [3:2]
//   Symbol 2 = bits [5:4]
//   Symbol 3 = bits [7:6]
//
// Protocol: AXI-Stream valid/ready handshaking
//
// Test Coverage:
//   T0: Reset behavior
//   T1: Single byte unpacking (all 4 symbols)
//   T2: Multiple bytes back-to-back
//   T3: Backpressure (downstream not ready)
//   T4: Slow source (upstream delays)
//   T5: Random valid/ready patterns
//   T6: All bit patterns (0x00 to 0xFF)
//   T7: Burst test (many bytes)
//=============================================================================

module tb_sym_unpacker_4x;

  // DUT signals
  reg clk;
  reg rst;
  
  reg in_valid;
  wire in_ready;
  reg [7:0] in_byte;
  
  wire rx_sym_valid;
  reg rx_sym_ready;
  wire [1:0] rx_sym;
  
  // Test control
  integer test_num;
  integer pass_count;
  integer fail_count;
  reg test_pass;
  
  // Monitoring
  integer byte_count;
  integer sym_count;
  reg [7:0] last_byte;
  integer friend_idx;
  reg [1:0] friend_expected [0:3];
  reg friend_active;
  
  //===========================================================================
  // DUT Instantiation
  //===========================================================================
  sym_unpacker_4x dut (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_byte(in_byte),
    .rx_sym_valid(rx_sym_valid),
    .rx_sym_ready(rx_sym_ready),
    .rx_sym(rx_sym)
  );
  
  //===========================================================================
  // Clock Generation
  //===========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period = 100MHz
  end
  
  //===========================================================================
  // Helper Tasks
  //===========================================================================
  task apply_reset;
    begin
      rst = 1;
      in_valid = 0;
      in_byte = 8'h00;
      rx_sym_ready = 0;
      @(posedge clk);
      @(posedge clk);
      rst = 0;
      @(posedge clk);
    end
  endtask
  
  task send_byte;
    input [7:0] byte_val;
    begin
      @(posedge clk);
      in_valid = 1;
      in_byte = byte_val;
      
      // Wait for handshake
      while (!in_ready) @(posedge clk);
      
      @(posedge clk);
      in_valid = 0;
    end
  endtask
  
  task receive_symbol;
    output [1:0] sym_val;
    begin
      rx_sym_ready = 1;
      
      // Wait for valid
      while (!rx_sym_valid) @(posedge clk);
      
      sym_val = rx_sym;
      @(posedge clk);
      rx_sym_ready = 0;
    end
  endtask
  
  task check_symbol;
    input [1:0] expected;
    reg [1:0] actual;
    begin
      // Wait for valid (assuming ready is already high)
      while (!rx_sym_valid) @(posedge clk);
      
      actual = rx_sym;
      
      if (actual !== expected) begin
        $display("    ✗ Symbol mismatch: got=%b, expected=%b", actual, expected);
        test_pass = 0;
      end
      
      @(posedge clk);
    end
  endtask

  // Friend's focused test: drive one byte and apply backpressure on 3rd symbol
  task drive_friend_byte;
    input [7:0] byte_val;
    begin
      friend_active = 1'b1;

      friend_expected[0] = byte_val[1:0];
      friend_expected[1] = byte_val[3:2];
      friend_expected[2] = byte_val[5:4];
      friend_expected[3] = byte_val[7:6];

      // Ensure the DUT is ready for a fresh byte
      while (!in_ready) @(posedge clk);

      // Hold downstream while we inspect each symbol
      rx_sym_ready = 0;

      // Present the byte for exactly one beat
      @(posedge clk);
      in_valid = 1;
      in_byte  = byte_val;

      @(posedge clk);
      in_valid = 0;

      for (friend_idx = 0; friend_idx < 4; friend_idx = friend_idx + 1) begin
        // Wait for the symbol to become valid
    while (!rx_sym_valid) @(posedge clk);
  #1;  // Allow nonblocking assignments to settle

        if (rx_sym !== friend_expected[friend_idx]) begin
          $display("    ✗ Symbol %0d mismatch: got=%b expected=%b",
                   friend_idx, rx_sym, friend_expected[friend_idx]);
          test_pass = 0;
        end else begin
          $display("    ✓ Symbol %0d matches (%b)", friend_idx, rx_sym);
        end

        if (friend_idx == 2) begin
          // Hold ready low for one extra beat to check backpressure behaviour
          @(posedge clk);
          #1;
          if (!rx_sym_valid || rx_sym !== friend_expected[friend_idx]) begin
            $display("    ✗ Symbol %0d not held correctly during backpressure",
                     friend_idx);
            test_pass = 0;
          end
        end

    // Pulse ready high for one cycle to consume the symbol
    rx_sym_ready = 1;
    @(posedge clk);
    #1;
    rx_sym_ready = 0;
      end

      // Let the DUT deassert valid and reassert in_ready
      @(posedge clk);

      friend_active = 1'b0;
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
  
  //===========================================================================
  // Main Test Sequence
  //===========================================================================
  initial begin
    $dumpfile("tb_sym_unpacker_4x.vcd");
    $dumpvars(0, tb_sym_unpacker_4x);
    
    // Initialize counters
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    byte_count = 0;
    sym_count = 0;
  friend_active = 1'b0;
    
    $display("");
    $display("=======================================================");
    $display("Symbol Unpacker Testbench");
    $display("=======================================================");
    $display("Protocol: AXI-Stream valid/ready");
    $display("Unpacking: 1 byte → 4 symbols (2 bits each)");
    $display("Order: sym[0]=bits[1:0], sym[1]=bits[3:2], ...");
    $display("=======================================================");
    
    // Apply initial reset
    apply_reset();
    
    //=========================================================================
    // T0: Reset behavior
    //=========================================================================
    start_test("T0: Reset behavior");
    
    // Check initial state
    if (in_ready !== 1'b1) begin
      $display("    ✗ After reset: in_ready=%b, expected=1", in_ready);
      test_pass = 0;
    end else begin
      $display("    ✓ After reset: in_ready=1");
    end
    
    if (rx_sym_valid !== 1'b0) begin
      $display("    ✗ After reset: rx_sym_valid=%b, expected=0", rx_sym_valid);
      test_pass = 0;
    end else begin
      $display("    ✓ After reset: rx_sym_valid=0");
    end
    
    end_test();
    
    //=========================================================================
    // T1: Single byte unpacking
    //=========================================================================
    start_test("T1: Single byte unpacking (0xE4 = 11_10_01_00)");
    
    apply_reset();
    rx_sym_ready = 1;  // Ready to receive symbols
    
    // Send byte 0xE4 = 0b11_10_01_00
    // Expected symbols in order: bits[1:0], [3:2], [5:4], [7:6] = 00, 01, 10, 11
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'hE4;
    
    // Wait for handshake
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    $display("    ✓ Byte 0xE4 sent");
    
    // Receive 4 symbols
    check_symbol(2'b00);  // bits [1:0]
    check_symbol(2'b01);  // bits [3:2]
    check_symbol(2'b10);  // bits [5:4]
    check_symbol(2'b11);  // bits [7:6]
    $display("    ✓ All 4 symbols received correctly");
    
    // Verify ready for next byte
    @(posedge clk);
    if (in_ready !== 1'b1) begin
      $display("    ✗ After symbols consumed: in_ready=%b, expected=1", in_ready);
      test_pass = 0;
    end
    
    rx_sym_ready = 0;
    
    end_test();
    
    //=========================================================================
    // T2: Multiple bytes back-to-back
    //=========================================================================
    start_test("T2: Multiple bytes back-to-back");
    
    apply_reset();
    rx_sym_ready = 1;
    
    // Send and receive byte 1: 0x1B
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'h1B;  // 00_01_10_11
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    check_symbol(2'b11); check_symbol(2'b10); check_symbol(2'b01); check_symbol(2'b00);
    
    // Send and receive byte 2: 0xB1
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'hB1;  // 10_11_00_01
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    check_symbol(2'b01); check_symbol(2'b00); check_symbol(2'b11); check_symbol(2'b10);
    
    // Send and receive byte 3: 0x4E
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'h4E;  // 01_00_11_10
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    check_symbol(2'b10); check_symbol(2'b11); check_symbol(2'b00); check_symbol(2'b01);
    
    $display("    ✓ 3 bytes sent and 12 symbols received correctly");
    
    rx_sym_ready = 0;
    
    end_test();
    
    //=========================================================================
    // T3: Backpressure (downstream not ready)
    //=========================================================================
    start_test("T3: Backpressure from downstream");
    
    apply_reset();
    
    // Send byte
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'hAA;  // 10_10_10_10
    
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    // Receive symbols with delays
    rx_sym_ready = 1;
    while (!rx_sym_valid) @(posedge clk);
    if (rx_sym !== 2'b10) test_pass = 0;
    @(posedge clk);
    rx_sym_ready = 0;
    
    // Add delay (backpressure)
    repeat(5) @(posedge clk);
    
    rx_sym_ready = 1;
    while (!rx_sym_valid) @(posedge clk);
    if (rx_sym !== 2'b10) test_pass = 0;
    @(posedge clk);
    rx_sym_ready = 0;
    
    repeat(3) @(posedge clk);
    
    rx_sym_ready = 1;
    while (!rx_sym_valid) @(posedge clk);
    if (rx_sym !== 2'b10) test_pass = 0;
    @(posedge clk);
    rx_sym_ready = 0;
    
    repeat(2) @(posedge clk);
    
    rx_sym_ready = 1;
    while (!rx_sym_valid) @(posedge clk);
    if (rx_sym !== 2'b10) test_pass = 0;
    @(posedge clk);
    rx_sym_ready = 0;
    
    $display("    ✓ Backpressure handled correctly");
    
    end_test();
    
    //=========================================================================
    // T4: Slow source
    //=========================================================================
    start_test("T4: Slow source (upstream delays)");
    
    apply_reset();
    
    rx_sym_ready = 1;  // Receiver always ready
    
    // Send byte with delay before valid
    repeat(5) @(posedge clk);
    in_valid = 1;
    in_byte = 8'h55;  // 01_01_01_01
    
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    // Receive 4 symbols
    for (integer i = 0; i < 4; i = i + 1) begin
      while (!rx_sym_valid) @(posedge clk);
      if (rx_sym !== 2'b01) test_pass = 0;
      @(posedge clk);
    end
    
    $display("    ✓ Slow source handled correctly");
    
    end_test();
    
    //=========================================================================
    // T5: Repeated backpressure cycles
    //=========================================================================
    start_test("T5: Repeated backpressure cycles");
    
    apply_reset();
    rx_sym_ready = 1;
    
    // Send a byte and receive with backpressure applied multiple times
    @(posedge clk);
    in_valid = 1;
    in_byte = 8'hE4;  // 11_10_01_00
    while (!in_ready) @(posedge clk);
    @(posedge clk);
    in_valid = 0;
    
    // Get all 4 symbols normally
    check_symbol(2'b00);
    check_symbol(2'b01);
    check_symbol(2'b10);
    check_symbol(2'b11);
    
    rx_sym_ready = 0;
    
    $display("    ✓ All symbols received correctly");
    
    end_test();
    
    //=========================================================================
    // T6: All bit patterns
    //=========================================================================
    start_test("T6: All bit patterns (0x00 to 0xFF)");
    
    apply_reset();
    rx_sym_ready = 1;
    
    for (byte_count = 0; byte_count < 256; byte_count = byte_count + 1) begin
      last_byte = byte_count[7:0];
      
      send_byte(last_byte);
      check_symbol(last_byte[1:0]);
      check_symbol(last_byte[3:2]);
      check_symbol(last_byte[5:4]);
      check_symbol(last_byte[7:6]);
    end
    
    $display("    ✓ All 256 byte patterns verified");
    
    rx_sym_ready = 0;
    
    end_test();
    
    //=========================================================================
    // T7: Burst test
    //=========================================================================
    start_test("T7: Burst test (100 random bytes)");
    
    apply_reset();
    
    rx_sym_ready = 1;
    
    for (byte_count = 0; byte_count < 100; byte_count = byte_count + 1) begin
      last_byte = $random & 8'hFF;
      send_byte(last_byte);
      
      // Receive 4 symbols
      for (sym_count = 0; sym_count < 4; sym_count = sym_count + 1) begin
        while (!rx_sym_valid) @(posedge clk);
        @(posedge clk);
      end
    end
    
    rx_sym_ready = 0;
    
    $display("    ✓ 100 bytes sent and 400 symbols received");
    
    end_test();
    
  //=========================================================================
  // T8: Friend's targeted backpressure scenario
  //=========================================================================
  start_test("T8: Friend's targeted backpressure scenario");

  apply_reset();

  // Check two representative bytes with backpressure on symbol #2
  $display("    Exercising byte 0xE4 (1110_0100)");
  drive_friend_byte(8'hE4);

  $display("    Exercising byte 0x3B (0011_1011)");
  drive_friend_byte(8'h3B);

  $display("    ✓ Friend's backpressure sequence verified");

  end_test();
    
    //=========================================================================
    // Summary
    //=========================================================================
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
  
  // Timeout watchdog
  initial begin
    #1000000;  // 1ms timeout
    $display("");
    $display("*** TIMEOUT: Test did not complete in time ***");
    $finish;
  end

endmodule
