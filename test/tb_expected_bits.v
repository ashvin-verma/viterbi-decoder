`timescale 1ns / 1ps

//==============================================================================
// Testbench for expected_bits module
//==============================================================================
// Exhaustively tests all S×2 cases (S states × 2 input bits) against C golden model
// Convention: bit 0 = newest input, higher bits = older state bits
// Generator polynomials use direct octal notation (tap i -> bit i)
//
// Test flow:
//   1. C model (viterbi_golden.c -DTEST_VECTORS) generates test vectors
//   2. Testbench reads vectors from test_vectors_expected_bits.txt
//   3. Applies inputs to DUT and compares outputs
//   4. Reports first mismatch with detailed binary state info
//
// Usage: make -f Makefile.expected_bits test
//==============================================================================

module tb_expected_bits;

  // Parameters matching the expected_bits module
  parameter K = 5;
  parameter M = K - 1;
  parameter G0_OCT = 'o23;
  parameter G1_OCT = 'o35;
  
  // Number of test cases
  localparam S = 1 << M;
  localparam NUM_TESTS = S * 2;  // All states × 2 input bits
  
  // Testbench signals
  reg [M-1:0] pred;
  reg b;
  wire [1:0] dut_output;
  
  // Test tracking
  integer test_file;
  integer total_tests;
  integer pass_count;
  integer fail_count;
  integer scan_result;
  reg first_error_printed;
  
  // Test vector variables
  reg [M-1:0] tv_pred;
  reg tv_b;
  reg [1:0] tv_expected;
  
  // Instantiate the DUT (Device Under Test)
  expected_bits #(
    .K(K),
    .M(M),
    .G0_OCT(G0_OCT),
    .G1_OCT(G1_OCT)
  ) dut (
    .pred(pred),
    .b(b),
    .expected(dut_output)
  );
  
  initial begin
    // Dump waveform for debugging
    $dumpfile("tb_expected_bits.vcd");
    $dumpvars(0, tb_expected_bits);
    
    // Initialize counters
    pass_count = 0;
    fail_count = 0;
    first_error_printed = 0;
    
    // Print header
    $display("=======================================================");
    $display("Expected Bits Testbench - Test Vector Based");
    $display("=======================================================");
    $display("Parameters: K=%0d, M=%0d", K, M);
    $display("G0_OCT=%o (0x%h), G1_OCT=%o (0x%h)", G0_OCT, G0_OCT, G1_OCT, G1_OCT);
    $display("=======================================================");
    $display("");
    
    // Open test vectors file
    test_file = $fopen("test_vectors_expected_bits.txt", "r");
    if (test_file == 0) begin
      $display("ERROR: Cannot open test_vectors_expected_bits.txt");
      $display("Run: ./test_expected_bits --vectors > test_vectors_expected_bits.txt");
      $finish;
    end
    
    $display("Reading test vectors from file...");
    $display("Expecting %0d test vectors", NUM_TESTS);
    $display("");
    
    // Process exactly NUM_TESTS vectors (avoids infinite loop)
    for (total_tests = 0; total_tests < NUM_TESTS; total_tests = total_tests + 1) begin
      // Read: pred(hex) b expected(hex)
      scan_result = $fscanf(test_file, "%h %d %h", tv_pred, tv_b, tv_expected);
      
      if (scan_result != 3) begin
        $display("ERROR: Failed to read test vector #%0d (got %0d fields)", total_tests + 1, scan_result);
        $display("Expected format: pred(hex) b(dec) expected(hex)");
        $fclose(test_file);
        $finish;
      end
      
      // Apply inputs to DUT
      pred = tv_pred;
      b = tv_b;
      
      // Allow one delta cycle for combinational logic to propagate
      #1;
      
      // Check result
      if (dut_output === tv_expected) begin
        pass_count = pass_count + 1;
      end else begin
        // Print first mismatch with detailed information
        if (first_error_printed == 0) begin
          $display("*** FIRST MISMATCH DETECTED ***");
          $display("  Test #%0d", total_tests + 1);
          $display("  pred = %0d (0x%h, 0b%b)", pred, pred, pred);
          $display("  b    = %0d", b);
          $display("  Expected (from file): 0b%b%b (0x%h)", 
                   tv_expected[1], tv_expected[0], tv_expected);
          $display("  Got (DUT):            0b%b%b (0x%h)",
                   dut_output[1], dut_output[0], dut_output);
          $display("  Register vector: {b=%b, pred=0b%b} = 0b%b",
                   b, pred, {b, pred});
          $display("");
          first_error_printed = 1;
        end
        fail_count = fail_count + 1;
      end
    end
    
    $fclose(test_file);
    
    // Print summary
    $display("=======================================================");
    $display("Test Summary");
    $display("=======================================================");
    $display("Total tests:  %0d", NUM_TESTS);
    $display("Passed:       %0d", pass_count);
    $display("Failed:       %0d", fail_count);
    
    if (fail_count == 0) begin
      $display("");
      $display("*** ALL TESTS PASSED! ***");
      $display("");
    end else begin
      $display("");
      $display("*** %0d TESTS FAILED ***", fail_count);
      $display("");
    end
    $display("=======================================================");
    
    $finish;
  end

endmodule
