module acs_core #(
    parameter int Wm = 8,
    parameter int Wb = 2
) (
    input  logic [Wm-1:0] pm0,
    input  logic [Wm-1:0] pm1,
    input  logic [Wb-1:0] bm0,
    input  logic [Wb-1:0] bm1,
    output logic [Wm-1:0] pm_out,
    output logic          surv
);

function automatic [Wm-1:0] sat_add(input logic [Wm-1:0] a, input logic [Wb-1:0] b);
    logic [Wm:0] sum;
    begin
        sum    = {1'b0, a} + {{(Wm-Wb+1){1'b0}}, b};
        sat_add = sum[Wm] ? {Wm{1'b1}} : sum[Wm-1:0];
    end
endfunction

logic [Wm-1:0] metric0;
logic [Wm-1:0] metric1;

assign metric0 = sat_add(pm0, bm0);
assign metric1 = sat_add(pm1, bm1);

// Tie-break: p0 wins on ties (i.e., choose metric1 only if strictly smaller)
assign surv    = (metric1 < metric0);  // 0=choose pm0/bm0, 1=choose pm1/bm1
assign pm_out  = surv ? metric1 : metric0;

endmodule