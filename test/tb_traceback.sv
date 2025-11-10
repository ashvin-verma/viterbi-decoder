`timescale 1ns/1ps
`include "../src/traceback.v"

module tb_traceback;
    parameter K = 3;
    parameter M = K - 1;
    parameter S = (1 << M);
    parameter D = 6;
    parameter T = 48;  // Number of information bits
    parameter T_SYMS = 50;  // Total symbols including tail bits
    parameter TIME_W = (D > 1) ? $clog2(D) : 1;
    parameter EXPECTED_TOTAL = (T > (D - 1)) ? (T - (D - 1)) : 0;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg [TIME_W-1:0] wr_ptr;
    reg [M-1:0]      s_end;
    reg              force_state0 = 1'b0;

    wire [TIME_W-1:0] tb_time;
    wire [M-1:0]      tb_state;
    wire              tb_surv_bit;

    wire              dec_bit_valid;
    wire              dec_bit;

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

    reg [S-1:0]        mem [0:D-1];
    reg                wr_en;
    reg [S-1:0]        surv_row_drive;
    reg [TIME_W-1:0]   wr_ptr_reg;
    reg [M-1:0]        dest_state;
    reg [M-1:0]        pred_hint;
    integer            time_tag [0:D-1];

    assign wr_ptr = wr_ptr_reg;
    assign tb_surv_bit = mem[tb_time][tb_state];

    always #5 clk = ~clk;

    parameter TRACE_LAT = D + 3;  // D cycles for traceback + 1 for DECODE + 2 margin

    integer idx;
    initial begin : init_mem
        for (idx = 0; idx < D; idx = idx + 1) begin
            mem[idx] = '0;
            time_tag[idx] = -1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr_reg <= '0;
            for (idx = 0; idx < D; idx = idx + 1) begin
                mem[idx] <= '0;
                time_tag[idx] <= -1;
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

    reg   bit_hist   [0:T-1];
    reg [M-1:0] state_hist [0:T];

    initial begin
        for (idx = 0; idx < T; idx = idx + 1) begin
            bit_hist[idx] = (idx % 3 == 1);
        end
        state_hist[0] = '0;
        for (idx = 0; idx < T; idx = idx + 1) begin
            reg [M-1:0] next_state;
            next_state = state_hist[idx] >> 1;
            next_state[M-1] = bit_hist[idx];
            state_hist[idx + 1] = next_state;
        end
    end

    integer expected_idx = 0;
    integer bits_seen = 0;
    reg actual_log   [0:EXPECTED_TOTAL-1];
    reg expected_log [0:EXPECTED_TOTAL-1];
    integer mismatch_count = 0;
    integer extra_outputs = 0;

    always @(posedge clk) begin
        if (rst) begin
            expected_idx = 0;
            bits_seen = 0;
            mismatch_count = 0;
            extra_outputs = 0;
        end else if (dec_bit_valid) begin
            if (expected_idx < EXPECTED_TOTAL) begin
                actual_log[expected_idx] = dec_bit;
                // Traceback produces bits in REVERSE order (newest first)
                // decoded[0] corresponds to input[T-1], decoded[1] to input[T-2], etc.
                expected_log[expected_idx] = bit_hist[T - 1 - expected_idx];
                if (dec_bit !== bit_hist[T - 1 - expected_idx]) begin
                    mismatch_count++;
                    if (expected_idx < 5) begin
                        $display("DEBUG idx %0d: got %0b, expected %0b (from bit_hist[%0d]), last tb_state=%0d tb_time=%0d mem[]=%0b", 
                                expected_idx, dec_bit, bit_hist[T - 1 - expected_idx], T - 1 - expected_idx,
                                tb_state, tb_time, mem[tb_time]);
                    end
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
            $display("%0t : wr_en=%0b wr_ptr=%0d tb_fsm=%0d tb_time=%0d tb_state=%0d count=%0d s_end=%0d row=%b surv=%0b curr_st=%0b src_t=%0d dec_valid=%0b dec_bit=%0b", $time, wr_en, wr_ptr, dut.state, tb_time, tb_state, dut.tb_count, s_end, mem[tb_time], tb_surv_bit, dut.current_state, time_tag[tb_time], dec_bit_valid, dec_bit);
    end
`endif

    integer t;
    initial begin : drive_stim
        wr_en = 1'b0;
        surv_row_drive = '0;
        s_end = '0;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (t = 0; t < T_SYMS; t = t + 1) begin
            @(negedge clk);
            // Survivor memory from C-model golden reference
            // Pattern from test_traceback.c: 1111 at t>=3 && t%3==0, else 0000
            if (t >= 3 && t % 3 == 0) begin
                surv_row_drive = 4'b1111;
            end else begin
                surv_row_drive = 4'b0000;
            end
            if (t >= 44) begin
                $display("STIM: t=%0d wr_ptr=%0d surv_row=%0b", t, wr_ptr_reg, surv_row_drive);
            end
            
            dest_state = state_hist[t + 1];
            wr_en = 1'b1;
            s_end = state_hist[t + 1];
            force_state0 = 1'b1;
            time_tag[wr_ptr] = t;
`ifdef TRACEBACK_TB_DEBUG
            $display("WRITE t=%0d ptr=%0d row=%b s_end=%0d", t, wr_ptr, surv_row_drive, s_end);
`endif

            @(posedge clk);
            #1 wr_en = 1'b0;
            #1 force_state0 = 1'b0;

            if (t != T - 1) begin
                repeat (TRACE_LAT - 1) @(posedge clk);
            end
        end

        repeat (D + 6) @(posedge clk);

        if (expected_idx != EXPECTED_TOTAL) begin
            $display("TB: expected %0d outputs, captured %0d", EXPECTED_TOTAL, expected_idx);
            $finish;
        end

        if (mismatch_count != 0) begin
            $display("TB: %0d mismatches detected", mismatch_count);
            for (idx = 0; idx < EXPECTED_TOTAL; idx = idx + 1) begin
                if (actual_log[idx] !== expected_log[idx]) begin
                    $display("    idx %0d: expected %0b got %0b", idx, expected_log[idx], actual_log[idx]);
                end
            end
            $display("TB: traceback outputs did not match expected sequence");
            $finish;
        end

        if (extra_outputs != 0) begin
            $display("TB: observed %0d extra outputs beyond expected window", extra_outputs);
        end

        $display("traceback TB PASS (%0d outputs checked)", bits_seen);
        $finish;
    end
endmodule