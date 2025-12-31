// Compare noise performance across K values
`timescale 1ns/1ps

module tb_noise_all_k();
    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    // Test parameters
    integer test_k, test_num, i, errors, sym_errors;
    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255], syms_clean [0:255];
    reg [7:0] test_pattern;
    integer seed;
    real error_prob, sym_ber, dec_ber;
    integer rand_val;

    // K=3 decoder
    reg rst3, start3;
    wire done3;
    wire [7:0] out_len3;
    wire bits_out3 [0:255];
    viterbi_simple_v2 #(.K(3), .G0(3'b111), .G1(3'b101)) dut3 (
        .clk(clk), .rst(rst3), .start(start3), .frame_len(frame_len),
        .syms_in(syms_in), .done(done3), .out_len(out_len3), .bits_out(bits_out3)
    );

    // K=4 decoder
    reg rst4, start4;
    wire done4;
    wire [7:0] out_len4;
    wire bits_out4 [0:255];
    viterbi_simple_v2 #(.K(4), .G0(4'b1111), .G1(4'b1101)) dut4 (
        .clk(clk), .rst(rst4), .start(start4), .frame_len(frame_len),
        .syms_in(syms_in), .done(done4), .out_len(out_len4), .bits_out(bits_out4)
    );

    // K=5 decoder
    reg rst5, start5;
    wire done5;
    wire [7:0] out_len5;
    wire bits_out5 [0:255];
    viterbi_simple_v2 #(.K(5), .G0(5'b11111), .G1(5'b11011)) dut5 (
        .clk(clk), .rst(rst5), .start(start5), .frame_len(frame_len),
        .syms_in(syms_in), .done(done5), .out_len(out_len5), .bits_out(bits_out5)
    );

    task test_decoder;
        input integer k_val;
        input real err_prob;
        output integer bit_errors;
        begin
            // Reset appropriate decoder
            if (k_val == 3) begin
                rst3 = 1; start3 = 0;
                #30; @(posedge clk); rst3 = 0; @(posedge clk);
                start3 = 1; @(posedge clk); #1; start3 = 0;
                i = 0;
                while (i < 300 && !done3) begin @(posedge clk); #1; i = i + 1; end
                // Count errors
                bit_errors = 0;
                for (i = 0; i < 64; i = i + 1)
                    if (bits_out3[i] !== test_pattern[i % 8])
                        bit_errors = bit_errors + 1;
            end else if (k_val == 4) begin
                rst4 = 1; start4 = 0;
                #30; @(posedge clk); rst4 = 0; @(posedge clk);
                start4 = 1; @(posedge clk); #1; start4 = 0;
                i = 0;
                while (i < 300 && !done4) begin @(posedge clk); #1; i = i + 1; end
                bit_errors = 0;
                for (i = 0; i < 64; i = i + 1)
                    if (bits_out4[i] !== test_pattern[i % 8])
                        bit_errors = bit_errors + 1;
            end else if (k_val == 5) begin
                rst5 = 1; start5 = 0;
                #30; @(posedge clk); rst5 = 0; @(posedge clk);
                start5 = 1; @(posedge clk); #1; start5 = 0;
                i = 0;
                while (i < 300 && !done5) begin @(posedge clk); #1; i = i + 1; end
                bit_errors = 0;
                for (i = 0; i < 64; i = i + 1)
                    if (bits_out5[i] !== test_pattern[i % 8])
                        bit_errors = bit_errors + 1;
            end
        end
    endtask

    task encode_and_add_noise;
        input integer k_val;
        input real err_prob;
        output integer sym_errs;
        reg [4:0] r;
        reg [3:0] st;
        begin
            // Encode
            st = 0;
            for (i = 0; i < 64; i = i + 1) begin
                if (k_val == 3) begin
                    r = {st[1:0], test_pattern[i % 8]};
                    syms_clean[i] = {^(r[2:0] & 3'b111), ^(r[2:0] & 3'b101)};
                    st = {st[0:0], test_pattern[i % 8]};
                end else if (k_val == 4) begin
                    r = {st[2:0], test_pattern[i % 8]};
                    syms_clean[i] = {^(r[3:0] & 4'b1111), ^(r[3:0] & 4'b1101)};
                    st = {st[1:0], test_pattern[i % 8]};
                end else if (k_val == 5) begin
                    r = {st[3:0], test_pattern[i % 8]};
                    syms_clean[i] = {^(r[4:0] & 5'b11111), ^(r[4:0] & 5'b11011)};
                    st = {st[2:0], test_pattern[i % 8]};
                end
            end

            // Add noise
            sym_errs = 0;
            for (i = 0; i < 64; i = i + 1) begin
                syms_in[i] = syms_clean[i];
                rand_val = $random(seed);
                if (((rand_val & 32'h7FFFFFFF) % 10000) < (err_prob * 10000)) begin
                    syms_in[i][0] = ~syms_in[i][0];
                    sym_errs = sym_errs + 1;
                end
                rand_val = $random(seed);
                if (((rand_val & 32'h7FFFFFFF) % 10000) < (err_prob * 10000)) begin
                    syms_in[i][1] = ~syms_in[i][1];
                    sym_errs = sym_errs + 1;
                end
            end
        end
    endtask

    initial begin
        $display("\n=== Noise Performance Comparison ===\n");

        seed = 99999;
        test_pattern = 8'b10110100;
        frame_len = 64;

        $display("Sym_BER | K=3 Dec_BER | K=4 Dec_BER | K=5 Dec_BER");
        $display("--------|-------------|-------------|------------");

        for (test_num = 0; test_num <= 8; test_num = test_num + 1) begin
            error_prob = test_num * 0.025;  // 0%, 2.5%, 5%, ..., 20%

            // Test K=3
            encode_and_add_noise(3, error_prob, sym_errors);
            sym_ber = (sym_errors * 100.0) / 128;
            test_decoder(3, error_prob, errors);
            dec_ber = (errors * 100.0) / 64;
            $write(" %5.1f%%  |   %5.1f%%    |", sym_ber, dec_ber);

            // Test K=4
            encode_and_add_noise(4, error_prob, sym_errors);
            test_decoder(4, error_prob, errors);
            dec_ber = (errors * 100.0) / 64;
            $write("   %5.1f%%    |", dec_ber);

            // Test K=5
            encode_and_add_noise(5, error_prob, sym_errors);
            test_decoder(5, error_prob, errors);
            dec_ber = (errors * 100.0) / 64;
            $display("   %5.1f%%", dec_ber);
        end

        $display("\n");
        $finish;
    end

endmodule
