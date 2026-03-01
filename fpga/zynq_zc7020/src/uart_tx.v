// =============================================================================
// uart_tx.v -- PL UART Serial Transmitter (115200 baud, 50 MHz clock)
//
// 8N1 format, no flow control.
// Input: 8-bit data with valid/ready handshake.
// =============================================================================

`default_nettype none

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,

    // Parallel input (valid/ready handshake)
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output reg        tx_ready,

    // Serial output
    output reg        tx_serial
);

    // -------------------------------------------------------------------------
    // Baud-rate parameters
    // -------------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // ~434

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    // -------------------------------------------------------------------------
    // Transmitter FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            clk_cnt    <= 16'd0;
            bit_idx    <= 3'd0;
            shift_reg  <= 8'd0;
            tx_serial  <= 1'b1;   // idle high
            tx_ready   <= 1'b1;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE: line high, wait for data
                // ---------------------------------------------------------
                S_IDLE: begin
                    tx_serial <= 1'b1;
                    clk_cnt   <= 16'd0;
                    bit_idx   <= 3'd0;
                    if (tx_valid && tx_ready) begin
                        shift_reg <= tx_data;
                        tx_ready  <= 1'b0;
                        state     <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // START: drive low for one bit period
                // ---------------------------------------------------------
                S_START: begin
                    tx_serial <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                // ---------------------------------------------------------
                // DATA: send 8 bits, LSB first
                // ---------------------------------------------------------
                S_DATA: begin
                    tx_serial <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
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
                // STOP: drive high for one bit period
                // ---------------------------------------------------------
                S_STOP: begin
                    tx_serial <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt  <= 16'd0;
                        tx_ready <= 1'b1;
                        state    <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
