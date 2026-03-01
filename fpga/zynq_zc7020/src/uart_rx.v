// =============================================================================
// uart_rx.v -- PL UART Serial Receiver (115200 baud, 50 MHz clock)
//
// 8N1 format, no flow control. Oversamples at 16x baud rate.
// Output: 8-bit data with valid pulse when a full byte is received.
// =============================================================================

`default_nettype none

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,

    // Serial input
    input  wire       rx_serial,

    // Parallel output
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    // -------------------------------------------------------------------------
    // Baud-rate parameters (16x oversampling)
    // -------------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;          // ~434 for 50 MHz / 115200
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;              // mid-bit sample point

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;       // bit-period counter
    reg [2:0]  bit_idx;       // 0..7 data bits
    reg [7:0]  shift_reg;

    // Double-register the asynchronous rx_serial for metastability
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        rx_meta <= rx_serial;
        rx_sync <= rx_meta;
    end

    // -------------------------------------------------------------------------
    // Receiver FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;  // default: one-cycle pulse

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for start bit (falling edge -> rx_sync == 0)
                // ---------------------------------------------------------
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0) begin
                        state <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // START: wait to reach mid-point of start bit to confirm
                // ---------------------------------------------------------
                S_START: begin
                    if (clk_cnt == HALF_BIT[15:0]) begin
                        clk_cnt <= 16'd0;
                        if (rx_sync == 1'b0) begin
                            // Valid start bit
                            state <= S_DATA;
                        end else begin
                            // Glitch -- go back to idle
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                // ---------------------------------------------------------
                // DATA: sample 8 bits at mid-point of each bit period
                // ---------------------------------------------------------
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        shift_reg[bit_idx] <= rx_sync;  // LSB first
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                // ---------------------------------------------------------
                // STOP: wait for stop bit; output the received byte
                // ---------------------------------------------------------
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt  <= 16'd0;
                        rx_valid <= 1'b1;
                        rx_data  <= shift_reg;
                        state    <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
