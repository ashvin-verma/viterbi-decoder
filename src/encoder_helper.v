// Simple encoder module for testbench use
// Implements (n,k,m) convolutional encoder

`timescale 1ns/1ps

module conv_encoder #(
    parameter K = 3,
    parameter G0_OCT = 8'o07,
    parameter G1_OCT = 8'o05
)(
    input clk,
    input rst,
    input bit_in,
    input bit_valid,
    output reg [1:0] sym_out,
    output reg sym_valid
);

    localparam M = K - 1;
    
    reg [M-1:0] shift_reg;
    reg [K-1:0] sr_extended;
    
    // Polynomial generators
    wire [K-1:0] g0 = G0_OCT;
    wire [K-1:0] g1 = G1_OCT;
    
    // Parity computation
    wire y0 = ^(sr_extended & g0);
    wire y1 = ^(sr_extended & g1);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 0;
            sym_out <= 0;
            sym_valid <= 0;
        end else begin
            if (bit_valid) begin
                // Shift in new bit
                shift_reg <= {shift_reg[M-2:0], bit_in};
                sr_extended <= {shift_reg[M-2:0], bit_in, bit_in};  // Extend for parity calc
                
                // Wait one cycle for shift
                sym_out <= {y0, y1};
                sym_valid <= 1;
            end else begin
                sym_valid <= 0;
            end
        end
    end
    
endmodule


// Testbench helper: Encode a bit stream
module tb_encoder_helper #(
    parameter K = 3,
    parameter G0_OCT = 8'o07,
    parameter G1_OCT = 8'o05,
    parameter MAX_BITS = 512
)();
    
    localparam M = K - 1;
    
    // Function to encode bits
    function automatic [1:0] encode_bit;
        input [M-1:0] state;
        input in_bit;
        input [K-1:0] g0;
        input [K-1:0] g1;
        reg [K-1:0] sr;
        begin
            sr = {state, in_bit};
            encode_bit[1] = ^(sr & g0);  // y0
            encode_bit[0] = ^(sr & g1);  // y1
        end
    endfunction
    
    // Task to encode a bit array
    task encode_sequence;
        input integer num_bits;
        input [MAX_BITS-1:0] bits_in;
        output [1:0] symbols_out [0:MAX_BITS-1];
        integer i;
        reg [M-1:0] state;
        reg [K-1:0] g0, g1;
        begin
            state = 0;
            g0 = G0_OCT;
            g1 = G1_OCT;
            
            for (i = 0; i < num_bits; i++) begin
                symbols_out[i] = encode_bit(state, bits_in[i], g0, g1);
                state = {state[M-2:0], bits_in[i]};
            end
        end
    endtask
    
endmodule
