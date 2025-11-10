// tb_conv_encoder_k9.v
// Test K=9 encoder configuration

`timescale 1ns/1ps

module tb_conv_encoder_k9;

  // K=9 canonical (753,561)_8
  parameter K_TB = 9;
  parameter G0 = 16'o753;
  parameter G1 = 16'o561;
  
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
  
  // Golden model
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
  
  reg [K-1:0] G0_MASK;
  reg [K-1:0] G1_MASK;
  reg [M-1:0] g_state;
  
  function [1:0] golden_sym;
    input bit_in;
    input [M-1:0] st;
    reg [K-1:0] reg_vec;
    begin
      reg_vec = {bit_in, st};
      golden_sym[1] = ^(reg_vec & G0_MASK);
      golden_sym[0] = ^(reg_vec & G1_MASK);
    end
  endfunction
  
  function [M-1:0] golden_next_state;
    input bit_in;
    input [M-1:0] st;
    begin
      golden_next_state = {bit_in, st[M-1:1]};
    end
  endfunction
  
  task drive_and_check;
    input b;
    reg [1:0] exp;
    begin
      @(negedge clk);
      in_bit = b;
      in_valid = 1'b1;
      exp = golden_sym(b, g_state);
      @(posedge clk);
      #1;
      if (!out_valid || out_sym !== exp) begin
        $display("ERROR: out_sym=%b exp=%b (state=%b, in=%0d)", out_sym, exp, g_state, b);
        $finish;
      end
      g_state = golden_next_state(b, g_state);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask
  
  integer i;
  reg [31:0] seed_val;
  reg b;
  
  initial begin
    G0_MASK = oct2mask(G0);
    G1_MASK = oct2mask(G1);
    
    $display("\n=== Testing K=%0d, G0=%0o, G1=%0o ===", K, G0, G1);
    $display("G0_MASK=%b, G1_MASK=%b\n", G0_MASK, G1_MASK);
    
    // Reset
    seed_load = 0;
    seed_value = {M{1'b0}};
    in_valid = 0;
    in_bit = 0;
    repeat (3) @(negedge clk);
    rst = 0;
    g_state = {M{1'b0}};
    @(negedge clk);
    
    // Quick tests
    $display("Test: All zeros (32 bits)");
    for (i = 0; i < 32; i = i + 1) drive_and_check(1'b0);
    $display("  PASS\n");
    
    $display("Test: All ones (32 bits)");
    for (i = 0; i < 32; i = i + 1) drive_and_check(1'b1);
    $display("  PASS\n");
    
    $display("Test: Random (100 bits)");
    seed_val = 32'hdeadbeef;
    for (i = 0; i < 100; i = i + 1) begin
      b = $random(seed_val) & 1;
      drive_and_check(b);
    end
    $display("  PASS\n");
    
    $display("=== All tests PASSED for K=%0d ===\n", K);
    $finish;
  end
  
  initial begin
    #100000;
    $display("ERROR: Timeout!");
    $finish;
  end

endmodule
