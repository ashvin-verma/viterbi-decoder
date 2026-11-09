`timescale 1ns/1ps
`default_nettype none
// System-level sim wrapper: AXI frame buffer + TT decoder (with debug taps)
// + BER tester, wired exactly as in top_ps7.v minus the PS7.
module tb_fb_system #(
    parameter K = 7, parameter D = 42, parameter G0 = 121, parameter G1 = 91,
    parameter LANES = 2
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [17:0] awaddr, input wire awvalid, output wire awready,
    input  wire [31:0] wdata,  input wire [3:0] wstrb, input wire wvalid, output wire wready,
    output wire [1:0]  bresp,  output wire bvalid, input wire bready,
    input  wire [17:0] araddr, input wire arvalid, output wire arready,
    output wire [31:0] rdata,  output wire [1:0] rresp, output wire rvalid, input wire rready
);
    localparam [3:0] HK = K;
    localparam [7:0] HD = D;
    localparam [8:0] HG0 = G0;
    localparam [8:0] HG1 = G1;

    wire [7:0] ui, uio_i, uo, uio_o, uio_oe;
    wire tt_rst_n;
    wire dbg_sweep, dbg_surv, dbg_commit;
    wire [K-2:0] dbg_idx, dbg_best;
    wire [7:0] dbg_pm;
    wire [7:0] dbg_idx8 = dbg_idx;
    wire [7:0] dbg_best8 = dbg_best;
    wire ber_wr_en; wire [4:0] ber_wr_addr, ber_rd_addr; wire [31:0] ber_wr_data, ber_rd_data;
    wire l0, l1, l2;

    viterbi_axi_framebuf #(.HW_CONFIG({2'b01, HG1, HG0, HD, HK})) u_fb (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .tt_ui_in(ui), .tt_uio_in(uio_i), .tt_uo_out(uo), .tt_uio_out(uio_o), .tt_rst_n(tt_rst_n),
        .dbg_sweep(dbg_sweep), .dbg_idx(dbg_idx8), .dbg_pm(dbg_pm), .dbg_surv(dbg_surv),
        .dbg_commit(dbg_commit), .dbg_best(dbg_best8),
        .ber_wr_en(ber_wr_en), .ber_wr_addr(ber_wr_addr), .ber_wr_data(ber_wr_data),
        .ber_rd_addr(ber_rd_addr), .ber_rd_data(ber_rd_data),
        .led_mode(l0), .led_busy(l1), .led_done(l2));

    tt_um_ashvin_viterbi #(.K(K), .D_TB(D), .RATE(2), .G0_OCT(G0), .G1_OCT(G1), .G2_OCT(0)) u_tt (
        .ui_in(ui), .uo_out(uo), .uio_in(uio_i), .uio_out(uio_o), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(tt_rst_n),
        .dbg_sweep(dbg_sweep), .dbg_idx(dbg_idx), .dbg_pm(dbg_pm),
        .dbg_surv(dbg_surv), .dbg_commit(dbg_commit), .dbg_best(dbg_best));

    ber_tester #(.K(K), .D(D), .G0_OCT(G0), .G1_OCT(G1), .LANES(LANES)) u_ber (
        .clk(clk), .rst_n(resetn), .wr_en(ber_wr_en), .wr_addr(ber_wr_addr), .wr_data(ber_wr_data),
        .rd_addr(ber_rd_addr), .rd_data(ber_rd_data));
endmodule
`default_nettype wire
