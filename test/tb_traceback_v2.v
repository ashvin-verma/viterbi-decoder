`timescale 1ns/1ps

module tb_traceback_v2;

    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter T_BITS = 32;
    parameter CLOCK_PERIOD = 10;
    localparam TIME_W = (D > 1) ? $clog2(D) : 1;

    reg clk;
    reg rst;

    reg start;
    reg [TIME_W-1:0] start_time;
    reg [M-1:0]      start_state;
    reg              force_state0;

    wire [TIME_W-1:0] tb_time;
    wire [M-1:0]      tb_state;
    reg               tb_surv_bit;

    wire              busy;
    wire              dec_bit_valid;
    wire              dec_bit;

    traceback_v2 #(
        .K(K),
        .M(M),
        .D(D)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .start_time(start_time),
        .start_state(start_state),
        .force_state0(force_state0),
        .tb_time(tb_time),
        .tb_state(tb_state),
        .tb_surv_bit(tb_surv_bit),
        .busy(busy),
        .dec_bit_valid(dec_bit_valid),
        .dec_bit(dec_bit)
    );

    reg [S-1:0] mem [0:D-1];
    reg bit_pattern [0:T_BITS-1];

    integer fifo_head, fifo_tail, fifo_count;
    reg expected_fifo [0:T_BITS-1];
    integer errors;
    integer idx;
    integer wr_idx;
    reg [S-1:0] row;

    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

    always @(*) begin
        tb_surv_bit = mem[tb_time][tb_state];
    end

    task push_expected(input bit val);
        expected_fifo[fifo_tail] = val;
        fifo_tail = fifo_tail + 1;
        fifo_count = fifo_count + 1;
    endtask

    task pop_check(input bit actual);
        if (fifo_count == 0) begin
            $display("Ignoring warmup output %b", actual);
        end else begin
            bit exp_val = expected_fifo[fifo_head];
            fifo_head = fifo_head + 1;
            fifo_count = fifo_count - 1;
            if (actual !== exp_val) begin
                $display("Mismatch: got %b expected %b", actual, exp_val);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst = 1;
        start = 0;
        start_time = 0;
        start_state = 0;
        force_state0 = 1;
        fifo_head = 0;
        fifo_tail = 0;
        fifo_count = 0;
        errors = 0;
        wr_idx = 0;

        for (idx = 0; idx < D; idx = idx + 1) begin
            mem[idx] = {S{1'b0}};
        end

        for (idx = 0; idx < T_BITS; idx = idx + 1) begin
            bit_pattern[idx] = (idx % 2);
        end

        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        for (idx = 0; idx < T_BITS; idx = idx + 1) begin
            @(posedge clk);
            while (busy) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    pop_check(dec_bit);
                end
            end
            row = {S{bit_pattern[idx]}};
            mem[wr_idx] = row;
            wr_idx = (wr_idx == D-1) ? 0 : wr_idx + 1;
            start_time = (wr_idx == 0) ? (D - 1) : (wr_idx - 1);
            start_state = {M{1'b0}};
            start = 1;
            @(posedge clk);
            start = 0;

            if (idx >= D - 1) begin
                push_expected(bit_pattern[idx - (D - 1)]);
            end

            if (dec_bit_valid) begin
                pop_check(dec_bit);
            end
        end

        repeat (D + 4) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                pop_check(dec_bit);
            end
        end

        if (errors == 0 && fifo_count == 0) begin
            $display("*** TRACEBACK_V2 PASS ***");
        end else begin
            $display("*** TRACEBACK_V2 FAIL (errors=%0d fifo=%0d) ***", errors, fifo_count);
        end

        $finish;
    end

    initial begin
        #(CLOCK_PERIOD * 5000);
        $display("Timeout!");
        $finish;
    end

endmodule
