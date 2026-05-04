// =============================================================================
// axi_tt_bridge.v -- Bridge between slow AXI GPIO (XSDB) and fast TT module
//
// Solves two speed-mismatch problems:
//
// INPUT:  XSDB mwr holds GPIO values for milliseconds, but byte_valid and
//         read_ack must be single-cycle pulses. Rising-edge detectors convert
//         GPIO level changes into clean 1-cycle pulses.
//
// OUTPUT: Decoded output bytes appear for ~160ns before being overwritten.
//         XSDB reads take 5-50ms. Solution: auto-ack the bit_packer immediately
//         and capture each output byte into a small FIFO. XSDB reads the FIFO
//         at its own pace.
//
// AXI GPIO register map:
//   GPIO_OUT (0x41200000) write:
//     [7:0]  = ui_in   ([7]=mode, [0]=byte_valid edge-detected)
//     [15:8] = uio_in  (input data byte)
//
//   GPIO_IN (0x41210000) read:
//     [7:0]  = uo_out-like status:
//                [0] = byte_in_ready (unpacker ready for next byte)
//                [1] = fifo_not_empty (FIFO has output byte to read)
//                [2] = rx_sym_ready
//                [3] = fifo_count > 0
//                [4] = fifo_count MSB
//     [15:8] = FIFO head byte (next decoded byte to read)
//
//   read_ack from GPIO (ui_in[4] rising edge) pops the FIFO.
// =============================================================================

`default_nettype none

module axi_tt_bridge (
    input  wire        clk,
    input  wire        resetn,

    // From AXI GPIO output register
    input  wire [7:0]  axi_ui_in,
    input  wire [7:0]  axi_uio_in,

    // To TT module
    output wire [7:0]  tt_ui_in,
    output wire [7:0]  tt_uio_in,

    // From TT module
    input  wire [7:0]  tt_uo_out,
    input  wire [7:0]  tt_uio_out,

    // To AXI GPIO input register
    output wire [7:0]  axi_uo_out,
    output wire [7:0]  axi_uio_out,

    // Soft reset: pulses low on mode 0→1 transition
    output wire        soft_resetn
);

    // =========================================================================
    // Soft reset on mode 0→1 transition (resets Viterbi core warm_cnt, etc.)
    // =========================================================================
    reg mode_prev;
    reg [2:0] rst_cnt;  // hold reset for 4 cycles
    always @(posedge clk)
        if (!resetn) mode_prev <= 1'b0;
        else         mode_prev <= axi_ui_in[7];

    wire mode_rising = axi_ui_in[7] & ~mode_prev;

    always @(posedge clk)
        if (!resetn)
            rst_cnt <= 3'd0;
        else if (mode_rising)
            rst_cnt <= 3'd4;
        else if (rst_cnt != 3'd0)
            rst_cnt <= rst_cnt - 3'd1;

    assign soft_resetn = (rst_cnt == 3'd0);

    // =========================================================================
    // Rising-edge detector for byte_valid (ui_in[0])
    // =========================================================================
    reg bv_prev;
    always @(posedge clk)
        if (!resetn) bv_prev <= 1'b0;
        else         bv_prev <= axi_ui_in[0];

    wire byte_valid_pulse = axi_ui_in[0] & ~bv_prev;

    // =========================================================================
    // Rising-edge detector for FIFO read (ui_in[4]) -- pops FIFO
    // =========================================================================
    reg ra_prev;
    always @(posedge clk)
        if (!resetn) ra_prev <= 1'b0;
        else         ra_prev <= axi_ui_in[4];

    wire fifo_pop_pulse = axi_ui_in[4] & ~ra_prev;

    // =========================================================================
    // TT module inputs
    // =========================================================================
    // Auto-ack: when TT module asserts byte_out_valid, immediately pulse
    // read_ack back so the bit_packer clears and accepts more bits.
    wire packer_valid = tt_uo_out[1];  // byte_out_valid from TT

    reg pv_prev;
    always @(posedge clk)
        if (!resetn) pv_prev <= 1'b0;
        else         pv_prev <= packer_valid;

    wire auto_ack_pulse = packer_valid & ~pv_prev;  // rising edge of byte_out_valid

    assign tt_ui_in = {
        axi_ui_in[7:5],        // [7]=mode, [6:5]=unused
        auto_ack_pulse,         // [4]=read_ack (auto-ack to TT packer)
        axi_ui_in[3:1],        // [3]=force_state0, [2:1]=sym bits
        byte_valid_pulse        // [0]=byte_valid (pulsed)
    };

    assign tt_uio_in = axi_uio_in;

    // =========================================================================
    // Output FIFO (16 entries x 8 bits)
    // =========================================================================
    reg [7:0] fifo_mem [0:15];
    reg [3:0] wr_ptr;
    reg [3:0] rd_ptr;
    reg [4:0] count;

    wire fifo_empty    = (count == 0);
    wire fifo_full     = (count == 16);
    wire fifo_push     = auto_ack_pulse & ~fifo_full;
    wire fifo_pop      = fifo_pop_pulse & ~fifo_empty;

    wire fifo_rst = !resetn || !soft_resetn;

    always @(posedge clk) begin
        if (fifo_rst) begin
            wr_ptr <= 4'd0;
            rd_ptr <= 4'd0;
            count  <= 5'd0;
        end else begin
            case ({fifo_push, fifo_pop})
                2'b10: begin  // push only
                    fifo_mem[wr_ptr] <= tt_uio_out;
                    wr_ptr <= wr_ptr + 4'd1;
                    count  <= count + 5'd1;
                end
                2'b01: begin  // pop only
                    rd_ptr <= rd_ptr + 4'd1;
                    count  <= count - 5'd1;
                end
                2'b11: begin  // push + pop simultaneously
                    fifo_mem[wr_ptr] <= tt_uio_out;
                    wr_ptr <= wr_ptr + 4'd1;
                    rd_ptr <= rd_ptr + 4'd1;
                    // count stays same
                end
                default: ;    // no change
            endcase
        end
    end

    // =========================================================================
    // AXI GPIO outputs
    // =========================================================================
    // Status byte: replaces uo_out with FIFO-aware status
    assign axi_uo_out[0] = tt_uo_out[0];       // byte_in_ready (from unpacker)
    assign axi_uo_out[1] = ~fifo_empty;         // FIFO has data (replaces byte_out_valid)
    assign axi_uo_out[2] = tt_uo_out[2];        // rx_sym_ready
    assign axi_uo_out[3] = ~fifo_empty;         // alias
    assign axi_uo_out[4] = count[4];            // overflow indicator
    assign axi_uo_out[7:5] = 3'b0;

    // Data byte: FIFO head (valid when not empty)
    assign axi_uio_out = fifo_empty ? 8'h00 : fifo_mem[rd_ptr];

endmodule

`default_nettype wire
