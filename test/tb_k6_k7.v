// Test K=6 and K=7 with universal decoder
`timescale 1ns/1ps

module tb_k6_k7();
    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    parameter K6 = 6;
    parameter K7 = 7;

    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255];

    // K=6 decoder (32 states)
    reg rst6, start6;
    wire done6;
    wire [7:0] out_len6;
    wire bits_out6 [0:255];
    viterbi_universal #(
        .K(6),
        .G0(6'b111111),  // G0=77 octal
        .G1(6'b101011)   // G1=53 octal
    ) dut6 (
        .clk(clk), .rst(rst6), .start(start6), .frame_len(frame_len),
        .syms_in(syms_in), .done(done6), .out_len(out_len6), .bits_out(bits_out6)
    );

    // K=7 decoder (64 states)
    reg rst7, start7;
    wire done7;
    wire [7:0] out_len7;
    wire bits_out7 [0:255];
    viterbi_universal #(
        .K(7),
        .G0(7'b1111001),  // G0=171 octal
        .G1(7'b1011011)   // G1=133 octal
    ) dut7 (
        .clk(clk), .rst(rst7), .start(start7), .frame_len(frame_len),
        .syms_in(syms_in), .done(done7), .out_len(out_len7), .bits_out(bits_out7)
    );

    integer i, j, errors, test_num;
    reg [7:0] test_pattern;
    reg [6:0] r;
    reg [5:0] st;

    task test_k_value;
        input integer k_val;
        input [7:0] pattern;
        input integer bit_pos;
        begin
            test_pattern = pattern;
            $display("\n=== Testing K=%0d (%0d states) ===", k_val, 1 << (k_val-1));
            $display("Pattern: Single '1' at bit %0d", bit_pos);

            // Encode
            st = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (k_val == 6) begin
                    r = {st[4:0], (i == bit_pos) ? 1'b1 : 1'b0};
                    syms_in[i] = {^(r[5:0] & 6'b111111), ^(r[5:0] & 6'b101011)};
                    st = {st[3:0], (i == bit_pos) ? 1'b1 : 1'b0};
                end else if (k_val == 7) begin
                    r = {st[5:0], (i == bit_pos) ? 1'b1 : 1'b0};
                    syms_in[i] = {^(r[6:0] & 7'b1111001), ^(r[6:0] & 7'b1011011)};
                    st = {st[4:0], (i == bit_pos) ? 1'b1 : 1'b0};
                end
            end
            frame_len = 32;

            // Reset and start
            if (k_val == 6) begin
                rst6 = 1; start6 = 0;
                #30; @(posedge clk); rst6 = 0; @(posedge clk);
                start6 = 1; @(posedge clk); #1; start6 = 0;

                // Wait
                i = 0;
                while (i < 300 && !done6) begin
                    @(posedge clk); #1; i = i + 1;
                end

                if (!done6) begin
                    $display("TIMEOUT at cycle %0d", i);
                    $finish;
                end

                $display("Completed at cycle %0d", i);

                // Check
                errors = 0;
                for (i = 0; i < 32; i = i + 1) begin
                    if ((i == bit_pos && !bits_out6[i]) || (i != bit_pos && bits_out6[i])) begin
                        if (errors < 5)
                            $display("  ERR bit[%0d]: exp=%b got=%b",
                                     i, (i==bit_pos), bits_out6[i]);
                        errors = errors + 1;
                    end
                end

            end else if (k_val == 7) begin
                rst7 = 1; start7 = 0;
                #30; @(posedge clk); rst7 = 0; @(posedge clk);
                start7 = 1; @(posedge clk); #1; start7 = 0;

                i = 0;
                while (i < 300 && !done7) begin
                    @(posedge clk); #1; i = i + 1;
                end

                if (!done7) begin
                    $display("TIMEOUT at cycle %0d", i);
                    $finish;
                end

                $display("Completed at cycle %0d", i);

                errors = 0;
                for (i = 0; i < 32; i = i + 1) begin
                    if ((i == bit_pos && !bits_out7[i]) || (i != bit_pos && bits_out7[i])) begin
                        if (errors < 5)
                            $display("  ERR bit[%0d]: exp=%b got=%b",
                                     i, (i==bit_pos), bits_out7[i]);
                        errors = errors + 1;
                    end
                end
            end

            if (errors == 0)
                $display("✓ PASS: All 32 bits correct for K=%0d!\n", k_val);
            else
                $display("✗ FAIL: %0d errors for K=%0d\n", errors, k_val);
        end
    endtask

    initial begin
        $display("\n=== K=6 and K=7 Universal Decoder Test ===");

        // Test K=6
        test_k_value(6, 8'b10101010, 16);

        // Test K=7
        test_k_value(7, 8'b11001100, 20);

        $display("=== All High-K Tests Complete ===\n");
        $finish;
    end

endmodule
