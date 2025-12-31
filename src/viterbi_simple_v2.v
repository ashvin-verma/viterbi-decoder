// Ultra-simple Viterbi Decoder - Stores frame, then decodes
// No streaming, just batch mode for simplicity
`default_nettype none

module viterbi_simple_v2 #(
    parameter K = 3,
    parameter M = K - 1,
    parameter S = 1 << M,
    parameter [K-1:0] G0 = 3'b111,  // G0=7 octal for K=3
    parameter [K-1:0] G1 = 3'b101   // G1=5 octal for K=3
) (
    input wire clk,
    input wire rst,

    // Frame input
    input wire start,           // Pulse to start new frame
    input wire [7:0] frame_len, // Number of symbols in frame
    input wire [1:0] syms_in [0:255],  // All symbols at once

    // Output
    output reg done,
    output reg [7:0] out_len,
    output reg bits_out [0:255]
);

    // Path metrics (current and next)
    reg [15:0] pm [0:S-1][0:1];  // [state][bank]
    reg bank;

    // Survivor memory
    reg surv [0:255][0:S-1];  // [time][state]

    // Working variables
    reg [7:0] t;
    integer s, p0, p1, i;
    reg [1:0] exp0, exp1, rx;
    reg [15:0] m0, m1;
    reg [1:0] bm0, bm1;
    reg rx_bit;
    reg [15:0] min_metric;
    reg [M-1:0] min_state;

    // State machine
    reg [1:0] state;
    localparam IDLE = 0, ACS = 1, TRACE = 2, DONE = 3;

    // Traceback vars
    reg [7:0] tb_t;
    reg [M-1:0] tb_s;

    // Hamming distance
    function [1:0] ham;
        input [1:0] a, b;
        ham = ((a[0]^b[0]) ? 1 : 0) + ((a[1]^b[1]) ? 1 : 0);
    endfunction

    // Expected symbol
    function [1:0] exp_sym;
        input [M-1:0] st;
        input b;
        reg [K-1:0] r;
        begin
            r = {st, b};
            exp_sym = {^(r & G0), ^(r & G1)};
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            bank <= 0;
            t <= 0;
        end else begin
            case (state)
            IDLE: begin
                done <= 0;
                if (start) begin
                    // Initialize path metrics - state 0 has cost 0, all others infinite
                    // Do this explicitly for up to 16 states (K<=5)
                    pm[0][0] <= 0;
                    if (S > 1) pm[1][0] <= 16'hFFFF;
                    if (S > 2) pm[2][0] <= 16'hFFFF;
                    if (S > 3) pm[3][0] <= 16'hFFFF;
                    if (S > 4) pm[4][0] <= 16'hFFFF;
                    if (S > 5) pm[5][0] <= 16'hFFFF;
                    if (S > 6) pm[6][0] <= 16'hFFFF;
                    if (S > 7) pm[7][0] <= 16'hFFFF;
                    if (S > 8) pm[8][0] <= 16'hFFFF;
                    if (S > 9) pm[9][0] <= 16'hFFFF;
                    if (S > 10) pm[10][0] <= 16'hFFFF;
                    if (S > 11) pm[11][0] <= 16'hFFFF;
                    if (S > 12) pm[12][0] <= 16'hFFFF;
                    if (S > 13) pm[13][0] <= 16'hFFFF;
                    if (S > 14) pm[14][0] <= 16'hFFFF;
                    if (S > 15) pm[15][0] <= 16'hFFFF;
                    bank <= 0;
                    t <= 0;
                    state <= ACS;
                end
            end

            ACS: begin
                if (t < frame_len) begin
                    // Get received symbol
                    rx = syms_in[t];

                    // ACS for all states
                    for (s = 0; s < S; s = s + 1) begin
                        p0 = s >> 1;
                        p1 = p0 | (1 << (M-1));

                        // For LSB insertion: both predecessors use same bit (LSB of state s)
                        // Extract bit from integer s
                        rx_bit = s & 1;
                        exp0 = exp_sym(p0, rx_bit);
                        exp1 = exp_sym(p1, rx_bit);

                        bm0 = ham(rx, exp0);
                        bm1 = ham(rx, exp1);

                        m0 = pm[p0][bank] + bm0;
                        m1 = pm[p1][bank] + bm1;

                        if (m1 < m0) begin
                            pm[s][~bank] <= m1;
                            surv[t][s] <= 1;
                        end else begin
                            pm[s][~bank] <= m0;
                            surv[t][s] <= 0;
                        end
                    end

                    bank <= ~bank;
                    t <= t + 1;

                end else begin
                    // Find best ending state - explicit comparisons for up to 16 states
                    // This avoids for-loop issues in some simulators
                    min_metric = pm[0][bank];
                    min_state = 0;

                    if (S > 1 && pm[1][bank] < min_metric) begin
                        min_metric = pm[1][bank]; min_state = 1;
                    end
                    if (S > 2 && pm[2][bank] < min_metric) begin
                        min_metric = pm[2][bank]; min_state = 2;
                    end
                    if (S > 3 && pm[3][bank] < min_metric) begin
                        min_metric = pm[3][bank]; min_state = 3;
                    end
                    if (S > 4 && pm[4][bank] < min_metric) begin
                        min_metric = pm[4][bank]; min_state = 4;
                    end
                    if (S > 5 && pm[5][bank] < min_metric) begin
                        min_metric = pm[5][bank]; min_state = 5;
                    end
                    if (S > 6 && pm[6][bank] < min_metric) begin
                        min_metric = pm[6][bank]; min_state = 6;
                    end
                    if (S > 7 && pm[7][bank] < min_metric) begin
                        min_metric = pm[7][bank]; min_state = 7;
                    end
                    if (S > 8 && pm[8][bank] < min_metric) begin
                        min_metric = pm[8][bank]; min_state = 8;
                    end
                    if (S > 9 && pm[9][bank] < min_metric) begin
                        min_metric = pm[9][bank]; min_state = 9;
                    end
                    if (S > 10 && pm[10][bank] < min_metric) begin
                        min_metric = pm[10][bank]; min_state = 10;
                    end
                    if (S > 11 && pm[11][bank] < min_metric) begin
                        min_metric = pm[11][bank]; min_state = 11;
                    end
                    if (S > 12 && pm[12][bank] < min_metric) begin
                        min_metric = pm[12][bank]; min_state = 12;
                    end
                    if (S > 13 && pm[13][bank] < min_metric) begin
                        min_metric = pm[13][bank]; min_state = 13;
                    end
                    if (S > 14 && pm[14][bank] < min_metric) begin
                        min_metric = pm[14][bank]; min_state = 14;
                    end
                    if (S > 15 && pm[15][bank] < min_metric) begin
                        min_metric = pm[15][bank]; min_state = 15;
                    end

                    tb_s <= min_state;
                    tb_t <= frame_len - 1;
                    state <= TRACE;
                end
            end

            TRACE: begin
                // Trace back one bit
                if (tb_t < frame_len) begin  // Still have bits to trace
                    // For LSB insertion: decoded bit is the LSB of current state
                    bits_out[tb_t] <= tb_s[0];

                    // Previous state: base is always s>>1, but which predecessor?
                    // Survivor bit tells us: 0 = p0, 1 = p1
                    if (surv[tb_t][tb_s])
                        tb_s <= (tb_s >> 1) | (1 << (M-1));  // p1
                    else
                        tb_s <= tb_s >> 1;  // p0

                    if (tb_t == 0) begin
                        // Done tracing
                        out_len <= frame_len;
                        state <= DONE;
                        done <= 1;
                    end else begin
                        tb_t <= tb_t - 1;
                    end

                end else begin
                    // Should not get here
                    out_len <= frame_len;
                    state <= DONE;
                    done <= 1;
                end
            end

            DONE: begin
                if (!start)
                    state <= IDLE;
            end
            endcase
        end
    end

endmodule

`default_nettype wire
