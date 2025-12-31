/*
 * Tiny Tapeout Viterbi Decoder
 * K=3, G0=7 (111), G1=5 (101) - Rate 1/2 convolutional code
 * Synthesis-friendly: no unpacked arrays
 */

`default_nettype none

module tt_um_ashvin_viterbi (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Parameters
    localparam K = 3;
    localparam M = K - 1;           // 2
    localparam S = 1 << M;          // 4 states
    localparam MAX_FRAME = 64;
    localparam [K-1:0] G0 = 3'b111;
    localparam [K-1:0] G1 = 3'b101;

    // Interface:
    // ui_in[0]   = rx_valid (symbol input valid)
    // ui_in[2:1] = rx_sym (2-bit received symbol)
    // ui_in[3]   = start (begin decoding)
    // ui_in[4]   = read_ack (acknowledge output bit read)
    //
    // uo_out[0]  = rx_ready
    // uo_out[1]  = out_valid
    // uo_out[2]  = out_bit
    // uo_out[3]  = busy
    // uo_out[4]  = frame_done

    wire rst = ~rst_n;
    wire rx_valid = ui_in[0];
    wire [1:0] rx_sym = ui_in[2:1];
    wire start_cmd = ui_in[3];
    wire read_ack = ui_in[4];

    // State machine
    localparam [2:0] S_IDLE = 0, S_RECEIVE = 1, S_ACS = 2, S_TRACE = 3, S_OUTPUT = 4;
    reg [2:0] state;

    // Symbol buffer - packed as 2 bits per entry, 64 entries = 128 bits
    reg [127:0] sym_buf;
    reg [6:0] sym_count;
    reg [6:0] frame_len;

    // Path metrics - 4 states x 8 bits x 2 banks = 64 bits
    reg [7:0] pm0_0, pm1_0, pm2_0, pm3_0;  // Bank 0
    reg [7:0] pm0_1, pm1_1, pm2_1, pm3_1;  // Bank 1
    reg bank;

    // Survivor memory - 64 time steps x 4 states = 256 bits
    reg [255:0] surv;  // surv[t*4 + state]

    // Output buffer - 64 bits
    reg [63:0] out_buf;
    reg [6:0] out_idx;
    reg [6:0] out_len;
    reg frame_complete;

    // ACS state
    reg [6:0] acs_t;

    // Traceback state
    reg [6:0] tb_t;
    reg [1:0] tb_s;

    // Get symbol from buffer
    wire [1:0] current_sym = sym_buf[acs_t*2 +: 2];

    // Expected symbol calculation
    function [1:0] exp_sym;
        input [1:0] st;
        input b;
        reg [2:0] r;
        begin
            r = {st, b};
            exp_sym = {^(r & G0), ^(r & G1)};
        end
    endfunction

    // Hamming distance
    function [1:0] ham;
        input [1:0] a, b;
        begin
            ham = (a[0] ^ b[0]) + (a[1] ^ b[1]);
        end
    endfunction

    // Read path metric from current bank
    function [7:0] get_pm;
        input [1:0] st;
        input bnk;
        begin
            case ({bnk, st})
                3'b000: get_pm = pm0_0;
                3'b001: get_pm = pm1_0;
                3'b010: get_pm = pm2_0;
                3'b011: get_pm = pm3_0;
                3'b100: get_pm = pm0_1;
                3'b101: get_pm = pm1_1;
                3'b110: get_pm = pm2_1;
                3'b111: get_pm = pm3_1;
            endcase
        end
    endfunction

    // ACS computation wires for all 4 states
    wire [1:0] pred0_s0 = 2'd0;  // State 0: predecessors are 0,2
    wire [1:0] pred1_s0 = 2'd2;
    wire [1:0] pred0_s1 = 2'd0;  // State 1: predecessors are 0,2
    wire [1:0] pred1_s1 = 2'd2;
    wire [1:0] pred0_s2 = 2'd1;  // State 2: predecessors are 1,3
    wire [1:0] pred1_s2 = 2'd3;
    wire [1:0] pred0_s3 = 2'd1;  // State 3: predecessors are 1,3
    wire [1:0] pred1_s3 = 2'd3;

    // Expected symbols and branch metrics for state 0 (input bit = 0)
    wire [1:0] exp0_s0 = exp_sym(pred0_s0, 1'b0);
    wire [1:0] exp1_s0 = exp_sym(pred1_s0, 1'b0);
    wire [1:0] bm0_s0 = ham(current_sym, exp0_s0);
    wire [1:0] bm1_s0 = ham(current_sym, exp1_s0);
    wire [7:0] m0_s0 = get_pm(pred0_s0, bank) + bm0_s0;
    wire [7:0] m1_s0 = get_pm(pred1_s0, bank) + bm1_s0;
    wire sel_s0 = (m1_s0 < m0_s0);
    wire [7:0] new_pm_s0 = sel_s0 ? m1_s0 : m0_s0;

    // Expected symbols and branch metrics for state 1 (input bit = 1)
    wire [1:0] exp0_s1 = exp_sym(pred0_s1, 1'b1);
    wire [1:0] exp1_s1 = exp_sym(pred1_s1, 1'b1);
    wire [1:0] bm0_s1 = ham(current_sym, exp0_s1);
    wire [1:0] bm1_s1 = ham(current_sym, exp1_s1);
    wire [7:0] m0_s1 = get_pm(pred0_s1, bank) + bm0_s1;
    wire [7:0] m1_s1 = get_pm(pred1_s1, bank) + bm1_s1;
    wire sel_s1 = (m1_s1 < m0_s1);
    wire [7:0] new_pm_s1 = sel_s1 ? m1_s1 : m0_s1;

    // Expected symbols and branch metrics for state 2 (input bit = 0)
    wire [1:0] exp0_s2 = exp_sym(pred0_s2, 1'b0);
    wire [1:0] exp1_s2 = exp_sym(pred1_s2, 1'b0);
    wire [1:0] bm0_s2 = ham(current_sym, exp0_s2);
    wire [1:0] bm1_s2 = ham(current_sym, exp1_s2);
    wire [7:0] m0_s2 = get_pm(pred0_s2, bank) + bm0_s2;
    wire [7:0] m1_s2 = get_pm(pred1_s2, bank) + bm1_s2;
    wire sel_s2 = (m1_s2 < m0_s2);
    wire [7:0] new_pm_s2 = sel_s2 ? m1_s2 : m0_s2;

    // Expected symbols and branch metrics for state 3 (input bit = 1)
    wire [1:0] exp0_s3 = exp_sym(pred0_s3, 1'b1);
    wire [1:0] exp1_s3 = exp_sym(pred1_s3, 1'b1);
    wire [1:0] bm0_s3 = ham(current_sym, exp0_s3);
    wire [1:0] bm1_s3 = ham(current_sym, exp1_s3);
    wire [7:0] m0_s3 = get_pm(pred0_s3, bank) + bm0_s3;
    wire [7:0] m1_s3 = get_pm(pred1_s3, bank) + bm1_s3;
    wire sel_s3 = (m1_s3 < m0_s3);
    wire [7:0] new_pm_s3 = sel_s3 ? m1_s3 : m0_s3;

    // Find minimum PM for traceback start
    wire [7:0] final_pm0 = bank ? pm0_1 : pm0_0;
    wire [7:0] final_pm1 = bank ? pm1_1 : pm1_0;
    wire [7:0] final_pm2 = bank ? pm2_1 : pm2_0;
    wire [7:0] final_pm3 = bank ? pm3_1 : pm3_0;

    wire [7:0] min01 = (final_pm0 <= final_pm1) ? final_pm0 : final_pm1;
    wire [1:0] idx01 = (final_pm0 <= final_pm1) ? 2'd0 : 2'd1;
    wire [7:0] min23 = (final_pm2 <= final_pm3) ? final_pm2 : final_pm3;
    wire [1:0] idx23 = (final_pm2 <= final_pm3) ? 2'd2 : 2'd3;
    wire [1:0] best_state = (min01 <= min23) ? idx01 : idx23;

    // Get survivor bit
    wire surv_bit = surv[tb_t * 4 + tb_s];

    // Status signals
    wire rx_ready = (state == S_IDLE) || (state == S_RECEIVE);
    wire out_valid = (state == S_OUTPUT) && (out_idx < out_len);
    wire out_bit = out_valid ? out_buf[out_idx] : 1'b0;
    wire busy = (state == S_ACS) || (state == S_TRACE);

    assign uo_out[0] = rx_ready;
    assign uo_out[1] = out_valid;
    assign uo_out[2] = out_bit;
    assign uo_out[3] = busy;
    assign uo_out[4] = frame_complete;
    assign uo_out[7:5] = 3'b0;

    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;

    wire _unused = &{ena, uio_in, 1'b0};

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            sym_count <= 0;
            frame_len <= 0;
            bank <= 0;
            acs_t <= 0;
            tb_t <= 0;
            tb_s <= 0;
            out_idx <= 0;
            out_len <= 0;
            frame_complete <= 0;
            sym_buf <= 0;
            surv <= 0;
            out_buf <= 0;
            pm0_0 <= 0; pm1_0 <= 8'hFF; pm2_0 <= 8'hFF; pm3_0 <= 8'hFF;
            pm0_1 <= 8'hFF; pm1_1 <= 8'hFF; pm2_1 <= 8'hFF; pm3_1 <= 8'hFF;
        end else begin
            case (state)
                S_IDLE: begin
                    sym_count <= 0;
                    out_idx <= 0;
                    frame_complete <= 0;
                    // Reset PMs
                    pm0_0 <= 0; pm1_0 <= 8'hFF; pm2_0 <= 8'hFF; pm3_0 <= 8'hFF;
                    pm0_1 <= 8'hFF; pm1_1 <= 8'hFF; pm2_1 <= 8'hFF; pm3_1 <= 8'hFF;
                    bank <= 0;
                    if (rx_valid) begin
                        sym_buf[1:0] <= rx_sym;
                        sym_count <= 1;
                        state <= S_RECEIVE;
                    end
                end

                S_RECEIVE: begin
                    if (rx_valid && sym_count < MAX_FRAME) begin
                        sym_buf[sym_count*2 +: 2] <= rx_sym;
                        sym_count <= sym_count + 1;
                    end
                    if (start_cmd && sym_count > 0) begin
                        frame_len <= sym_count;
                        acs_t <= 0;
                        state <= S_ACS;
                    end
                end

                S_ACS: begin
                    if (acs_t < frame_len) begin
                        // Update survivor memory
                        surv[acs_t*4 + 0] <= sel_s0;
                        surv[acs_t*4 + 1] <= sel_s1;
                        surv[acs_t*4 + 2] <= sel_s2;
                        surv[acs_t*4 + 3] <= sel_s3;

                        // Update path metrics to opposite bank
                        if (bank == 0) begin
                            pm0_1 <= new_pm_s0;
                            pm1_1 <= new_pm_s1;
                            pm2_1 <= new_pm_s2;
                            pm3_1 <= new_pm_s3;
                        end else begin
                            pm0_0 <= new_pm_s0;
                            pm1_0 <= new_pm_s1;
                            pm2_0 <= new_pm_s2;
                            pm3_0 <= new_pm_s3;
                        end

                        bank <= ~bank;
                        acs_t <= acs_t + 1;
                    end else begin
                        // Start traceback
                        tb_s <= best_state;
                        tb_t <= frame_len - 1;
                        state <= S_TRACE;
                    end
                end

                S_TRACE: begin
                    // Decoded bit is LSB of current state
                    out_buf[tb_t] <= tb_s[0];

                    // Compute previous state
                    if (surv_bit)
                        tb_s <= {1'b1, tb_s[1]};  // Came from predecessor with MSB=1
                    else
                        tb_s <= {1'b0, tb_s[1]};  // Came from predecessor with MSB=0

                    if (tb_t == 0) begin
                        out_len <= frame_len;
                        state <= S_OUTPUT;
                    end else begin
                        tb_t <= tb_t - 1;
                    end
                end

                S_OUTPUT: begin
                    if (read_ack && out_idx < out_len) begin
                        out_idx <= out_idx + 1;
                    end
                    if (out_idx >= out_len) begin
                        frame_complete <= 1;
                    end
                    if (frame_complete && start_cmd) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
