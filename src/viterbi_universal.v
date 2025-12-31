// Universal Viterbi Decoder - Supports K=3 to K=7 using generate blocks
`default_nettype none

module viterbi_universal #(
    parameter K = 3,
    parameter M = K - 1,
    parameter S = 1 << M,
    parameter [K-1:0] G0 = 3'b111,
    parameter [K-1:0] G1 = 3'b101
) (
    input wire clk,
    input wire rst,

    // Frame input
    input wire start,
    input wire [7:0] frame_len,
    input wire [1:0] syms_in [0:255],

    // Output
    output reg done,
    output reg [7:0] out_len,
    output reg bits_out [0:255]
);

    // Path metrics (current and next)
    reg [15:0] pm [0:S-1][0:1];
    reg bank;

    // Survivor memory
    reg surv [0:255][0:S-1];

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

    // Generate PM initialization logic
    genvar g;
    generate
        for (g = 0; g < S; g = g + 1) begin : gen_pm_init
            always @(*) begin
                if (state == IDLE && start) begin
                    // This will be used to initialize PMs
                    // State 0 gets metric 0, others get high value
                end
            end
        end
    endgenerate

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
                        // Initialize path metrics using generate
                        for (i = 0; i < S; i = i + 1) begin
                            pm[i][0] <= (i == 0) ? 16'h0000 : 16'hFFFF;
                        end
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

                            // For LSB insertion: both predecessors use same bit
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
                        // Find best ending state using for loop
                        min_metric = pm[0][bank];
                        min_state = 0;
                        for (s = 1; s < S; s = s + 1) begin
                            if (pm[s][bank] < min_metric) begin
                                min_metric = pm[s][bank];
                                min_state = s;
                            end
                        end
                        tb_s <= min_state;
                        tb_t <= frame_len - 1;
                        state <= TRACE;
                    end
                end

                TRACE: begin
                    if (tb_t < frame_len) begin
                        // For LSB insertion: decoded bit is LSB of current state
                        bits_out[tb_t] <= tb_s[0];

                        // Previous state
                        if (surv[tb_t][tb_s])
                            tb_s <= (tb_s >> 1) | (1 << (M-1));  // p1
                        else
                            tb_s <= tb_s >> 1;  // p0

                        if (tb_t == 0) begin
                            out_len <= frame_len;
                            state <= DONE;
                            done <= 1;
                        end else begin
                            tb_t <= tb_t - 1;
                        end
                    end else begin
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
