`timescale 1ns/1ps
`include "../src/traceback.v"

module tb_traceback;
    localparam int K = 3;
    localparam int M = K - 1;
    localparam int S = (1 << M);
    localparam int D = 6;
    localparam int T = 48;
    localparam int TIME_W = (D > 1) ? $clog2(D) : 1;
    localparam int EXPECTED_TOTAL = (T > (D - 1)) ? (T - (D - 1)) : 0;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [TIME_W-1:0] wr_ptr;
    logic [M-1:0]      s_end;
    logic              force_state0 = 1'b0;

    logic [TIME_W-1:0] tb_time;
    logic [M-1:0]      tb_state;
    logic              tb_surv_bit;

    logic              dec_bit_valid;
    logic              dec_bit;

    traceback #(
        .M(M),
        .D(D)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_ptr(wr_ptr),
        .s_end(s_end),
        .force_state0(force_state0),
        .tb_time(tb_time),
        .tb_state(tb_state),
        .tb_surv_bit(tb_surv_bit),
        .dec_bit_valid(dec_bit_valid),
        .dec_bit(dec_bit)
    );

    logic [S-1:0]        mem [0:D-1];
    logic                wr_en;
    logic [S-1:0]        surv_row_drive;
    logic [TIME_W-1:0]   wr_ptr_reg;

    assign wr_ptr = wr_ptr_reg;
    assign tb_surv_bit = mem[tb_time][tb_state];

    always #5 clk = ~clk;

    localparam int TRACE_LAT = D + 2;

    initial begin : init_mem
        for (int idx = 0; idx < D; idx++) begin
            mem[idx] = '0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr_reg <= '0;
            for (int idx = 0; idx < D; idx++) begin
                mem[idx] <= '0;
            end
        end else if (wr_en) begin
            mem[wr_ptr_reg] <= surv_row_drive;
            if (wr_ptr_reg == TIME_W'(D - 1)) begin
                wr_ptr_reg <= '0;
            end else begin
                wr_ptr_reg <= wr_ptr_reg + 1'b1;
            end
        end
    end

    bit   bit_hist   [0:T-1];
    logic [M-1:0] state_hist [0:T];

    initial begin
        for (int idx = 0; idx < T; idx++) begin
            bit_hist[idx] = (idx % 3 == 1);
        end
        state_hist[0] = '0;
        for (int idx = 0; idx < T; idx++) begin
            logic [M-1:0] next_state;
            next_state = state_hist[idx] >> 1;
            next_state[M-1] = bit_hist[idx];
            state_hist[idx + 1] = next_state;
        end
    end

    int expected_idx = 0;
    int bits_seen = 0;
    bit actual_log   [0:EXPECTED_TOTAL-1];
    bit expected_log [0:EXPECTED_TOTAL-1];
    int mismatch_count = 0;
    int extra_outputs = 0;

    always @(posedge clk) begin
        if (rst) begin
            expected_idx = 0;
            bits_seen = 0;
            mismatch_count = 0;
            extra_outputs = 0;
        end else if (dec_bit_valid) begin
            if (expected_idx < EXPECTED_TOTAL) begin
                actual_log[expected_idx] = dec_bit;
                expected_log[expected_idx] = bit_hist[expected_idx];
                if (dec_bit !== bit_hist[expected_idx]) begin
                    mismatch_count++;
                end
                expected_idx++;
            end else begin
                extra_outputs++;
            end
            bits_seen++;
        end
    end

`ifdef TRACEBACK_TB_DEBUG
    always @(posedge clk) begin
            $display("%0t : wr_en=%0b wr_ptr=%0d tb_fsm=%0d tb_time=%0d tb_state=%0d count=%0d dec_valid=%0b dec_bit=%0b", $time, wr_en, wr_ptr, dut.tb_fsm, tb_time, tb_state, dut.tb_count, dec_bit_valid, dec_bit);
    end
`endif

    initial begin : drive_stim
        wr_en = 1'b0;
        surv_row_drive = '0;
        s_end = '0;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (int t = 0; t < T; t++) begin
            @(negedge clk);
            surv_row_drive = '0;
            surv_row_drive[state_hist[t + 1]] = bit_hist[t];
            wr_en = 1'b1;
            s_end = state_hist[t + 1];

            @(posedge clk);
            #1 wr_en = 1'b0;

            if (t != T - 1) begin
                repeat (TRACE_LAT - 1) @(posedge clk);
            end
        end

        repeat (D + 6) @(posedge clk);

        if (expected_idx != EXPECTED_TOTAL) begin
            $fatal(1, "TB: expected %0d outputs, captured %0d", EXPECTED_TOTAL, expected_idx);
        end

        if (mismatch_count != 0) begin
            $display("TB: %0d mismatches detected", mismatch_count);
            for (int idx = 0; idx < EXPECTED_TOTAL; idx++) begin
                if (actual_log[idx] !== expected_log[idx]) begin
                    $display("    idx %0d: expected %0b got %0b", idx, expected_log[idx], actual_log[idx]);
                end
            end
            $fatal(1, "TB: traceback outputs did not match expected sequence");
        end

        if (extra_outputs != 0) begin
            $display("TB: observed %0d extra outputs beyond expected window", extra_outputs);
        end

        $display("traceback TB PASS (%0d outputs checked)", bits_seen);
        $finish;
    end
endmodule
