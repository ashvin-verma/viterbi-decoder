// tb_conv_encoder_1_2.v
// Self-checking testbench for conv_encoder_1_2 (parameterizable K, G0, G1).
// Covers: reset, noiseless streams, random, PRBS7, seed_load (tail-biting seed),
// input gaps (in_valid=0), and long random with scoreboard.

`timescale 1ns/1ps

module tb_conv_encoder_1_2;

  // ======== SELECT CONFIG ========
  // K=3 canonical (7,5)_8
  parameter K_TB = 3;
  parameter G0 = 8'o07;
  parameter G1 = 8'o05;
  
  // // K=4 canonical (17,13)_8
  // parameter K_TB = 4;
  // parameter G0 = 8'o17;
  // parameter G1 = 8'o13;
  // =================================
  
  localparam K = K_TB;
  localparam M = K - 1;
  
  // DUT I/O
  reg clk = 0;
  reg rst = 1;
  reg seed_load;
  reg [M-1:0] seed_value;
  reg in_valid;
  reg in_bit;
  wire out_valid;
  wire [1:0] out_sym;
  
  // Instantiate DUT
  conv_encoder_1_2 #(
    .K(K),
    .G0_OCT(G0),
    .G1_OCT(G1)
  ) dut (
    .clk(clk),
    .rst(rst),
    .seed_load(seed_load),
    .seed_value(seed_value),
    .in_valid(in_valid),
    .in_bit(in_bit),
    .out_valid(out_valid),
    .out_sym(out_sym)
  );
  
  // Clock generation
  always #5 clk = ~clk;
  
  // ---------- Golden Model Helpers ----------
  // Octal to mask conversion (K bits), LSB=D^0=current input
  function [K-1:0] oct2mask;
    input integer oct;
    integer pos, v, digit;
    begin
      oct2mask = {K{1'b0}};
      pos = 0;
      v = oct;
      while (v != 0) begin
        digit = v & 7;
        if (((digit & 1) != 0) && (pos+0 < K)) oct2mask[pos+0] = 1'b1;
        if (((digit & 2) != 0) && (pos+1 < K)) oct2mask[pos+1] = 1'b1;
        if (((digit & 4) != 0) && (pos+2 < K)) oct2mask[pos+2] = 1'b1;
        v = v >> 3;
        pos = pos + 3;
      end
    end
  endfunction
  
  // Generator polynomial masks
  reg [K-1:0] G0_MASK;
  reg [K-1:0] G1_MASK;
  
  // Golden state
  reg [M-1:0] g_state;
  
  // Compute golden c0,c1 for given input bit and current g_state (before update)
  function [1:0] golden_sym;
    input bit_in;
    input [M-1:0] st;
    reg [K-1:0] reg_vec;
    begin
      reg_vec = {bit_in, st};  // width K
      golden_sym[1] = ^(reg_vec & G0_MASK);  // c0 at [1]
      golden_sym[0] = ^(reg_vec & G1_MASK);  // c1 at [0]
    end
  endfunction
  
  // Update golden state (same as DUT): next = {in_bit, state[M-1:1]}
  function [M-1:0] golden_next_state;
    input bit_in;
    input [M-1:0] st;
    begin
      golden_next_state = {bit_in, st[M-1:1]};
    end
  endfunction
  
  // ---------- TB Utilities ----------
  task apply_reset;
    begin
      seed_load = 0;
      seed_value = {M{1'b0}};
      in_valid = 0;
      in_bit = 0;
      repeat (3) @(negedge clk);
      rst = 0;
      g_state = {M{1'b0}};
      @(negedge clk);
    end
  endtask
  
  // Drive one bit with in_valid=1, sample on posedge, compare to golden
  task drive_and_check;
    input b;
    reg [1:0] exp;
    begin
      // Present inputs before rising edge
      @(negedge clk);
      in_bit = b;
      in_valid = 1'b1;
      
      // Golden compute BEFORE state update
      exp = golden_sym(b, g_state);
      
      // On rising edge, DUT emits out_sym and updates state
      @(posedge clk);
      #1;
      
      if (!out_valid) begin
        $display("ERROR: out_valid deasserted on in_valid=1");
        $finish;
      end
      
      if (out_sym !== exp) begin
        $display("ERROR: Mismatch: out_sym=%b exp=%b (g_state=%b, in=%0d)", 
                 out_sym, exp, g_state, b);
        $finish;
      end
      
      // Update golden state
      g_state = golden_next_state(b, g_state);
      
      // Deassert in_valid next cycle
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask
  
  // Insert an idle (in_valid=0) cycle and ensure no output
  task idle_cycle;
    begin
      @(negedge clk);
      in_valid = 1'b0;
      @(posedge clk);
      #1;
      if (out_valid) begin
        $display("ERROR: out_valid should be 0 on idle cycle");
        $finish;
      end
    end
  endtask
  
  // Load seed_value (tail-biting/seed test)
  task load_seed;
    input [M-1:0] s;
    begin
      @(negedge clk);
      seed_value = s;
      seed_load = 1'b1;
      @(posedge clk);
      #1;
      seed_load = 1'b0;
      g_state = s;  // mirror in golden
    end
  endtask
  
  // Generate PRBS7 bit
  reg [6:0] prbs7_lfsr;
  function prbs7;
    input dummy;  // Verilog-2001 requires at least one input
    reg fb;
    begin
      fb = prbs7_lfsr[6] ^ prbs7_lfsr[5];  // x^7 + x^6 + 1
      prbs7 = prbs7_lfsr[0];
      prbs7_lfsr = {fb, prbs7_lfsr[6:1]};
    end
  endfunction
  
  // Test counters
  integer test_count;
  integer i, j;
  reg [31:0] seed_val;
  reg [M-1:0] s;
  reg b;
  
  // ---------- Tests ----------
  initial begin
    // Initialize generator masks
    G0_MASK = oct2mask(G0);
    G1_MASK = oct2mask(G1);
    
    $display("\n=== TB start: K=%0d, G0=%0o, G1=%0o ===", K, G0, G1);
    $display("G0_MASK=%b, G1_MASK=%b\n", G0_MASK, G1_MASK);
    
    test_count = 0;
    apply_reset();
    
    // T0: single 0 then single 1
    test_count = test_count + 1;
    $display("[Test %0d] Single 0 then single 1", test_count);
    drive_and_check(1'b0);
    drive_and_check(1'b1);
    idle_cycle();
    $display("  PASS\n");
    
    // T1: all-zeros stream (length 16)
    test_count = test_count + 1;
    $display("[Test %0d] All-zeros stream (16 bits)", test_count);
    for (i = 0; i < 16; i = i + 1) begin
      drive_and_check(1'b0);
    end
    idle_cycle();
    $display("  PASS\n");
    
    // T2: all-ones stream (length 16)
    test_count = test_count + 1;
    $display("[Test %0d] All-ones stream (16 bits)", test_count);
    for (i = 0; i < 16; i = i + 1) begin
      drive_and_check(1'b1);
    end
    idle_cycle();
    $display("  PASS\n");
    
    // T3: alternating 0101… (length 32)
    test_count = test_count + 1;
    $display("[Test %0d] Alternating pattern (32 bits)", test_count);
    for (i = 0; i < 32; i = i + 1) begin
      drive_and_check(i[0]);
    end
    idle_cycle();
    $display("  PASS\n");
    
    // T4: Random with input gaps
    test_count = test_count + 1;
    $display("[Test %0d] Random with input gaps (64 bits)", test_count);
    seed_val = 32'hc0ffee12;
    for (i = 0; i < 64; i = i + 1) begin
      b = $random(seed_val) & 1;
      drive_and_check(b);
      if (($random(seed_val) & 3) == 0) begin
        idle_cycle();  // ~25% idle
      end
    end
    $display("  PASS\n");
    
    // T5: PRBS7 (length 128)
    test_count = test_count + 1;
    $display("[Test %0d] PRBS7 sequence (128 bits)", test_count);
    prbs7_lfsr = 7'h5A;  // non-zero seed
    for (i = 0; i < 128; i = i + 1) begin
      b = prbs7(1'b0);  // Pass dummy argument
      drive_and_check(b);
    end
    idle_cycle();
    $display("  PASS\n");
    
    // T6: seed_load behavior (tail-biting seed / arbitrary preload)
    if (M > 0) begin
      test_count = test_count + 1;
      $display("[Test %0d] Seed load (tail-biting)", test_count);
      s = {M{1'b0}};
      // Choose a seed with alternating bits
      for (j = 0; j < M; j = j + 1) begin
        s[j] = j[0];
      end
      load_seed(s);
      
      // After seeding, run 32 random bits and check
      for (i = 0; i < 32; i = i + 1) begin
        b = $random(seed_val) & 1;
        drive_and_check(b);
      end
      idle_cycle();
      $display("  PASS\n");
    end
    
    // T7: Long random burn-in (1000 bits), with occasional idles
    test_count = test_count + 1;
    $display("[Test %0d] Long random burn-in (1000 bits with gaps)", test_count);
    for (i = 0; i < 1000; i = i + 1) begin
      b = $random(seed_val) & 1;
      drive_and_check(b);
      if (($random(seed_val) % 10) == 0) begin
        idle_cycle();  // ~10% idle
      end
    end
    $display("  PASS\n");
    
    $display("=== All %0d tests PASSED for K=%0d, G0=%0o, G1=%0o ===\n", 
             test_count, K, G0, G1);
    $finish;
  end
  
  // Timeout watchdog
  initial begin
    #1000000;  // 1ms timeout
    $display("\nERROR: Testbench timeout!");
    $finish;
  end
  
  // Optional: Waveform dumping
  initial begin
    $dumpfile("tb_conv_encoder_new.vcd");
    $dumpvars(0, tb_conv_encoder_1_2);
  end

endmodule
