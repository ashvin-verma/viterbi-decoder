module acs_core #(
    parameter Wm = 8,
    parameter Wb = 2
) (
    input  wire [Wm-1:0] pm0,
    input  wire [Wm-1:0] pm1,
    input  wire [Wb-1:0] bm0,
    input  wire [Wb-1:0] bm1,
    output wire [Wm-1:0] pm_out,
    output wire           surv
);

wire [Wm-1:0] metric0;
wire [Wm-1:0] metric1;

assign metric0 = pm0 + {{(Wm-Wb){1'b0}}, bm0};
assign metric1 = pm1 + {{(Wm-Wb){1'b0}}, bm1};

assign surv    = (metric1 < metric0);
assign pm_out  = surv ? metric1 : metric0;

endmodule
