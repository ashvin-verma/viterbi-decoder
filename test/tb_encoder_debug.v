// Debug encoder task parameters
`timescale 1ns/1ps

module tb_encoder_debug();
    
    parameter K = 3;
    parameter M = K - 1;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    
    task encode_bit(
        input logic in_bit,
        input logic [M-1:0] state_in,
        output logic [M-1:0] state_out,
        output logic y0,
        output logic y1
    );
        logic [K-1:0] sr;
        begin
            $display("  encode_bit: in_bit=%b, state_in=%02b", in_bit, state_in);
            sr = {state_in, in_bit};
            $display("  sr = %03b", sr);
            y0 = ^(sr & G0_OCT[K-1:0]);
            y1 = ^(sr & G1_OCT[K-1:0]);
            $display("  y0=%b (sr & G0 = %03b), y1=%b (sr & G1 = %03b)", 
                    y0, sr & G0_OCT[K-1:0], y1, sr & G1_OCT[K-1:0]);
            state_out = sr[K-2:0];  // Shift: take lower K-1 bits
            $display("  state_out = sr[%0d:0] = %02b", K-2, state_out);
        end
    endtask
    
    logic [M-1:0] state;
    logic y0, y1;
    
    initial begin
        $display("Testing encoder with explicit state management");
        $display("==============================================");
        
        state = 2'b00;
        $display("\n1. Encode bit 1:");
        encode_bit(1'b1, state, state, y0, y1);
        $display("After call: state=%02b, y0=%b, y1=%b\n", state, y0, y1);
        
        $display("2. Encode bit 1 again:");
        encode_bit(1'b1, state, state, y0, y1);
        $display("After call: state=%02b, y0=%b, y1=%b\n", state, y0, y1);
        
        $display("3. Encode bit 0:");
        encode_bit(1'b0, state, state, y0, y1);
        $display("After call: state=%02b, y0=%b, y1=%b\n", state, y0, y1);
        
        $finish;
    end
    
endmodule
