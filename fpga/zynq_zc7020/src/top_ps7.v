// =============================================================================
// top_ps7.v -- Top-level wrapper: PS7 block design + AXI frame buffer +
//              TT Viterbi decoder
//
// Wraps the Vivado block design (PS7 + AXI interconnect) and connects
// an AXI-Lite frame buffer peripheral to the TT Viterbi module.
// Host writes full encoded frames via XSDB, reads decoded output.
//
// LEDs:
//   LD0 = mode (frame buffer driving mode 1)
//   LD1 = busy (frame processing in progress)
//   LD2 = done (decoded output ready)
//   LD3 = heartbeat (~1 Hz)
// =============================================================================

`default_nettype none

`ifndef K_SEL
  `define K_SEL 7
`endif
`ifndef D_TB_SEL
  `define D_TB_SEL 42
`endif
`ifndef G0_SEL
  `define G0_SEL 121    // 0o171
`endif
`ifndef G1_SEL
  `define G1_SEL 91     // 0o133
`endif

module top_ps7 (
    // =====================================================================
    // PS7 DDR interface (directly from block design wrapper)
    // =====================================================================
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,

    // =====================================================================
    // PS7 Fixed I/O (MIO, PS_CLK, PS_POR, PS_SRST)
    // =====================================================================
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // =====================================================================
    // LEDs
    // =====================================================================
    output wire        led0,
    output wire        led1,
    output wire        led2,
    output wire        led3
);

    // =========================================================================
    // Block design wrapper signals (AXI-Lite exported from block design)
    // =========================================================================
    wire        pl_clk;
    wire        pl_resetn;

    // AXI-Lite signals from block design (address is 32 bits from interconnect)
    wire [31:0] axi_awaddr;
    wire [2:0]  axi_awprot;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [31:0] axi_araddr;
    wire [2:0]  axi_arprot;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    // =========================================================================
    // Block design wrapper instantiation
    // =========================================================================
    system_wrapper u_system (
        // DDR
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),
        // Fixed I/O
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
        // PL clock and reset
        .pl_clk            (pl_clk),
        .pl_resetn         (pl_resetn),
        // AXI-Lite slave interface (exported from block design)
        .M_AXI_awaddr      (axi_awaddr),
        .M_AXI_awprot      (axi_awprot),
        .M_AXI_awvalid     (axi_awvalid),
        .M_AXI_awready     (axi_awready),
        .M_AXI_wdata       (axi_wdata),
        .M_AXI_wstrb       (axi_wstrb),
        .M_AXI_wvalid      (axi_wvalid),
        .M_AXI_wready      (axi_wready),
        .M_AXI_bresp       (axi_bresp),
        .M_AXI_bvalid      (axi_bvalid),
        .M_AXI_bready      (axi_bready),
        .M_AXI_araddr      (axi_araddr),
        .M_AXI_arprot      (axi_arprot),
        .M_AXI_arvalid     (axi_arvalid),
        .M_AXI_arready     (axi_arready),
        .M_AXI_rdata       (axi_rdata),
        .M_AXI_rresp       (axi_rresp),
        .M_AXI_rvalid      (axi_rvalid),
        .M_AXI_rready      (axi_rready)
    );

    // =========================================================================
    // TT module signals
    // =========================================================================
    wire [7:0] tt_ui_in;
    wire [7:0] tt_uio_in;
    wire [7:0] tt_uo_out;
    wire [7:0] tt_uio_out;
    wire [7:0] tt_uio_oe;
    wire       tt_rst_n;

    // =========================================================================
    // AXI-Lite Frame Buffer
    // =========================================================================
    viterbi_axi_framebuf u_framebuf (
        .S_AXI_ACLK    (pl_clk),
        .S_AXI_ARESETN  (pl_resetn),
        // Write address (use lower 12 bits — interconnect handles base offset)
        .S_AXI_AWADDR   (axi_awaddr[11:0]),
        .S_AXI_AWPROT   (axi_awprot),
        .S_AXI_AWVALID  (axi_awvalid),
        .S_AXI_AWREADY  (axi_awready),
        // Write data
        .S_AXI_WDATA    (axi_wdata),
        .S_AXI_WSTRB    (axi_wstrb),
        .S_AXI_WVALID   (axi_wvalid),
        .S_AXI_WREADY   (axi_wready),
        // Write response
        .S_AXI_BRESP    (axi_bresp),
        .S_AXI_BVALID   (axi_bvalid),
        .S_AXI_BREADY   (axi_bready),
        // Read address
        .S_AXI_ARADDR   (axi_araddr[11:0]),
        .S_AXI_ARPROT   (axi_arprot),
        .S_AXI_ARVALID  (axi_arvalid),
        .S_AXI_ARREADY  (axi_arready),
        // Read data
        .S_AXI_RDATA    (axi_rdata),
        .S_AXI_RRESP    (axi_rresp),
        .S_AXI_RVALID   (axi_rvalid),
        .S_AXI_RREADY   (axi_rready),
        // TT module interface
        .tt_ui_in       (tt_ui_in),
        .tt_uio_in      (tt_uio_in),
        .tt_uo_out      (tt_uo_out),
        .tt_uio_out     (tt_uio_out),
        .tt_rst_n       (tt_rst_n),
        // Status LEDs
        .led_mode       (led0),
        .led_busy       (led1),
        .led_done       (led2)
    );

    // =========================================================================
    // TinyTapeout Viterbi decoder (K driven by `define, default K=7)
    // =========================================================================
    tt_um_ashvin_viterbi #(
        .K       (`K_SEL),
        .D_TB    (`D_TB_SEL),
        .RATE    (2),
        .G0_OCT  (`G0_SEL),
        .G1_OCT  (`G1_SEL),
        .G2_OCT  ('o0)
    ) u_tt (
        .ui_in   (tt_ui_in),
        .uo_out  (tt_uo_out),
        .uio_in  (tt_uio_in),
        .uio_out (tt_uio_out),
        .uio_oe  (tt_uio_oe),
        .ena     (1'b1),
        .clk     (pl_clk),
        .rst_n   (tt_rst_n)
    );

    // =========================================================================
    // Heartbeat LED (~1 Hz at 50 MHz)
    // =========================================================================
    reg [24:0] heartbeat_cnt;
    always @(posedge pl_clk) begin
        if (!pl_resetn)
            heartbeat_cnt <= 25'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 25'd1;
    end

    // =========================================================================
    // LED assignments
    //   LD0 = mode    (ON when decoder is in Mode 1)
    //   LD1 = busy    (ON during frame processing)
    //   LD2 = done    (ON when decoded output is ready)
    //   LD3 = heartbeat (~1.5 Hz, proves clock is running)
    // =========================================================================
    // led0, led1, led2 driven by u_framebuf port connections above
    assign led3 = heartbeat_cnt[24];

endmodule

`default_nettype wire
