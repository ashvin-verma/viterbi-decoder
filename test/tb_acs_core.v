`timescale 1ns / 1ps

//==============================================================================
// Testbench for acs_core module (Add-Compare-Select)
//==============================================================================
// Tests ACS unit with explicit test cases:
//   - Obvious cases: very different path metrics (clear winner)
//   - Edge cases: equal or near-equal path metrics
//   - Overflow cases: path metrics near maximum value
//
// ACS operation: 
//   metric0 = pm0 + bm0
//   metric1 = pm1 + bm1
//   If metric1 < metric0: select path 1 (surv=1), else path 0 (surv=0)
//==============================================================================

module tb_acs_core;

  // Parameters
  parameter Wm = 8;   // Path metric width
  parameter Wb = 2;   // Branch metric width
  
  // DUT signals
  reg [Wm-1:0] pm0, pm1;
  reg [Wb-1:0] bm0, bm1;
  wire [Wm-1:0] pm_out;
  wire surv;
  
  // Test tracking
  integer test_num;
  integer pass_count;
  integer fail_count;
  
  // Instantiate DUT
  acs_core #(
    .Wm(Wm),
    .Wb(Wb)
  ) dut (
    .pm0(pm0),
    .pm1(pm1),
    .bm0(bm0),
    .bm1(bm1),
    .pm_out(pm_out),
    .surv(surv)
  );
  
  // Test case task
  task test_case;
    input [Wm-1:0] in_pm0;
    input [Wm-1:0] in_pm1;
    input [Wb-1:0] in_bm0;
    input [Wb-1:0] in_bm1;
    input expected_surv;
    input [Wm-1:0] expected_pm;
    begin
      test_num = test_num + 1;
      
      // Apply inputs
      pm0 = in_pm0;
      pm1 = in_pm1;
      bm0 = in_bm0;
      bm1 = in_bm1;
      
      // Wait for combinational logic
      #1;
      
      // Check results
      if (surv === expected_surv && pm_out === expected_pm) begin
        pass_count = pass_count + 1;
        $display("✓ Test %0d PASS", test_num);
        $display("  pm0=%0d bm0=%0d → m0=%0d | pm1=%0d bm1=%0d → m1=%0d", 
                 in_pm0, in_bm0, in_pm0+in_bm0, in_pm1, in_bm1, in_pm1+in_bm1);
        $display("  surv=%0d pm_out=%0d (expected surv=%0d pm=%0d)", 
                 surv, pm_out, expected_surv, expected_pm);
      end else begin
        fail_count = fail_count + 1;
        $display("✗ Test %0d FAIL", test_num);
        $display("  pm0=%0d bm0=%0d → m0=%0d | pm1=%0d bm1=%0d → m1=%0d", 
                 in_pm0, in_bm0, in_pm0+in_bm0, in_pm1, in_bm1, in_pm1+in_bm1);
        $display("  Expected: surv=%0d pm=%0d", expected_surv, expected_pm);
        $display("  Got:      surv=%0d pm=%0d", surv, pm_out);
      end
      $display("");
    end
  endtask
  
  initial begin
    $dumpfile("tb_acs_core.vcd");
    $dumpvars(0, tb_acs_core);
    
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    
    $display("=======================================================");
    $display("ACS Core Testbench");
    $display("=======================================================");
    $display("Parameters: Wm=%0d, Wb=%0d", Wm, Wb);
    $display("=======================================================");
    $display("");
    
    // ===================================================================
    // OBVIOUS CASES: Clear winner (very different metrics)
    // ===================================================================
    $display("--- Obvious Cases: Clear Winner ---");
    $display("");
    
    // Test 1: Path 0 wins by large margin (pm0=10, pm1=100, bm0=0, bm1=0)
    test_case(10, 100, 0, 0, 0, 10);
    
    // Test 2: Path 1 wins by large margin (pm0=100, pm1=10, bm0=0, bm1=0)
    test_case(100, 10, 0, 0, 1, 10);
    
    // Test 3: Path 0 wins despite worse BM (pm0=20, pm1=50, bm0=3, bm1=0 → m0=23 < m1=50)
    test_case(20, 50, 3, 0, 0, 23);
    
    // Test 4: Path 1 catches up with better BM (pm0=20, pm1=22, bm0=3, bm1=0 → m1=22 < m0=23)
    test_case(20, 22, 3, 0, 1, 22);
    
    // ===================================================================
    // EDGE CASES: Equal or near-equal metrics
    // ===================================================================
    $display("--- Edge Cases: Equal/Near-Equal Metrics ---");
    $display("");
    
    // Test 5: Exactly equal metrics (m0=11 == m1=11, tie goes to path 0)
    test_case(10, 11, 1, 0, 0, 11);
    
    // Test 6: Off by 1, path 1 better (m1=10 < m0=11)
    test_case(10, 10, 1, 0, 1, 10);
    
    // Test 7: Off by 1, path 0 better (m0=10 < m1=11)
    test_case(10, 10, 0, 1, 0, 10);
    
    // Test 8: All zeros (m0=0 == m1=0)
    test_case(0, 0, 0, 0, 0, 0);
    
    // ===================================================================
    // BOUNDARY CASES: Maximum values and overflow potential
    // ===================================================================
    $display("--- Boundary Cases: Maximum Values ---");
    $display("");
    
    // Test 9: Maximum path metrics (pm0=255 > pm1=254)
    test_case(255, 254, 0, 0, 1, 254);
    
    // Test 10: Maximum branch metrics (m1=12 < m0=13)
    test_case(10, 10, 3, 2, 1, 12);
    
    // Test 11: Near overflow (m0=255 < m1=255, wraps)
    test_case(253, 252, 2, 3, 0, 255);
    
    // Test 12: Both overflow (m0=257→1, m1=256→0, path1 wins)
    test_case(254, 253, 3, 3, 1, 256 % 256);
    
    // ===================================================================
    // RANDOM-ISH MIXED CASES
    // ===================================================================
    $display("--- Mixed Cases ---");
    $display("");
    
    // Test 13: Moderate values (m1=39 < m0=43)
    test_case(42, 37, 1, 2, 1, 39);
    
    // Test 14: One path at zero (m0=2 << m1=50)
    test_case(0, 50, 2, 0, 0, 2);
    
    // Test 15: Large BM difference (m0=100 < m1=103)
    test_case(100, 100, 0, 3, 0, 100);
    
    // ===================================================================
    // Summary
    // ===================================================================
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
      $display("*** %0d TESTS FAILED ***", fail_count);
    end
    $display("=======================================================");
    
    $finish;
  end

endmodule
