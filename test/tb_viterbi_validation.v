// Validation test: Encode -> Add errors -> Decode -> Verify
`timescale 1ns/1ps

module tb_viterbi_validation();

    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 8;
    parameter WM = 6;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    parameter CLOCK_PERIOD = 10;

    reg clk;
    reg rst;
    reg rx_sym_valid;
    wire rx_sym_ready;
    reg [1:0] rx_sym;
    wire dec_bit_valid;
    wire dec_bit;
    reg force_state0;

    // Golden encoder for generating test data
    reg [M-1:0] enc_state;

    // Test data
    reg [7:0] test_data [0:15];
    integer i, j, k;
    integer bit_idx, sym_idx, dec_idx;
    reg [1:0] encoded_syms [0:255];
    reg decoded_bits [0:255];
    integer num_errors;
    integer num_decoded;

    tt_um_viterbi_core #(
        .K(K),
        .D(D),
        .Wm(WM),
        .G0_OCT(G0_OCT),
        .G1_OCT(G1_OCT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_sym_valid(rx_sym_valid),
        .rx_sym_ready(rx_sym_ready),
        .rx_sym(rx_sym),
        .dec_bit_valid(dec_bit_valid),
        .dec_bit(dec_bit),
        .force_state0(force_state0)
    );

    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

    // Encoder task - GOLDEN MODEL CONVENTION (LSB insertion)
    task encode_bit;
        input bit_in;
        input [M-1:0] state_in;
        output [1:0] symbol;
        output [M-1:0] state_out;
        reg [K-1:0] reg_val;
        reg c0, c1;
        begin
            // Golden model: reg = {state, bit} - bit at LSB
            reg_val = {state_in, bit_in};
            c0 = ^(reg_val & 3'b111);  // G0 = 7 octal = 111 binary
            c1 = ^(reg_val & 3'b101);  // G1 = 5 octal = 101 binary
            // LSB insertion: next = (state << 1) | bit
            state_out = {state_in[M-2:0], bit_in};
            symbol = {c0, c1};
        end
    endtask

    initial begin
        $display("\n========================================");
        $display("Viterbi Decoder Validation Test");
        $display("========================================");
        $display("K=%0d, G0=%o, G1=%o", K, G0_OCT, G1_OCT);

        // Initialize test data with pattern
        for (i = 0; i < 16; i = i + 1) begin
            test_data[i] = i[7:0];  // 0,1,2,3,...,15
        end

        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ========================================
        // TEST 1: Noiseless transmission
        // ========================================
        $display("\n--- TEST 1: Noiseless (should decode perfectly) ---");

        // Encode 32 bits
        enc_state = 0;
        sym_idx = 0;
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                bit_idx = i * 8 + j;
                encode_bit(test_data[i][j], enc_state, encoded_syms[sym_idx], enc_state);
                $display("Bit %2d: %b -> Symbol %2d: %b (state: %b)",
                         bit_idx, test_data[i][j], sym_idx, encoded_syms[sym_idx], enc_state);
                sym_idx = sym_idx + 1;
            end
        end

        // Send symbols to decoder
        dec_idx = 0;
        for (i = 0; i < sym_idx; i = i + 1) begin
            while (!rx_sym_ready) @(posedge clk);
            rx_sym = encoded_syms[i];
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;

            // Collect any output
            for (k = 0; k < 10; k = k + 1) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    decoded_bits[dec_idx] = dec_bit;
                    $display("  Decoded bit %2d: %b", dec_idx, dec_bit);
                    dec_idx = dec_idx + 1;
                end
            end
        end

        // Wait for remaining outputs
        for (i = 0; i < 500; i = i + 1) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                decoded_bits[dec_idx] = dec_bit;
                $display("  Decoded bit %2d: %b", dec_idx, dec_bit);
                dec_idx = dec_idx + 1;
            end
        end

        // Check results
        num_errors = 0;
        num_decoded = dec_idx;
        $display("\nDecoded %0d bits (sent %0d input bits)", num_decoded, 32);

        // Compare decoded output with input (skip first D bits for traceback delay)
        for (i = D; i < 32 && i < num_decoded; i = i + 1) begin
            j = i / 8;
            k = i % 8;
            if (decoded_bits[i] !== test_data[j][k]) begin
                $display("ERROR at bit %2d: expected %b, got %b", i, test_data[j][k], decoded_bits[i]);
                num_errors = num_errors + 1;
            end
        end

        if (num_errors == 0 && num_decoded >= 32) begin
            $display("✓ TEST 1 PASSED: Perfect noiseless decoding");
        end else begin
            $display("✗ TEST 1 FAILED: %0d errors, %0d bits decoded", num_errors, num_decoded);
        end

        // ========================================
        // TEST 2: Single bit error correction
        // ========================================
        $display("\n--- TEST 2: Single symbol error (should correct) ---");

        // Reset decoder
        rst = 1;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Flip one bit in symbol 10
        $display("Flipping bit 0 of symbol 10: %b -> %b", encoded_syms[10], encoded_syms[10] ^ 2'b01);
        encoded_syms[10] = encoded_syms[10] ^ 2'b01;

        // Send symbols to decoder
        dec_idx = 0;
        for (i = 0; i < sym_idx; i = i + 1) begin
            while (!rx_sym_ready) @(posedge clk);
            rx_sym = encoded_syms[i];
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;

            // Collect outputs
            for (k = 0; k < 10; k = k + 1) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    decoded_bits[dec_idx] = dec_bit;
                    dec_idx = dec_idx + 1;
                end
            end
        end

        // Wait for remaining outputs
        for (i = 0; i < 500; i = i + 1) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                decoded_bits[dec_idx] = dec_bit;
                dec_idx = dec_idx + 1;
            end
        end

        // Check results
        num_errors = 0;
        num_decoded = dec_idx;
        $display("\nDecoded %0d bits with 1 symbol error", num_decoded);

        for (i = D; i < 32 && i < num_decoded; i = i + 1) begin
            j = i / 8;
            k = i % 8;
            if (decoded_bits[i] !== test_data[j][k]) begin
                $display("ERROR at bit %2d: expected %b, got %b", i, test_data[j][k], decoded_bits[i]);
                num_errors = num_errors + 1;
            end
        end

        if (num_errors == 0) begin
            $display("✓ TEST 2 PASSED: Corrected single bit error");
        end else begin
            $display("✗ TEST 2 FAILED: %0d uncorrected errors", num_errors);
        end

        // Final summary
        $display("\n========================================");
        $display("Validation Summary");
        $display("========================================");
        $display("This decoder appears to be: %s",
                 (num_errors == 0) ? "WORKING" : "NOT WORKING");

        $finish;
    end

    // Timeout
    initial begin
        #50000000;
        $display("\n✗ TIMEOUT - Test did not complete");
        $finish;
    end

endmodule
