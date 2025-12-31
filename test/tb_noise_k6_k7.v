// Noise test for K=6 and K=7
`timescale 1ns/1ps

module tb_noise_k6_k7();
    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255], syms_clean [0:255];

    // K=6 decoder
    reg rst6, start6;
    wire done6;
    wire [7:0] out_len6;
    wire bits_out6 [0:255];
    viterbi_universal #(.K(6), .G0(6'b111111), .G1(6'b101011)) dut6 (
        .clk(clk), .rst(rst6), .start(start6), .frame_len(frame_len),
        .syms_in(syms_in), .done(done6), .out_len(out_len6), .bits_out(bits_out6)
    );

    // K=7 decoder
    reg rst7, start7;
    wire done7;
    wire [7:0] out_len7;
    wire bits_out7 [0:255];
    viterbi_universal #(.K(7), .G0(7'b1111001), .G1(7'b1011011)) dut7 (
        .clk(clk), .rst(rst7), .start(start7), .frame_len(frame_len),
        .syms_in(syms_in), .done(done7), .out_len(out_len7), .bits_out(bits_out7)
    );

    integer i, errors, sym_errors, test_num;
    reg [7:0] test_pattern;
    reg [6:0] r;
    reg [5:0] st;
    integer seed;
    real error_prob, sym_ber, dec_ber;
    integer rand_val;

    task encode_and_noise;
        input integer k_val;
        input real err_prob;
        output integer sym_errs;
        begin
            st = 0;
            for (i = 0; i < 64; i = i + 1) begin
                if (k_val == 6) begin
                    r = {st[4:0], test_pattern[i % 8]};
                    syms_clean[i] = {^(r[5:0] & 6'b111111), ^(r[5:0] & 6'b101011)};
                    st = {st[3:0], test_pattern[i % 8]};
                end else if (k_val == 7) begin
                    r = {st[5:0], test_pattern[i % 8]};
                    syms_clean[i] = {^(r[6:0] & 7'b1111001), ^(r[6:0] & 7'b1011011)};
                    st = {st[4:0], test_pattern[i % 8]};
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

    task test_decoder;
        input integer k_val;
        output integer bit_errs;
        begin
            if (k_val == 6) begin
                rst6 = 1; start6 = 0;
                #30; @(posedge clk); rst6 = 0; @(posedge clk);
                start6 = 1; @(posedge clk); #1; start6 = 0;
                i = 0;
                while (i < 300 && !done6) begin @(posedge clk); #1; i = i + 1; end
                bit_errs = 0;
                for (i = 0; i < 64; i = i + 1)
                    if (bits_out6[i] !== test_pattern[i % 8])
                        bit_errs = bit_errs + 1;
            end else if (k_val == 7) begin
                rst7 = 1; start7 = 0;
                #30; @(posedge clk); rst7 = 0; @(posedge clk);
                start7 = 1; @(posedge clk); #1; start7 = 0;
                i = 0;
                while (i < 300 && !done7) begin @(posedge clk); #1; i = i + 1; end
                bit_errs = 0;
                for (i = 0; i < 64; i = i + 1)
                    if (bits_out7[i] !== test_pattern[i % 8])
                        bit_errs = bit_errs + 1;
            end
        end
    endtask

    initial begin
        $display("\n=== Noise Performance: K=6 and K=7 ===\n");

        seed = 77777;
        test_pattern = 8'b10110100;
        frame_len = 64;

        $display("Sym_BER | K=6 Dec_BER | K=7 Dec_BER | Improvement");
        $display("--------|-------------|-------------|------------");

        for (test_num = 0; test_num <= 8; test_num = test_num + 1) begin
            error_prob = test_num * 0.025;

            // Test K=6
            encode_and_noise(6, error_prob, sym_errors);
            sym_ber = (sym_errors * 100.0) / 128;
            test_decoder(6, errors);
            dec_ber = (errors * 100.0) / 64;
            $write(" %5.1f%%  |   %5.1f%%    |", sym_ber, dec_ber);

            // Test K=7
            encode_and_noise(7, error_prob, sym_errors);
            test_decoder(7, errors);
            dec_ber = (errors * 100.0) / 64;
            $write("   %5.1f%%    |", dec_ber);

            // Show improvement
            if (dec_ber > 0)
                $display("   %.1fx", sym_ber / dec_ber);
            else if (sym_ber > 0)
                $display("   Perfect");
            else
                $display("   ---");
        end

        $display("\n");
        $finish;
    end

endmodule
