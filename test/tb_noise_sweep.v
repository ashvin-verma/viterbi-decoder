// Sweep noise levels for different K values
`timescale 1ns/1ps

module tb_noise_sweep();
    parameter TEST_K = 3;
    parameter TEST_M = TEST_K - 1;
    parameter TEST_S = 1 << TEST_M;

    reg clk, rst, start;
    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255];
    reg [1:0] syms_clean [0:255];
    wire done;
    wire [7:0] out_len;
    wire bits_out [0:255];

    generate
        if (TEST_K == 3) begin : gen_k3
            viterbi_simple_v2 #(.K(3), .G0(3'b111), .G1(3'b101)) dut (
                .clk(clk), .rst(rst), .start(start), .frame_len(frame_len),
                .syms_in(syms_in), .done(done), .out_len(out_len), .bits_out(bits_out)
            );
        end else if (TEST_K == 4) begin : gen_k4
            viterbi_simple_v2 #(.K(4), .G0(4'b1111), .G1(4'b1101)) dut (
                .clk(clk), .rst(rst), .start(start), .frame_len(frame_len),
                .syms_in(syms_in), .done(done), .out_len(out_len), .bits_out(bits_out)
            );
        end else if (TEST_K == 5) begin : gen_k5
            viterbi_simple_v2 #(.K(5), .G0(5'b11111), .G1(5'b11011)) dut (
                .clk(clk), .rst(rst), .start(start), .frame_len(frame_len),
                .syms_in(syms_in), .done(done), .out_len(out_len), .bits_out(bits_out)
            );
        end
    endgenerate

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer i, errors, sym_errors, test_num;
    reg [TEST_K-1:0] r;
    reg [TEST_M-1:0] st;
    reg [7:0] test_pattern;
    integer seed;
    real error_prob;
    integer rand_val;
    real sym_ber, dec_ber;

    initial begin
        $display("\n=== Noise Sweep Test (K=%0d, %0d states) ===\n", TEST_K, TEST_S);
        $display("Sym_BER  Sym_Errs  Dec_BER  Dec_Errs  Gain");
        $display("-------  --------  -------  --------  ----");

        seed = 54321;
        test_pattern = 8'b10110100;  // Mixed pattern

        // Sweep from 0% to 20% symbol error rate
        for (test_num = 0; test_num <= 10; test_num = test_num + 1) begin
            error_prob = test_num * 0.02;  // 0%, 2%, 4%, ..., 20%

            // Encode clean symbols
            st = 0;
            for (i = 0; i < 64; i = i + 1) begin
                r = {st, test_pattern[i % 8]};
                if (TEST_K == 3)
                    syms_clean[i] = {^(r & 3'b111), ^(r & 3'b101)};
                else if (TEST_K == 4)
                    syms_clean[i] = {^(r & 4'b1111), ^(r & 4'b1101)};
                else if (TEST_K == 5)
                    syms_clean[i] = {^(r & 5'b11111), ^(r & 5'b11011)};
                st = {st[TEST_M-2:0], test_pattern[i % 8]};
            end
            frame_len = 64;

            // Add noise
            sym_errors = 0;
            for (i = 0; i < 64; i = i + 1) begin
                syms_in[i] = syms_clean[i];

                // Flip bit 0
                rand_val = $random(seed);
                if (((rand_val & 32'h7FFFFFFF) % 10000) < (error_prob * 10000)) begin
                    syms_in[i][0] = ~syms_in[i][0];
                    sym_errors = sym_errors + 1;
                end

                // Flip bit 1
                rand_val = $random(seed);
                if (((rand_val & 32'h7FFFFFFF) % 10000) < (error_prob * 10000)) begin
                    syms_in[i][1] = ~syms_in[i][1];
                    sym_errors = sym_errors + 1;
                end
            end

            // Reset and decode
            rst = 1; start = 0;
            #30;
            @(posedge clk);
            rst = 0;
            @(posedge clk);

            start = 1;
            @(posedge clk);
            #1;
            start = 0;

            // Wait
            i = 0;
            while (i < 300 && !done) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end

            if (!done) begin
                $display("TIMEOUT at error_prob=%.2f", error_prob);
                $finish;
            end

            // Check bit errors
            errors = 0;
            for (i = 0; i < 64; i = i + 1) begin
                if (bits_out[i] !== test_pattern[i % 8])
                    errors = errors + 1;
            end

            sym_ber = (sym_errors * 100.0) / 128;  // 64 symbols * 2 bits
            dec_ber = (errors * 100.0) / 64;       // 64 bits

            $display("%6.1f%%  %8d  %6.1f%%  %8d  %4.1fx",
                     sym_ber, sym_errors, dec_ber, errors,
                     sym_errors > 0 ? (sym_ber / (dec_ber > 0 ? dec_ber : 0.1)) : 0);
        end

        $display("\n");
        $finish;
    end

endmodule
