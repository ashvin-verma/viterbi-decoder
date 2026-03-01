module ham3 (
    input wire [2:0] a,
    input wire [2:0] b,
    output wire [1:0] c
);
    wire [2:0] x;
    assign x = a ^ b;
    assign c = {1'b0, x[2]} + {1'b0, x[1]} + {1'b0, x[0]};  // popcount, max=3, fits in 2 bits
endmodule
