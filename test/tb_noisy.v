// Test Viterbi decoder with noisy channel
`timescale 1ns/1ps

module tb_noisy();
    parameter K = 3;
    parameter M = 2;
    parameter S = 4;

    reg clk, rst, start;
    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255];
    reg [1:0] syms_clean [0:255];
    wire done;
    wire [7:0] out_len;
    wire bits_out [0:255];

    viterbi_simple_v2 #(.K(3)) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .frame_len(frame_len),
        .syms_in(syms_in),
        .done(done),
        .out_len(out_len),
        .bits_out(bits_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer i, j, errors, sym_errors, test_num;
    integer total_errors, total_bits, total_sym_errors, total_syms;
    reg [K-1:0] r;
    reg [M-1:0] st;
    reg [7:0] test_pattern;
    integer seed;
    real error_prob;
    integer rand_val;

    initial begin
        $display("\n=== Noisy Channel Test (K=3) ===\n");

        seed = 12345;
        total_errors = 0;
        total_bits = 0;
        total_sym_errors = 0;
        total_syms = 0;

        // Test with different error probabilities
        for (test_num = 0; test_num < 4; test_num = test_num + 1) begin
            case (test_num)
                0: begin error_prob = 0.0; test_pattern = 8'b10101010; end
                1: begin error_prob = 0.05; test_pattern = 8'b11001100; end
                2: begin error_prob = 0.10; test_pattern = 8'b11110000; end
                3: begin error_prob = 0.15; test_pattern = 8'b01010101; end
            endcase

            $display("Test %0d: Pattern=%b, Symbol Error Prob=%.2f",
                     test_num, test_pattern, error_prob);

            // Encode clean symbols
            st = 0;
            for (i = 0; i < 32; i = i + 1) begin
                r = {st, test_pattern[i % 8]};
                syms_clean[i] = {^(r & 3'b111), ^(r & 3'b101)};
                st = {st[0], test_pattern[i % 8]};
            end
            frame_len = 32;

            // Add noise
            sym_errors = 0;
            for (i = 0; i < 32; i = i + 1) begin
                syms_in[i] = syms_clean[i];

                // Randomly flip each bit of the symbol
                rand_val = $random(seed);
                if (((rand_val & 32'hFFFF) % 10000) < (error_prob * 10000)) begin
                    syms_in[i][0] = ~syms_in[i][0];
                    sym_errors = sym_errors + 1;
                end

                rand_val = $random(seed);
                if (((rand_val & 32'hFFFF) % 10000) < (error_prob * 10000)) begin
                    syms_in[i][1] = ~syms_in[i][1];
                    sym_errors = sym_errors + 1;
                end
            end

            $display("  Injected %0d symbol bit errors", sym_errors);

            // Reset
            rst = 1; start = 0;
            #30;
            @(posedge clk);
            rst = 0;
            @(posedge clk);

            // Start decoder
            start = 1;
            @(posedge clk);
            #1;
            start = 0;

            // Wait
            i = 0;
            while (i < 200 && !done) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end

            if (!done) begin
                $display("  TIMEOUT!\n");
                $finish;
            end

            // Check bit errors
            errors = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (bits_out[i] !== test_pattern[i % 8]) begin
                    errors = errors + 1;
                end
            end

            total_errors = total_errors + errors;
            total_bits = total_bits + 32;
            total_sym_errors = total_sym_errors + sym_errors;
            total_syms = total_syms + 32 * 2;  // 2 bits per symbol

            $display("  Decoded bit errors: %0d/32 (%.1f%% BER)",
                     errors, (errors * 100.0) / 32);
            $display("  Symbol BER: %.1f%%, Decoded BER: %.1f%%\n",
                     (sym_errors * 100.0) / (32 * 2),
                     (errors * 100.0) / 32);
        end

        $display("=== Overall Statistics ===");
        $display("Total symbol bit errors: %0d/%0d (%.2f%%)",
                 total_sym_errors, total_syms,
                 (total_sym_errors * 100.0) / total_syms);
        $display("Total decoded bit errors: %0d/%0d (%.2f%%)",
                 total_errors, total_bits,
                 (total_errors * 100.0) / total_bits);
        $display("Error correction ratio: %.2fx\n",
                 (total_sym_errors * 1.0) / (total_errors > 0 ? total_errors : 1));

        $finish;
    end

endmodule
