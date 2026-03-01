// =============================================================================
// top_zynq.v -- Top-level FPGA wrapper for Zynq ZC7020 (PYNQ-Z2)
//
// Clock:  PS FCLK_CLK0 at 50 MHz (directly from Zynq PS, no PLL needed)
// Reset:  Active-low pushbutton (BTN0), synchronized to clk domain
// UART:   Pure-PL UART on Pmod A (JA) pins, 115200 baud, 8N1
//           JA[0] = UART RX (FPGA input,  from host TX)
//           JA[1] = UART TX (FPGA output, to host RX)
// LEDs:   LD0 = busy, LD1 = done, LD2 = rx_activity, LD3 = tx_activity
//
// No AXI, no ARM software required.  Purely PL fabric.
// =============================================================================

`default_nettype none

module top_zynq (
    // Clock from PS (directly from processing system FCLK_CLK0)
    input  wire       clk,

    // Active-low reset pushbutton (BTN0)
    input  wire       btn0_n,

    // Pmod A (JA) -- directly to FPGA pins
    input  wire       ja0,     // UART RX (FPGA receives from host)
    output wire       ja1,     // UART TX (FPGA sends to host)

    // LEDs
    output wire       led0,    // busy
    output wire       led1,    // done
    output wire       led2,    // rx_activity
    output wire       led3     // tx_activity
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115200;

    // =========================================================================
    // Reset synchronizer (async assert, sync deassert)
    // =========================================================================
    reg [2:0] rst_sync;
    wire      rst;        // active-high, synchronized reset
    wire      rst_n;      // active-low for TT module

    always @(posedge clk or negedge btn0_n) begin
        if (!btn0_n)
            rst_sync <= 3'b111;
        else
            rst_sync <= {rst_sync[1:0], 1'b0};
    end

    assign rst   = rst_sync[2];
    assign rst_n = ~rst;

    // =========================================================================
    // UART RX
    // =========================================================================
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk       (clk),
        .rst       (rst),
        .rx_serial (ja0),
        .rx_data   (uart_rx_data),
        .rx_valid  (uart_rx_valid)
    );

    // =========================================================================
    // UART TX
    // =========================================================================
    wire [7:0] uart_tx_data;
    wire       uart_tx_valid;
    wire       uart_tx_ready;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk       (clk),
        .rst       (rst),
        .tx_data   (uart_tx_data),
        .tx_valid  (uart_tx_valid),
        .tx_ready  (uart_tx_ready),
        .tx_serial (ja1)
    );

    // =========================================================================
    // TT module interface wires
    // =========================================================================
    wire [7:0] tt_ui_in;
    wire [7:0] tt_uo_out;
    wire [7:0] tt_uio_in;
    wire [7:0] tt_uio_out;
    wire [7:0] tt_uio_oe;

    // =========================================================================
    // UART <-> Viterbi bridge
    // =========================================================================
    wire bridge_busy;
    wire bridge_done;
    wire bridge_rx_activity;
    wire bridge_tx_activity;

    uart_viterbi_bridge u_bridge (
        .clk            (clk),
        .rst            (rst),

        // UART RX
        .uart_rx_data   (uart_rx_data),
        .uart_rx_valid  (uart_rx_valid),

        // UART TX
        .uart_tx_data   (uart_tx_data),
        .uart_tx_valid  (uart_tx_valid),
        .uart_tx_ready  (uart_tx_ready),

        // TT module pins
        .tt_ui_in       (tt_ui_in),
        .tt_uo_out      (tt_uo_out),
        .tt_uio_in      (tt_uio_in),
        .tt_uio_out     (tt_uio_out),

        // Status
        .busy           (bridge_busy),
        .done           (bridge_done),
        .rx_activity    (bridge_rx_activity),
        .tx_activity    (bridge_tx_activity)
    );

    // =========================================================================
    // TinyTapeout top module  (Mode 1 = byte batch)
    // ui_in[7] is set to 1 by the bridge to select Mode 1
    // =========================================================================
    tt_um_ashvin_viterbi u_tt (
        .ui_in   (tt_ui_in),
        .uo_out  (tt_uo_out),
        .uio_in  (tt_uio_in),
        .uio_out (tt_uio_out),
        .uio_oe  (tt_uio_oe),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // =========================================================================
    // LED outputs
    // =========================================================================
    // Stretch activity pulses so they are visible on LEDs
    reg [19:0] rx_led_cnt;
    reg [19:0] tx_led_cnt;
    localparam LED_STRETCH = 20'd500_000;  // 10ms at 50 MHz

    always @(posedge clk) begin
        if (rst) begin
            rx_led_cnt <= 20'd0;
            tx_led_cnt <= 20'd0;
        end else begin
            // RX activity stretcher
            if (bridge_rx_activity)
                rx_led_cnt <= LED_STRETCH;
            else if (rx_led_cnt != 20'd0)
                rx_led_cnt <= rx_led_cnt - 20'd1;

            // TX activity stretcher
            if (bridge_tx_activity)
                tx_led_cnt <= LED_STRETCH;
            else if (tx_led_cnt != 20'd0)
                tx_led_cnt <= tx_led_cnt - 20'd1;
        end
    end

    assign led0 = bridge_busy;
    assign led1 = bridge_done;
    assign led2 = (rx_led_cnt != 20'd0);
    assign led3 = (tx_led_cnt != 20'd0);

endmodule

`default_nettype wire
