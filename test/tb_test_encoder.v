// Test the encoder task itself
`timescale 1ns/1ps

module tb_test_encoder();
    
    parameter K = 3;
    parameter M = K - 1;
    parameter G0_OCT = 8'o07;  // 111 binary
    parameter G1_OCT = 8'o05;  // 101 binary
    
    task encode_bit(
        input logic in_bit,
        input logic [M-1:0] state_in,
        output logic [M-1:0] state_out,
        output logic y0,
        output logic y1
    );
        logic [K-1:0] sr;
        begin
            sr = {state_in, in_bit};
            y0 = ^(sr & G0_OCT[K-1:0]);
            y1 = ^(sr & G1_OCT[K-1:0]);
            state_out = sr[K-1:1];
        end
    endtask
    
    logic [M-1:0] state;
    logic y0, y1;
    integer i;
    logic [0:7] test_bits;
    
    initial begin
        $display("Encoder Test");
        $display("============");
        $display("G0 = %03b", G0_OCT[2:0]);
        $display("G1 = %03b", G1_OCT[2:0]);
        $display("");
        
        // Test pattern: alternating
        test_bits = 8'b01010101;
        
        $display("Encoding pattern: %b", test_bits);
        state = 0;
        for (i = 0; i < 8; i = i + 1) begin
            encode_bit(test_bits[i], state, state, y0, y1);
            $display("Bit[%0d]=%b: state=%02b -> symbols %b%b", i, test_bits[i], state, y0, y1);
        end
        
        $display("");
        $display("Encoding all 1s:");
        state = 0;
        for (i = 0; i < 8; i = i + 1) begin
            encode_bit(1'b1, state, state, y0, y1);
            $display("Bit[%0d]=%b: state=%02b -> symbols %b%b", i, 1'b1, state, y0, y1);
        end
        
        $display("");
        $display("Encoding all 0s:");
        state = 0;
        for (i = 0; i < 8; i = i + 1) begin
            encode_bit(1'b0, state, state, y0, y1);
            $display("Bit[%0d]=%b: state=%02b -> symbols %b%b", i, 1'b0, state, y0, y1);
        end
        
        $finish;
    end
    
endmodule
