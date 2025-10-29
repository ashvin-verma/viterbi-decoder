module ham2 #(
) (
    input  wire [1:0] a,
    output wire [1:0] b
);
    assign wire x[1:0] = a[1:0] ^ b[1:0];
endmodule