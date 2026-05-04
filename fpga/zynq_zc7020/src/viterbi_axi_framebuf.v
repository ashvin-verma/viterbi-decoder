// =============================================================================
// viterbi_axi_framebuf.v -- AXI-Lite frame buffer for Viterbi decoder
//
// Replaces the byte-at-a-time GPIO bridge with a BRAM-backed AXI-Lite
// peripheral. The host writes an entire encoded frame into INPUT_BUF,
// sets FRAME_LEN, triggers CTRL, and reads decoded output from OUTPUT_BUF.
//
// Register Map (4 KB window):
//   0x000  CTRL       R/W  [0]=trigger (auto-clear), [1]=soft_reset
//   0x004  STATUS     RO   [0]=busy, [1]=done, [15:8]=output byte count
//   0x008  FRAME_LEN  R/W  [8:0]=input byte count (1-256)
//   0x400  INPUT_BUF  WO   256-byte input buffer (64 x 32-bit words)
//   0x800  OUTPUT_BUF RO   256-byte output buffer (64 x 32-bit words)
//
// Frame Controller FSM:
//   FC_IDLE -> FC_RESET -> FC_FEED -> FC_DRAIN -> FC_DONE -> FC_IDLE
// =============================================================================

`default_nettype none

module viterbi_axi_framebuf (
    // AXI-Lite slave interface
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,

    input  wire [11:0] S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output reg         S_AXI_AWREADY,

    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output reg         S_AXI_WREADY,

    output reg  [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    input  wire [11:0] S_AXI_ARADDR,
    input  wire [2:0]  S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output reg         S_AXI_ARREADY,

    output reg  [31:0] S_AXI_RDATA,
    output reg  [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    // TT module interface
    output wire [7:0]  tt_ui_in,
    output wire [7:0]  tt_uio_in,
    input  wire [7:0]  tt_uo_out,
    input  wire [7:0]  tt_uio_out,

    // Reset to TT module (active-low)
    output wire        tt_rst_n,

    // Status LEDs
    output wire        led_mode,
    output wire        led_busy,
    output wire        led_done
);

    // =========================================================================
    // Address decode constants
    // =========================================================================
    localparam ADDR_CTRL      = 12'h000;
    localparam ADDR_STATUS    = 12'h004;
    localparam ADDR_FRAME_LEN = 12'h008;
    localparam ADDR_IN_BASE   = 12'h400;
    localparam ADDR_IN_END    = 12'h4FC;  // 64 words = 256 bytes
    localparam ADDR_OUT_BASE  = 12'h800;
    localparam ADDR_OUT_END   = 12'h8FC;

    // =========================================================================
    // Internal registers
    // =========================================================================
    reg        ctrl_trigger;      // [0] auto-clears after FSM starts
    reg        ctrl_soft_reset;   // [1] manual soft reset
    reg [8:0]  frame_len;         // input byte count (1-256, 0 = 256)
    reg        status_busy;
    reg        status_done;
    reg [7:0]  out_byte_count;

    // =========================================================================
    // Input BRAM (256 x 8, written as 32-bit words from AXI)
    // =========================================================================
    reg [7:0] input_bram [0:255];
    reg [7:0] output_bram [0:255];

    // =========================================================================
    // Frame Controller FSM
    // =========================================================================
    localparam [2:0]
        FC_IDLE  = 3'd0,
        FC_RESET = 3'd1,
        FC_FEED  = 3'd2,
        FC_DRAIN = 3'd3,
        FC_DONE  = 3'd4;

    reg [2:0]  fc_state;
    reg [8:0]  fc_rd_idx;       // input read index (byte address)
    reg [8:0]  fc_wr_idx;       // output write index
    reg [3:0]  fc_rst_cnt;      // reset hold counter
    reg [13:0] fc_timeout;      // drain timeout counter
    reg [8:0]  fc_frame_len_r;  // latched frame length

    // TT module control signals from FSM
    reg        fc_byte_valid;   // pulse byte_valid to TT
    reg        fc_mode;         // mode bit
    reg        fc_rst_active;   // active during reset phase
    reg        fc_wait_ack;     // delay rd_idx increment after byte_valid pulse

    // =========================================================================
    // Auto-ack: detect rising edge of byte_out_valid from TT
    // =========================================================================
    wire packer_valid = tt_uo_out[1];  // byte_out_valid
    reg  pv_prev;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            pv_prev <= 1'b0;
        else
            pv_prev <= packer_valid;
    end

    wire auto_ack_pulse = packer_valid & ~pv_prev;

    // =========================================================================
    // TT module input wiring
    // =========================================================================
    // ui_in: [7]=mode, [6:5]=unused, [4]=read_ack, [3]=force_state0, [2:1]=sym, [0]=byte_valid
    assign tt_ui_in = {
        fc_mode,              // [7] mode
        2'b0,                 // [6:5] unused
        auto_ack_pulse,       // [4] read_ack (auto-ack packer)
        1'b0,                 // [3] force_state0
        2'b0,                 // [2:1] sym (unused in mode 1)
        fc_byte_valid         // [0] byte_valid
    };

    assign tt_uio_in = input_bram[fc_rd_idx[7:0]];  // data byte from BRAM

    // TT reset: active low, asserted during FC_RESET phase or manual soft reset
    assign tt_rst_n = S_AXI_ARESETN & ~fc_rst_active & ~ctrl_soft_reset;

    // =========================================================================
    // Frame Controller FSM
    // =========================================================================
    wire byte_in_ready = tt_uo_out[0];  // unpacker ready for next byte

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN || ctrl_soft_reset) begin
            fc_state       <= FC_IDLE;
            fc_rd_idx      <= 9'd0;
            fc_rst_cnt     <= 4'd0;
            fc_timeout     <= 14'd0;
            fc_byte_valid  <= 1'b0;
            fc_mode        <= 1'b0;
            fc_rst_active  <= 1'b0;
            fc_wait_ack    <= 1'b0;
            status_busy    <= 1'b0;
            status_done    <= 1'b0;
            out_byte_count <= 8'd0;
            fc_frame_len_r <= 9'd0;
        end else begin
            // Default: clear single-cycle pulse
            fc_byte_valid <= 1'b0;

            case (fc_state)
                FC_IDLE: begin
                    if (ctrl_trigger) begin
                        fc_state       <= FC_RESET;
                        fc_frame_len_r <= (frame_len == 9'd0) ? 9'd256 : frame_len;
                        fc_rd_idx      <= 9'd0;
                        fc_rst_cnt     <= 4'd8;  // 8-cycle reset pulse
                        fc_mode        <= 1'b0;  // mode=0 before transition
                        fc_rst_active  <= 1'b1;
                        fc_wait_ack    <= 1'b0;
                        status_busy    <= 1'b1;
                        status_done    <= 1'b0;
                        out_byte_count <= 8'd0;
                    end
                end

                FC_RESET: begin
                    if (fc_rst_cnt == 4'd0) begin
                        // End reset, set mode=1 (triggers soft reset via mode transition)
                        fc_rst_active <= 1'b0;
                        fc_mode       <= 1'b1;
                        fc_state      <= FC_FEED;
                    end else begin
                        fc_rst_cnt <= fc_rst_cnt - 4'd1;
                    end
                end

                FC_FEED: begin
                    // After a byte_valid pulse, advance rd_idx on the NEXT cycle
                    // (so data is stable on tt_uio_in while byte_valid is high)
                    if (fc_wait_ack) begin
                        fc_rd_idx   <= fc_rd_idx + 9'd1;
                        fc_wait_ack <= 1'b0;
                    end else if (fc_rd_idx >= fc_frame_len_r) begin
                        // All input bytes sent, wait for output
                        fc_state   <= FC_DRAIN;
                        fc_timeout <= 14'd0;
                    end else if (byte_in_ready && !fc_byte_valid) begin
                        // Pulse byte_valid — data at bram[fc_rd_idx] is on bus
                        fc_byte_valid <= 1'b1;
                        fc_wait_ack   <= 1'b1;
                    end
                end

                FC_DRAIN: begin
                    // Wait for last output bytes or timeout
                    fc_timeout <= fc_timeout + 14'd1;
                    if (fc_timeout >= 14'd8191) begin
                        fc_state <= FC_DONE;
                    end
                end

                FC_DONE: begin
                    status_busy    <= 1'b0;
                    status_done    <= 1'b1;
                    out_byte_count <= fc_wr_idx[7:0];
                    fc_state       <= FC_IDLE;
                end

                default: fc_state <= FC_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Output capture: write decoded bytes to output BRAM
    // Resets on trigger (via fc_wr_idx_rst flag from register write block)
    // =========================================================================
    reg fc_wr_idx_rst;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN || fc_wr_idx_rst || ctrl_soft_reset) begin
            fc_wr_idx <= 9'd0;
        end else if (auto_ack_pulse && fc_wr_idx < 9'd256) begin
            output_bram[fc_wr_idx[7:0]] <= tt_uio_out;
            fc_wr_idx <= fc_wr_idx + 9'd1;
        end
    end

    // =========================================================================
    // AXI-Lite Write Channel
    // =========================================================================
    reg [11:0] aw_addr_r;
    reg        aw_done;
    reg        w_done;

    // Write address handshake
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY <= 1'b0;
            aw_addr_r     <= 12'd0;
            aw_done       <= 1'b0;
        end else begin
            if (S_AXI_AWVALID && !aw_done) begin
                S_AXI_AWREADY <= 1'b1;
                aw_addr_r     <= S_AXI_AWADDR;
                aw_done       <= 1'b1;
            end else begin
                S_AXI_AWREADY <= 1'b0;
            end
            if (S_AXI_BVALID && S_AXI_BREADY)
                aw_done <= 1'b0;
        end
    end

    // Write data handshake
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_WREADY <= 1'b0;
            w_done       <= 1'b0;
        end else begin
            if (S_AXI_WVALID && !w_done) begin
                S_AXI_WREADY <= 1'b1;
                w_done       <= 1'b1;
            end else begin
                S_AXI_WREADY <= 1'b0;
            end
            if (S_AXI_BVALID && S_AXI_BREADY)
                w_done <= 1'b0;
        end
    end

    // Write response
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_BRESP  <= 2'b00;
        end else begin
            if (aw_done && w_done && !S_AXI_BVALID) begin
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= 2'b00;  // OKAY
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // Register writes
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            ctrl_trigger    <= 1'b0;
            ctrl_soft_reset <= 1'b0;
            frame_len       <= 9'd0;
            fc_wr_idx_rst   <= 1'b0;
        end else begin
            // Auto-clear trigger after one cycle
            if (ctrl_trigger)
                ctrl_trigger <= 1'b0;

            fc_wr_idx_rst <= 1'b0;

            // Process write when both address and data are ready
            if (aw_done && w_done && !S_AXI_BVALID) begin
                if (aw_addr_r == ADDR_CTRL) begin
                    if (S_AXI_WSTRB[0]) begin
                        ctrl_trigger    <= S_AXI_WDATA[0];
                        ctrl_soft_reset <= S_AXI_WDATA[1];
                        if (S_AXI_WDATA[0])
                            fc_wr_idx_rst <= 1'b1;  // reset output index on trigger
                    end
                end
                else if (aw_addr_r == ADDR_FRAME_LEN) begin
                    if (S_AXI_WSTRB[0])
                        frame_len[7:0] <= S_AXI_WDATA[7:0];
                    if (S_AXI_WSTRB[1])
                        frame_len[8]   <= S_AXI_WDATA[8];
                end
                else if (aw_addr_r >= ADDR_IN_BASE && aw_addr_r <= ADDR_IN_END) begin
                    // Write to input BRAM (4 bytes per 32-bit word)
                    // Word address: (addr - 0x400) / 4 -> byte base = word_idx * 4
                    // Each 32-bit write stores up to 4 bytes
                    if (S_AXI_WSTRB[0])
                        input_bram[{aw_addr_r[7:2], 2'b00}] <= S_AXI_WDATA[7:0];
                    if (S_AXI_WSTRB[1])
                        input_bram[{aw_addr_r[7:2], 2'b01}] <= S_AXI_WDATA[15:8];
                    if (S_AXI_WSTRB[2])
                        input_bram[{aw_addr_r[7:2], 2'b10}] <= S_AXI_WDATA[23:16];
                    if (S_AXI_WSTRB[3])
                        input_bram[{aw_addr_r[7:2], 2'b11}] <= S_AXI_WDATA[31:24];
                end
            end
        end
    end

    // =========================================================================
    // AXI-Lite Read Channel
    // =========================================================================
    reg [11:0] ar_addr_r;

    // Read address handshake
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY <= 1'b0;
            ar_addr_r     <= 12'd0;
        end else begin
            if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
                S_AXI_ARREADY <= 1'b1;
                ar_addr_r     <= S_AXI_ARADDR;
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end
        end
    end

    // Read data + response
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= 32'd0;
            S_AXI_RRESP  <= 2'b00;
        end else begin
            if (S_AXI_ARREADY) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RRESP  <= 2'b00;  // OKAY

                if (ar_addr_r == ADDR_CTRL)
                    S_AXI_RDATA <= {30'd0, ctrl_soft_reset, ctrl_trigger};
                else if (ar_addr_r == ADDR_STATUS)
                    S_AXI_RDATA <= {16'd0, out_byte_count, 6'd0, status_done, status_busy};
                else if (ar_addr_r == ADDR_FRAME_LEN)
                    S_AXI_RDATA <= {23'd0, frame_len};
                else if (ar_addr_r >= ADDR_OUT_BASE && ar_addr_r <= ADDR_OUT_END) begin
                    // Read from output BRAM (4 bytes per word)
                    S_AXI_RDATA <= {
                        output_bram[{ar_addr_r[7:2], 2'b11}],
                        output_bram[{ar_addr_r[7:2], 2'b10}],
                        output_bram[{ar_addr_r[7:2], 2'b01}],
                        output_bram[{ar_addr_r[7:2], 2'b00}]
                    };
                end
                else
                    S_AXI_RDATA <= 32'hDEADBEEF;  // unmapped
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    // =========================================================================
    // LED status outputs
    // =========================================================================
    assign led_mode = fc_mode;
    assign led_busy = status_busy;
    assign led_done = status_done;

endmodule

`default_nettype wire
