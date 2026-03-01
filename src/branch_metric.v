`default_nettype none

module branch_metric #(
    parameter int Wb = 2,
    parameter int RATE = 2
) (
    input  wire [RATE-1:0] rx_sym,
    input  wire [RATE-1:0] exp_sym0,
    input  wire [RATE-1:0] exp_sym1,
    output wire [Wb-1:0] bm0,
    output wire [Wb-1:0] bm1
);

    wire [1:0] bm0_raw;
    wire [1:0] bm1_raw;

    generate
        if (RATE == 3) begin : gen_ham3
            ham3 ham0 (
                .a(rx_sym),
                .b(exp_sym0),
                .c(bm0_raw)
            );

            ham3 ham1 (
                .a(rx_sym),
                .b(exp_sym1),
                .c(bm1_raw)
            );
        end else begin : gen_ham2
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
        end
    endgenerate

    assign bm0 = bm0_raw[Wb-1:0];
    assign bm1 = bm1_raw[Wb-1:0];

endmodule

`default_nettype wire
