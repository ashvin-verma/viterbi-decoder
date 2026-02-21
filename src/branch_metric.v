`default_nettype none

module branch_metric #(
    parameter Wb = 2
) (
    input  wire [1:0] rx_sym,
    input  wire [1:0] exp_sym0,
    input  wire [1:0] exp_sym1,
    output wire [Wb-1:0] bm0,
    output wire [Wb-1:0] bm1
);

    wire [1:0] bm0_raw;
    wire [1:0] bm1_raw;

    ham2 ham0 (
        .a(rx_sym),
        .b(exp_sym0),
        .c(bm0_raw)
    );

    ham2 ham1 (
        .a(rx_sym),
        .b(exp_sym1),
        .c(bm1_raw)
    );

    assign bm0 = bm0_raw[Wb-1:0];
    assign bm1 = bm1_raw[Wb-1:0];

endmodule

`default_nettype wire
