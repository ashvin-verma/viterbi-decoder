module ham2 #(
) (
    input wire [1:0] a,
    input wire [1:0] b,
    output wire [1:0] c
);
    assign wire x = a ^ b;
    assign c = {1'b0, x[1]} + {1'b0, x[0]};
endmodule