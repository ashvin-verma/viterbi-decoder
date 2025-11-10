`timescale 1ns/1ps

module tb_debug_unpack;
  reg clk=0, rst=1;
  reg in_valid=0, rx_sym_ready=0;
  reg [7:0] in_byte=0;
  wire in_ready;
  wire rx_sym_valid;
  wire [1:0] rx_sym;
  
  sym_unpacker_4x dut(.*);
  
  always #5 clk=~clk;
  
  initial begin
    repeat(3) @(posedge clk); 
    rst=0;
    @(posedge clk);
    
    $display("T=%0t: Initial state: in_ready=%b", $time, in_ready);
    
    // Wait until ready
    while (!in_ready) @(posedge clk);
    $display("T=%0t: Ready detected", $time);
    
    // Send 0xE4 - set signals BEFORE the clock edge
    @(posedge clk);
    in_byte = 8'hE4;
    in_valid = 1;
    rx_sym_ready = 0;
    $display("T=%0t: Set in_valid=1, in_byte=0xE4", $time);
    
    // On next clock, handshake should occur
    @(posedge clk);
    $display("T=%0t: After handshake clk: in_ready=%b, rx_sym_valid=%b, rx_sym=%b", 
             $time, in_ready, rx_sym_valid, rx_sym);
    in_valid = 0;
    
    // Check if first symbol is valid
    @(posedge clk);
    $display("T=%0t: Sym0 should be valid: valid=%b, sym=%b (expect 00)", 
             $time, rx_sym_valid, rx_sym);
    
    $finish;
  end
endmodule
