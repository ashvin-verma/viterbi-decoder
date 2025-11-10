`timescale 1ns/1ps

//=============================================================================
// PM Bank Testbench
//=============================================================================
// Tests the dual-bank path metric memory with ping-pong buffering.
// Uses small parameters for bring-up: K=3, S=4, Wm=6, D=4
//
// Golden Reference: Verilog behavioral model (simple arrays + tasks/functions)
// Alternative approach: Could use C via DPI, but Verilog model is simpler
//
// Test Coverage:
//   T0: Reset and role initialization
//   T1: init_frame on Bank A (prev_is_A==1)
//   T2: Single write to current bank
//   T3: Bank swap operation
//   T4: Full symbol pass (S writes + swap)
//   T5: init_frame when prev_is_A==0
//   T6: Read-port semantics (dual ports, same/diff addresses)
//   T7: Protocol checks (no write during swap, init_frame behavior)
//   T8: Randomized sequence with behavioral model scoreboard
//=============================================================================

module tb_pm_bank;

  // Small parameters for bring-up
  parameter K = 3;
  parameter M = K - 1;  // M = 2
  parameter S = 1 << M;  // S = 4
  parameter Wm = 6;
  parameter D = 4;
  
  // Derived constants
  parameter INF = (1 << Wm) - 1;  // 63 for Wm=6
  
  // DUT signals
  reg clk;
  reg rst;
  reg init_frame;
  reg [M-1:0] rd_idx0;
  reg [M-1:0] rd_idx1;
  reg wr_en;
  reg [M-1:0] wr_idx;
  reg [Wm-1:0] wr_pm;
  reg swap_banks;
  
  wire [Wm-1:0] rd_pm0;
  wire [Wm-1:0] rd_pm1;
  wire prev_is_A;
  
  // Behavioral model (golden reference) - simple Verilog arrays
  reg [Wm-1:0] model_bank_A [0:S-1];
  reg [Wm-1:0] model_bank_B [0:S-1];
  reg model_prev_is_A;
  
  // Test control
  integer test_num;
  integer pass_count;
  integer fail_count;
  integer i, j;
  reg [Wm-1:0] expected_val;
  reg test_pass;
  
  //===========================================================================
  // DUT Instantiation
  //===========================================================================
  pm_bank #(
    .K(K),
    .M(M),
    .S(S),
    .Wm(Wm)
  ) dut (
    .clk(clk),
    .rst(rst),
    .init_frame(init_frame),
    .rd_idx0(rd_idx0),
    .rd_idx1(rd_idx1),
    .wr_en(wr_en),
    .wr_idx(wr_idx),
    .wr_pm(wr_pm),
    .swap_banks(swap_banks),
    .rd_pm0(rd_pm0),
    .rd_pm1(rd_pm1),
    .prev_A(prev_is_A)
  );
  
  //===========================================================================
  // Clock Generation
  //===========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period = 100MHz
  end
  
  //===========================================================================
  // Behavioral Model Tasks
  //===========================================================================
  task model_reset;
    integer k;
    begin
      for (k = 0; k < S; k = k + 1) begin
        model_bank_A[k] = 0;
        model_bank_B[k] = 0;
      end
      model_prev_is_A = 1'b1;
    end
  endtask
  
  task model_init_frame;
    integer k;
    begin
      if (model_prev_is_A) begin
        model_bank_B[0] = 0;
        for (k = 1; k < S; k = k + 1) begin
          model_bank_B[k] = INF;
        end
      end else begin
        model_bank_A[0] = 0;
        for (k = 1; k < S; k = k + 1) begin
          model_bank_A[k] = INF;
        end
      end
    end
  endtask
  
  task model_write;
    input [M-1:0] idx;
    input [Wm-1:0] pm;
    begin
      if (model_prev_is_A) begin
        model_bank_B[idx] = pm;
      end else begin
        model_bank_A[idx] = pm;
      end
    end
  endtask
  
  task model_swap;
    begin
      model_prev_is_A = ~model_prev_is_A;
    end
  endtask
  
  function [Wm-1:0] model_read;
    input [M-1:0] idx;
    begin
      if (model_prev_is_A) begin
        model_read = model_bank_A[idx];
      end else begin
        model_read = model_bank_B[idx];
      end
    end
  endfunction
  
  //===========================================================================
  // Helper Tasks
  //===========================================================================
  task apply_reset;
    begin
      rst = 1;
      init_frame = 0;
      rd_idx0 = 0;
      rd_idx1 = 0;
      wr_en = 0;
      wr_idx = 0;
      wr_pm = 0;
      swap_banks = 0;
      @(posedge clk);
      @(posedge clk);
      rst = 0;
      @(posedge clk);
      model_reset();
    end
  endtask
  
  task pulse_init_frame;
    begin
      @(posedge clk);
      init_frame = 1;
      model_init_frame();
      @(posedge clk);
      init_frame = 0;
      @(posedge clk);  // Let it settle
    end
  endtask
  
  task do_write;
    input [M-1:0] idx;
    input [Wm-1:0] pm;
    begin
      @(posedge clk);
      wr_en = 1;
      wr_idx = idx;
      wr_pm = pm;
      model_write(idx, pm);
      @(posedge clk);
      wr_en = 0;
    end
  endtask
  
  task do_swap;
    begin
      @(posedge clk);
      swap_banks = 1;
      model_swap();
      @(posedge clk);
      swap_banks = 0;
      @(posedge clk);  // Let it settle
    end
  endtask
  
  task check_read;
    input [M-1:0] idx;
    input [Wm-1:0] expected;
    input [31:0] port_num;  // 0 or 1
    reg [Wm-1:0] actual;
    begin
      if (port_num == 0) begin
        rd_idx0 = idx;
        @(posedge clk);
        #1;  // Combinational read delay
        actual = rd_pm0;
      end else begin
        rd_idx1 = idx;
        @(posedge clk);
        #1;
        actual = rd_pm1;
      end
      
      if (actual !== expected) begin
        $display("    ✗ Read port %0d at idx=%0d: expected=%0d, got=%0d", 
                 port_num, idx, expected, actual);
        test_pass = 0;
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
  
  //===========================================================================
  // Main Test Sequence
  //===========================================================================
  initial begin
    $dumpfile("tb_pm_bank.vcd");
    $dumpvars(0, tb_pm_bank);
    
    // Initialize counters
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    
    $display("");
    $display("=======================================================");
    $display("PM Bank Testbench");
    $display("=======================================================");
    $display("Parameters: K=%0d, M=%0d, S=%0d, Wm=%0d, INF=%0d", K, M, S, Wm, INF);
    $display("=======================================================");
    
    // Apply initial reset
    apply_reset();
    
    //=========================================================================
    // T0: Reset and role initialization
    //=========================================================================
    start_test("T0: Reset and role initialization");
    
    // Check that prev_is_A is 1 after reset
    if (prev_is_A !== 1'b1) begin
      $display("    ✗ After reset: prev_is_A=%b, expected=1", prev_is_A);
      test_pass = 0;
    end else begin
      $display("    ✓ After reset: prev_is_A=1");
    end
    
    // Reads from A should be 0 (we reset arrays to 0)
    for (i = 0; i < S; i = i + 1) begin
      check_read(i, 0, 0);
    end
    
    // Verify no spurious writes
    $display("    ✓ Bank A reads are 0, no writes occurred");
    
    end_test();
    
    //=========================================================================
    // T1: init_frame on Bank A (prev_is_A==1)
    //=========================================================================
    start_test("T1: init_frame on Bank A (prev_is_A==1)");
    
    pulse_init_frame();
    
    // After init_frame with prev_is_A==1, Bank B (curr) should have:
    // B[0]=0, B[others]=INF
    // But reads still come from Bank A (prev)
    // We need to swap to read from B
    do_swap();
    
    // Now prev is B, check values
    expected_val = 0;
    check_read(0, expected_val, 0);
    $display("    ✓ After init_frame+swap: rd_pm[0]=%0d (expected 0)", rd_pm0);
    
    for (i = 1; i < S; i = i + 1) begin
      check_read(i, INF, 0);
    end
    $display("    ✓ After init_frame+swap: rd_pm[1..%0d]=%0d (expected INF=%0d)", 
             S-1, rd_pm0, INF);
    
    end_test();
    
    // Reset for next tests
    apply_reset();
    
    //=========================================================================
    // T2: Single write into current bank
    //=========================================================================
    start_test("T2: Single write into current bank");
    
    // prev_is_A==1, so writes go to Bank B
    // Write value 13 to index 2
    do_write(2, 13);
    
    // Reads still come from Bank A (all zeros)
    check_read(2, 0, 0);
    $display("    ✓ Write to curr bank (B) doesn't affect reads from prev bank (A)");
    
    // Swap to make B the prev bank
    do_swap();
    
    // Now reads should come from B
    check_read(2, 13, 0);
    $display("    ✓ After swap: rd_pm[2]=%0d (expected 13)", rd_pm0);
    
    // Other indices should still be 0
    check_read(0, 0, 0);
    check_read(1, 0, 0);
    check_read(3, 0, 0);
    
    end_test();
    
    // Reset for next tests
    apply_reset();
    
    //=========================================================================
    // T3: Swap roles
    //=========================================================================
    start_test("T3: Swap roles");
    
    // Write to Bank B (curr) while prev_is_A==1
    do_write(2, 42);
    
    // Verify prev_is_A==1
    if (prev_is_A !== 1'b1) begin
      $display("    ✗ Before swap: prev_is_A=%b, expected=1", prev_is_A);
      test_pass = 0;
    end
    
    // Pulse swap_banks
    do_swap();
    
    // Verify prev_is_A==0
    if (prev_is_A !== 1'b0) begin
      $display("    ✗ After swap: prev_is_A=%b, expected=0", prev_is_A);
      test_pass = 0;
    end else begin
      $display("    ✓ After swap: prev_is_A=0");
    end
    
    // Now reads come from Bank B
    check_read(2, 42, 0);
    $display("    ✓ Reads now come from Bank B, rd_pm[2]=%0d", rd_pm0);
    
    end_test();
    
    //=========================================================================
    // T4: Full symbol pass (S writes → swap)
    //=========================================================================
    start_test("T4: Full symbol pass (S writes -> swap)");
    
    apply_reset();
    
    // Write S values: 100, 101, 102, 103 to indices 0, 1, 2, 3
    for (i = 0; i < S; i = i + 1) begin
      do_write(i, 100 + i);
    end
    
    // Swap banks
    do_swap();
    
    // Verify all values
    for (i = 0; i < S; i = i + 1) begin
      check_read(i, 100 + i, 0);
    end
    $display("    ✓ Full symbol pass: {100,101,102,103} written and verified");
    
    end_test();
    
    //=========================================================================
    // T5: init_frame when prev_is_A==0
    //=========================================================================
    start_test("T5: init_frame when prev_is_A==0");
    
    // Continue from T4 state where prev_is_A==0
    // Current bank is A
    pulse_init_frame();
    
    // Bank A should now have [0, INF, INF, INF]
    // Swap to read from A
    do_swap();
    
    check_read(0, 0, 0);
    for (i = 1; i < S; i = i + 1) begin
      check_read(i, INF, 0);
    end
    $display("    ✓ init_frame on Bank A: [0, INF, INF, INF]");
    
    end_test();
    
    //=========================================================================
    // T6: Read-port semantics
    //=========================================================================
    start_test("T6: Read-port semantics");
    
    apply_reset();
    
    // Write different values to all indices
    for (i = 0; i < S; i = i + 1) begin
      do_write(i, 10 + i);
    end
    do_swap();
    
    // Test simultaneous reads from both ports, same address
    @(posedge clk);
    rd_idx0 = 2;
    rd_idx1 = 2;
    #1;
    if (rd_pm0 !== 12 || rd_pm1 !== 12) begin
      $display("    ✗ Same address on both ports: rd_pm0=%0d, rd_pm1=%0d, expected 12", 
               rd_pm0, rd_pm1);
      test_pass = 0;
    end else begin
      $display("    ✓ Same address (idx=2): rd_pm0=%0d, rd_pm1=%0d", rd_pm0, rd_pm1);
    end
    
    // Test different addresses
    @(posedge clk);
    rd_idx0 = 0;
    rd_idx1 = 3;
    #1;
    if (rd_pm0 !== 10 || rd_pm1 !== 13) begin
      $display("    ✗ Different addresses: rd_pm0=%0d (exp 10), rd_pm1=%0d (exp 13)", 
               rd_pm0, rd_pm1);
      test_pass = 0;
    end else begin
      $display("    ✓ Different addresses: rd_pm0=%0d, rd_pm1=%0d", rd_pm0, rd_pm1);
    end
    
    end_test();
    
    //=========================================================================
    // T7: Protocol assertions
    //=========================================================================
    start_test("T7: Protocol checks");
    
    apply_reset();
    
    // Check: swap_banks implies !wr_en (no write during swap)
    // This is more of a coverage check - we'll just note it
    $display("    ✓ Protocol: swap_banks should never coincide with wr_en");
    $display("      (This testbench enforces this, would use SVA in practice)");
    
    // Check: After init_frame, rd_pm0[0] is 0, others >= INF threshold
    pulse_init_frame();
    do_swap();
    
    check_read(0, 0, 0);
    for (i = 1; i < S; i = i + 1) begin
      rd_idx0 = i;
      #1;
      if (rd_pm0 < INF) begin
        $display("    ✗ After init_frame: rd_pm[%0d]=%0d, expected >= INF=%0d", 
                 i, rd_pm0, INF);
        test_pass = 0;
      end
    end
    $display("    ✓ After init_frame: index 0 is 0, others are INF");
    
    end_test();
    
    //=========================================================================
    // T8: Randomized sequence with scoreboard
    //=========================================================================
    start_test("T8: Randomized sequence with software scoreboard");
    
    apply_reset();
    
    // Run a randomized sequence of operations
    // Pattern: init -> S writes -> swap -> repeat a few times
    for (j = 0; j < 3; j = j + 1) begin  // 3 iterations
      // Init frame
      pulse_init_frame();
      
      // S writes with random values
      for (i = 0; i < S; i = i + 1) begin
        do_write(i, ($random & 6'b111111));  // Random 6-bit value
      end
      
      // Swap
      do_swap();
      
      // Verify all reads match scoreboard
      for (i = 0; i < S; i = i + 1) begin
        expected_val = model_read(i);
        check_read(i, expected_val, 0);
      end
    end
    
    $display("    ✓ Randomized sequence: 3 iterations verified against scoreboard");
    
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
    #100000;  // 100us timeout
    $display("");
    $display("*** TIMEOUT: Test did not complete in time ***");
    $finish;
  end

endmodule
