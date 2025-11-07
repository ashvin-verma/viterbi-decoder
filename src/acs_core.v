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

logic [Wm-1:0] metric0;
logic [Wm-1:0] metric1;

assign metric0 = pm0 + {{(Wm-1-Wb){1'b0}}, bm0};
assign metric1 = pm1 + {{(Wm-1-Wb){1'b0}}, bm1};

assign surv    = (metric1 < metric0);
assign pm_out  = surv ? metric1[Wm-1:0] : metric0[Wm-1:0];

endmodule