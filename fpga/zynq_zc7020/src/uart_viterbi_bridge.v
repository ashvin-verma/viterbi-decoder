// =============================================================================
// uart_viterbi_bridge.v -- Serial UART <-> TinyTapeout Mode 1 byte bridge
//
// Protocol (same as TinyTapeout Mode 1):
//   Host -> FPGA:
//     Byte 0:   frame_length N  (number of input bytes, each has 4 symbols)
//     Bytes 1..N: encoded symbol data (4 packed 2-bit symbols per byte, LSB first)
//
//   FPGA -> Host:
//     After all input symbols are processed, the decoded output bytes
//     are transmitted back via UART TX.  Each input byte produces 4 symbols
//     which (after pipeline warm-up) yield 4 decoded bits.  Since 8 bits
//     per output byte, each 2 input bytes produce 1 output byte.
//     Total output bytes = (N * 4) / 8 = N / 2  (rounded down).
//     First D_TB decoded bits are discarded during warm-up (handled by core).
//
// This bridge talks to the TT module's Mode 1 interface:
//   ui_in[7]   = 1  (mode select: byte batch)
//   ui_in[0]   = byte_valid  (sym_unpacker input valid)
//   ui_in[3]   = force_state0  (tail termination -- held low here)
//   ui_in[4]   = read_ack  (bit_packer output ready)
//   uio_in[7:0] = input byte to sym_unpacker
//
//   uo_out[0]  = byte_in_ready  (unpacker ready for next byte)
//   uo_out[1]  = byte_out_valid (packer has output byte ready)
//   uo_out[2]  = rx_sym_ready   (core symbol input ready)
//   uo_out[3]  = busy
//   uo_out[4]  = done
//   uio_out[7:0] = output byte from bit_packer
// =============================================================================

`default_nettype none

module uart_viterbi_bridge (
    input  wire       clk,
    input  wire       rst,

    // UART RX interface (from uart_rx)
    input  wire [7:0] uart_rx_data,
    input  wire       uart_rx_valid,

    // UART TX interface (to uart_tx)
    output reg  [7:0] uart_tx_data,
    output reg        uart_tx_valid,
    input  wire       uart_tx_ready,

    // TT module pins -- directly wired to tt_um_ashvin_viterbi
    output reg  [7:0] tt_ui_in,
    input  wire [7:0] tt_uo_out,
    output reg  [7:0] tt_uio_in,
    input  wire [7:0] tt_uio_out,

    // Status indicators
    output wire       busy,
    output wire       done,
    output wire       rx_activity,
    output wire       tx_activity
);

    // -------------------------------------------------------------------------
    // TT Mode 1 signal aliases
    // -------------------------------------------------------------------------
    wire tt_byte_in_ready  = tt_uo_out[0];
    wire tt_byte_out_valid = tt_uo_out[1];
    // tt_uo_out[2] = rx_sym_ready (not needed here)
    // tt_uo_out[3] = batch_busy
    // tt_uo_out[4] = batch_done

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE      = 3'd0,   // Waiting for frame length byte
                     S_RECV      = 3'd1,   // Receiving input data bytes
                     S_FEED      = 3'd2,   // Feeding a byte to TT module
                     S_FEED_WAIT = 3'd3,   // Wait for TT to accept byte
                     S_DRAIN     = 3'd4,   // Drain decoded output bytes
                     S_TX_BYTE   = 3'd5,   // Send one byte via UART TX
                     S_TX_WAIT   = 3'd6;   // Wait for UART TX to finish

    reg [2:0]  state;
    reg [7:0]  frame_len;         // number of input bytes in this frame
    reg [7:0]  bytes_received;    // count of data bytes received so far
    reg [7:0]  bytes_fed;         // count of data bytes fed to TT so far
    reg [7:0]  bytes_out_sent;    // count of output bytes sent via TX
    reg [7:0]  expected_out;      // expected number of output bytes

    // Input buffer: up to 255 bytes. For Viterbi K=7 with D=42,
    // typical frames are small (tens of bytes).
    reg [7:0]  in_buf [0:255];
    reg [7:0]  current_byte;      // byte being fed to TT module

    // Timeout counter for drain phase -- if TT doesn't produce output
    // for a long time, we declare the frame complete.
    reg [19:0] drain_timeout;
    localparam DRAIN_TIMEOUT_MAX = 20'd500_000;  // 10ms at 50 MHz

    // -------------------------------------------------------------------------
    // Status outputs
    // -------------------------------------------------------------------------
    assign busy = (state != S_IDLE);
    assign done = (state == S_IDLE);
    assign rx_activity = uart_rx_valid;
    assign tx_activity = uart_tx_valid && uart_tx_ready;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            frame_len       <= 8'd0;
            bytes_received  <= 8'd0;
            bytes_fed       <= 8'd0;
            bytes_out_sent  <= 8'd0;
            expected_out    <= 8'd0;
            current_byte    <= 8'd0;
            drain_timeout   <= 20'd0;
            tt_ui_in        <= 8'b1000_0000;  // Mode 1 selected, everything else 0
            tt_uio_in       <= 8'd0;
            uart_tx_data    <= 8'd0;
            uart_tx_valid   <= 1'b0;
        end else begin
            // Default: deassert handshake signals each cycle
            // Keep Mode 1 bit (ui_in[7]) always high
            tt_ui_in[7]   <= 1'b1;
            tt_ui_in[6:5] <= 2'b0;
            tt_ui_in[3]   <= 1'b0;  // force_state0 = 0
            tt_ui_in[2:1] <= 2'b0;  // unused in Mode 1 (sym from unpacker)

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for first byte = frame length
                // ---------------------------------------------------------
                S_IDLE: begin
                    tt_ui_in[0] <= 1'b0;  // byte_valid = 0
                    tt_ui_in[4] <= 1'b0;  // read_ack = 0
                    if (uart_rx_valid) begin
                        frame_len      <= uart_rx_data;
                        bytes_received <= 8'd0;
                        bytes_fed      <= 8'd0;
                        bytes_out_sent <= 8'd0;
                        // Output bytes = (frame_len * 4 bits_decoded) / 8 = frame_len / 2
                        // But the core has D=42 warm-up symbols, so the first D decoded
                        // bits are suppressed.  The bit_packer inside the TT module handles
                        // the packing.  We just drain whatever the TT module produces.
                        // We'll use a timeout-based approach for simplicity.
                        expected_out   <= uart_rx_data >> 1;  // N/2
                        state          <= S_RECV;
                    end
                end

                // ---------------------------------------------------------
                // RECV: collect data bytes from UART RX
                // ---------------------------------------------------------
                S_RECV: begin
                    tt_ui_in[0] <= 1'b0;
                    tt_ui_in[4] <= 1'b0;
                    if (uart_rx_valid) begin
                        in_buf[bytes_received] <= uart_rx_data;
                        bytes_received <= bytes_received + 8'd1;
                        if (bytes_received + 8'd1 == frame_len) begin
                            // All input bytes received, start feeding
                            state <= S_FEED;
                        end
                    end
                end

                // ---------------------------------------------------------
                // FEED: present next byte to TT module
                // ---------------------------------------------------------
                S_FEED: begin
                    tt_ui_in[4] <= 1'b0;
                    if (bytes_fed < frame_len) begin
                        current_byte <= in_buf[bytes_fed];
                        tt_uio_in    <= in_buf[bytes_fed];
                        tt_ui_in[0]  <= 1'b0;  // don't assert valid yet
                        state        <= S_FEED_WAIT;
                    end else begin
                        // All bytes fed, move to drain phase
                        drain_timeout <= 20'd0;
                        state         <= S_DRAIN;
                    end
                end

                // ---------------------------------------------------------
                // FEED_WAIT: assert byte_valid, wait for TT to accept
                // ---------------------------------------------------------
                S_FEED_WAIT: begin
                    tt_uio_in   <= current_byte;
                    tt_ui_in[0] <= 1'b1;  // byte_valid = 1
                    tt_ui_in[4] <= 1'b0;

                    if (tt_byte_in_ready) begin
                        // TT accepted the byte (in_ready is high while we present valid)
                        // The handshake: valid && ready on same cycle = transfer.
                        bytes_fed   <= bytes_fed + 8'd1;
                        tt_ui_in[0] <= 1'b0;  // deassert valid
                        state       <= S_FEED;
                    end
                end

                // ---------------------------------------------------------
                // DRAIN: poll TT module for output bytes
                // ---------------------------------------------------------
                S_DRAIN: begin
                    tt_ui_in[0] <= 1'b0;
                    tt_ui_in[4] <= 1'b0;

                    if (tt_byte_out_valid) begin
                        // TT has a byte ready -- grab it
                        uart_tx_data  <= tt_uio_out;
                        tt_ui_in[4]   <= 1'b1;  // read_ack = 1
                        state         <= S_TX_BYTE;
                        drain_timeout <= 20'd0;
                    end else begin
                        drain_timeout <= drain_timeout + 20'd1;
                        if (drain_timeout >= DRAIN_TIMEOUT_MAX) begin
                            // No more output -- frame complete
                            state <= S_IDLE;
                        end
                    end
                end

                // ---------------------------------------------------------
                // TX_BYTE: begin UART transmit of one output byte
                // ---------------------------------------------------------
                S_TX_BYTE: begin
                    tt_ui_in[0] <= 1'b0;
                    tt_ui_in[4] <= 1'b0;  // deassert read_ack

                    if (uart_tx_ready) begin
                        uart_tx_valid  <= 1'b1;
                        state          <= S_TX_WAIT;
                    end
                end

                // ---------------------------------------------------------
                // TX_WAIT: wait for UART TX to accept byte
                // ---------------------------------------------------------
                S_TX_WAIT: begin
                    tt_ui_in[0] <= 1'b0;
                    tt_ui_in[4] <= 1'b0;

                    if (uart_tx_ready) begin
                        // TX accepted the byte
                        uart_tx_valid  <= 1'b0;
                        bytes_out_sent <= bytes_out_sent + 8'd1;
                        // Go back to drain for more output
                        drain_timeout  <= 20'd0;
                        state          <= S_DRAIN;
                    end else begin
                        // TX is busy, keep valid asserted
                        uart_tx_valid <= 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
