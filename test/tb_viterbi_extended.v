// Extended Viterbi Decoder Test Suite
// Tests: error correction, BSC sweep, backpressure, reset robustness
`timescale 1ns/1ps
`default_nettype none

module tb_viterbi_extended();

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter K = 5;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 24;
    parameter WM = 6;
    parameter G0_OCT = 8'o23;
    parameter G1_OCT = 8'o35;
    parameter CLOCK_PERIOD = 10;
    parameter FLUSH = D - 1;  // flush symbols after each frame

    // ========================================================================
    // DUT signals
    // ========================================================================
    reg clk;
    reg rst;
    reg rx_sym_valid;
    wire rx_sym_ready;
    reg [1:0] rx_sym;
    wire dec_bit_valid;
    wire dec_bit;
    reg force_state0;

    // ========================================================================
    // Test infrastructure
    // ========================================================================
    integer test_num;
    integer test_pass;
    integer all_pass;

    // Global decoded bit collector (always-block, never misses a pulse)
    reg [0:1023] g_dec_bits;
    integer g_dec_count;
    reg g_collecting;

    always @(posedge clk) begin
        if (g_collecting && dec_bit_valid && !rst) begin
            g_dec_bits[g_dec_count] = dec_bit;
            g_dec_count = g_dec_count + 1;
        end
    end

    // ========================================================================
    // DUT instantiation
    // ========================================================================
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

    // ========================================================================
    // Clock generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // Encoder
    // ========================================================================
    function automatic [1:0] encode_sym(
        input logic in_bit,
        input logic [M-1:0] state_in
    );
        logic [K-1:0] sr;
        begin
            sr = {state_in, in_bit};
            encode_sym[1] = ^(sr & G0_OCT[K-1:0]);
            encode_sym[0] = ^(sr & G1_OCT[K-1:0]);
        end
    endfunction

    function automatic [M-1:0] next_enc_state(
        input logic in_bit,
        input logic [M-1:0] state_in
    );
        next_enc_state = {state_in[M-2:0], in_bit};
    endfunction

    // ========================================================================
    // Helper tasks
    // ========================================================================

    task reset_dut();
        begin
            @(posedge clk);
            rst = 1;
            rx_sym_valid = 0;
            force_state0 = 1;
            g_collecting = 0;
            repeat(3) @(posedge clk);
            rst = 0;
            @(posedge clk);
        end
    endtask

    // Fixed send_symbol: clock-advance BEFORE checking ready
    // (avoids delta-cycle race with DUT's NBA state update)
    task send_symbol(input [1:0] sym);
        integer timeout;
        begin
            timeout = 0;
            @(posedge clk);
            while (!rx_sym_ready) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 300) begin
                    $display("ERROR: send_symbol timeout");
                    $finish;
                end
            end
            rx_sym = sym;
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask

    // Encode and send a frame: info bits + tail + flush
    // Returns via global g_dec_bits / g_dec_count
    task send_frame(
        input [0:1023] info_bits,
        input integer L,
        input [0:2047] error_mask  // 1 = flip this coded bit
    );
        integer i;
        logic [M-1:0] enc_state;
        logic [1:0] sym;
        begin
            // Reset collector
            g_dec_count = 0;
            g_dec_bits = '0;
            g_collecting = 1;

            enc_state = 0;

            // Send info bits + tail
            for (i = 0; i < L + M; i = i + 1) begin
                if (i < L)
                    sym = encode_sym(info_bits[i], enc_state);
                else
                    sym = encode_sym(1'b0, enc_state);

                if (i < L)
                    enc_state = next_enc_state(info_bits[i], enc_state);
                else
                    enc_state = next_enc_state(1'b0, enc_state);

                // Apply errors
                if (error_mask[i*2])   sym[1] = ~sym[1];
                if (error_mask[i*2+1]) sym[0] = ~sym[0];

                send_symbol(sym);
            end

            // Flush: D-1 zero symbols to push all info bits through traceback
            for (i = 0; i < FLUSH; i = i + 1) begin
                send_symbol(2'b00);
            end

            // Wait for remaining outputs
            repeat(100) @(posedge clk);
            g_collecting = 0;
        end
    endtask

    function integer count_errors(
        input [0:1023] actual,
        input [0:1023] expected,
        input integer count
    );
        integer i, errs;
        begin
            errs = 0;
            for (i = 0; i < count; i = i + 1) begin
                if (actual[i] !== expected[i]) errs = errs + 1;
            end
            count_errors = errs;
        end
    endfunction

    task start_test(input string name);
        begin
            $display("\n--- Test %0d: %s ---", test_num, name);
            test_pass = 1;
            test_num = test_num + 1;
        end
    endtask

    task end_test();
        begin
            if (test_pass) begin
                $display("PASS (Test %0d)", test_num - 1);
            end else begin
                $display("FAIL (Test %0d)", test_num - 1);
                all_pass = 0;
            end
        end
    endtask

    // ========================================================================
    // LEVEL 3: Two-bit flips (distance probing)
    // ========================================================================
    task level3_double_errors();
        integer err_count;
        logic [0:1023] info_bits;
        logic [0:2047] error_mask;
        integer L, i, seed;
        begin
            $display("\n========================================================");
            $display("LEVEL 3: Two-bit Flips (Distance Probing)");
            $display("========================================================");
            $display("K=%0d, d_free=7, corrects <=3 errors", K);

            L = 64;
            seed = 200;

            // Test separated errors (should correct)
            start_test("Separated errors (10 symbols apart)");
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            for (i = 0; i < 2048; i = i + 1) error_mask[i] = 0;
            error_mask[20] = 1;  // flip symbol 10, bit 0
            error_mask[40] = 1;  // flip symbol 20, bit 0

            reset_dut();
            send_frame(info_bits, L, error_mask);

            err_count = count_errors(g_dec_bits, info_bits, g_dec_count < L ? g_dec_count : L);
            $display("  Decoded %0d bits, %0d errors", g_dec_count, err_count);
            if (g_dec_count < L) begin
                $display("  FAIL: not enough decoded bits (%0d < %0d)", g_dec_count, L);
                test_pass = 0;
            end else if (err_count != 0) begin
                $display("  FAIL: expected 0 errors (d_free=7 handles 2 errors easily)");
                test_pass = 0;
            end
            end_test();

            // Test adjacent errors (harder but d_free=7 should still handle 2)
            start_test("Adjacent errors (1 symbol apart)");
            seed = 201;
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            for (i = 0; i < 2048; i = i + 1) error_mask[i] = 0;
            error_mask[20] = 1;  // flip symbol 10, bit 0
            error_mask[22] = 1;  // flip symbol 11, bit 0

            reset_dut();
            send_frame(info_bits, L, error_mask);

            err_count = count_errors(g_dec_bits, info_bits, g_dec_count < L ? g_dec_count : L);
            $display("  Decoded %0d bits, %0d errors", g_dec_count, err_count);
            if (g_dec_count < L) begin
                $display("  FAIL: not enough decoded bits");
                test_pass = 0;
            end else if (err_count != 0) begin
                $display("  FAIL: expected 0 errors (d_free=7 handles 2 errors)");
                test_pass = 0;
            end
            end_test();
        end
    endtask

    // ========================================================================
    // LEVEL 4: BSC Channel Sweep
    // ========================================================================
    task level4_bsc_sweep();
        integer p_idx, frame, i, err_count;
        integer total_bits [0:4];
        integer total_errs [0:4];
        integer p_thresholds [0:4];
        logic [0:1023] info_bits;
        logic [0:2047] error_mask;
        integer L, seed, rand_val;
        begin
            $display("\n========================================================");
            $display("LEVEL 4: BSC Channel Sweep");
            $display("========================================================");

            // Probability thresholds (out of 1000)
            p_thresholds[0] = 0;    // p=0.0
            p_thresholds[1] = 10;   // p=0.01
            p_thresholds[2] = 30;   // p=0.03
            p_thresholds[3] = 50;   // p=0.05
            p_thresholds[4] = 80;   // p=0.08

            L = 64;

            for (p_idx = 0; p_idx < 5; p_idx = p_idx + 1) begin
                total_bits[p_idx] = 0;
                total_errs[p_idx] = 0;
                seed = 300 + p_idx * 100;

                start_test($sformatf("BSC p=%0d/1000", p_thresholds[p_idx]));

                for (frame = 0; frame < 10; frame = frame + 1) begin
                    for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;

                    for (i = 0; i < 2*(L+M); i = i + 1) begin
                        rand_val = {$random(seed)} % 1000;  // unsigned modulo
                        error_mask[i] = (rand_val < p_thresholds[p_idx]) ? 1 : 0;
                    end
                    // Clear remaining error mask
                    for (i = 2*(L+M); i < 2048; i = i + 1) error_mask[i] = 0;

                    reset_dut();
                    send_frame(info_bits, L, error_mask);

                    err_count = count_errors(g_dec_bits, info_bits, g_dec_count < L ? g_dec_count : L);
                    total_bits[p_idx] = total_bits[p_idx] + (g_dec_count < L ? g_dec_count : L);
                    total_errs[p_idx] = total_errs[p_idx] + err_count;
                end

                $display("  BER = %0d / %0d bits", total_errs[p_idx], total_bits[p_idx]);

                // p=0.0 must have 0 errors (noiseless)
                if (p_thresholds[p_idx] == 0 && total_errs[p_idx] != 0) begin
                    $display("  FAIL: noiseless channel must have 0 errors");
                    test_pass = 0;
                end
                // All channels must produce enough bits
                if (total_bits[p_idx] < 10 * L) begin
                    $display("  FAIL: not enough decoded bits (%0d < %0d)", total_bits[p_idx], 10*L);
                    test_pass = 0;
                end
                end_test();
            end

            // Monotonicity check
            $display("\n  BER monotonicity check:");
            for (p_idx = 1; p_idx < 5; p_idx = p_idx + 1) begin
                if (total_errs[p_idx] < total_errs[p_idx-1] && total_errs[p_idx-1] > 0) begin
                    $display("    Warning: BER[%0d]=%0d < BER[%0d]=%0d (non-monotonic, may be statistical)",
                        p_idx, total_errs[p_idx], p_idx-1, total_errs[p_idx-1]);
                end
            end
        end
    endtask

    // ========================================================================
    // LEVEL 7: Throughput & Backpressure
    // ========================================================================
    task level7_backpressure();
        integer i, err_count;
        logic [M-1:0] enc_state;
        logic [1:0] pre_encoded [0:127]; // pre-computed symbols
        logic [0:1023] info_bits;  // must match count_errors parameter width
        integer L, seed, stall_seed;
        integer n_syms, accepted_syms;
        integer timeout, stall_len;
        begin
            $display("\n========================================================");
            $display("LEVEL 7: Throughput & Backpressure");
            $display("========================================================");

            L = 32;
            seed = 700;

            start_test("Random input stalls");

            // Pre-compute info bits
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;

            // Pre-encode all symbols (info + tail)
            enc_state = 0;
            n_syms = 0;
            for (i = 0; i < L + M; i = i + 1) begin
                if (i < L) begin
                    pre_encoded[n_syms] = encode_sym(info_bits[i], enc_state);
                    enc_state = next_enc_state(info_bits[i], enc_state);
                end else begin
                    pre_encoded[n_syms] = encode_sym(1'b0, enc_state);
                    enc_state = next_enc_state(1'b0, enc_state);
                end
                n_syms = n_syms + 1;
            end

            // Add flush symbols
            for (i = 0; i < FLUSH; i = i + 1) begin
                pre_encoded[n_syms] = 2'b00;
                n_syms = n_syms + 1;
            end

            // Send with random stalls
            reset_dut();
            g_dec_count = 0;
            g_dec_bits = '0;
            g_collecting = 1;

            stall_seed = 777;
            accepted_syms = 0;

            for (i = 0; i < n_syms; i = i + 1) begin
                // Random stalls (~30% chance, 1-5 cycle duration)
                if (({$random(stall_seed)} % 10) < 3) begin
                    rx_sym_valid = 0;
                    stall_len = 1 + ({$random(stall_seed)} % 5);
                    repeat(stall_len) @(posedge clk);
                end

                send_symbol(pre_encoded[i]);
                accepted_syms = accepted_syms + 1;
            end

            repeat(100) @(posedge clk);
            g_collecting = 0;

            $display("  Symbols: %0d sent, %0d accepted", n_syms, accepted_syms);
            $display("  Decoded bits: %0d", g_dec_count);

            if (accepted_syms != n_syms) begin
                $display("  FAIL: Symbol count mismatch (%0d != %0d)", accepted_syms, n_syms);
                test_pass = 0;
            end

            if (g_dec_count >= L) begin
                err_count = count_errors(g_dec_bits, info_bits, L);
                $display("  Decode errors: %0d/%0d", err_count, L);
                if (err_count != 0) begin
                    $display("  FAIL: noiseless backpressure test should have 0 errors");
                    test_pass = 0;
                end
            end else begin
                $display("  FAIL: not enough decoded bits (%0d < %0d)", g_dec_count, L);
                test_pass = 0;
            end

            end_test();
        end
    endtask

    // ========================================================================
    // LEVEL 8: Reset Robustness
    // ========================================================================
    task level8_reset();
        integer i, err_count;
        logic [M-1:0] enc_state;
        logic [1:0] sym;
        logic [0:1023] info_bits;
        logic [0:2047] no_errors;
        integer L, seed;
        begin
            $display("\n========================================================");
            $display("LEVEL 8: Reset Robustness");
            $display("========================================================");

            L = 32;
            seed = 800;
            for (i = 0; i < 2048; i = i + 1) no_errors[i] = 0;

            start_test("Mid-frame reset then fresh frame");

            // Generate and partially send a frame
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;

            reset_dut();
            enc_state = 0;
            for (i = 0; i < L/2; i = i + 1) begin
                sym = encode_sym(info_bits[i], enc_state);
                enc_state = next_enc_state(info_bits[i], enc_state);
                send_symbol(sym);
            end
            $display("  Sent %0d symbols, then resetting mid-frame", L/2);

            // Reset mid-frame
            reset_dut();

            // Verify no outputs for 20 cycles after reset
            g_dec_count = 0;
            g_collecting = 1;
            repeat(20) @(posedge clk);
            g_collecting = 0;

            if (g_dec_count != 0) begin
                $display("  FAIL: Got %0d bits after mid-frame reset (expected 0)", g_dec_count);
                test_pass = 0;
            end else begin
                $display("  No outputs after reset (clean stop)");
            end

            // Send a fresh, complete frame and verify it decodes correctly
            seed = 801;
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;

            reset_dut();
            send_frame(info_bits, L, no_errors);

            if (g_dec_count >= L) begin
                err_count = count_errors(g_dec_bits, info_bits, L);
                $display("  Fresh frame: %0d decoded bits, %0d errors", g_dec_count, err_count);
                if (err_count != 0) begin
                    $display("  FAIL: fresh frame after reset should decode cleanly");
                    test_pass = 0;
                end
            end else begin
                $display("  FAIL: not enough decoded bits after reset (%0d < %0d)", g_dec_count, L);
                test_pass = 0;
            end

            end_test();
        end
    endtask

    // ========================================================================
    // LEVEL 9: Expected failure (beyond correction capacity)
    // ========================================================================
    task level9_expected_failure();
        integer i, err_count;
        logic [0:1023] info_bits;
        logic [0:2047] error_mask;
        integer L, seed;
        begin
            $display("\n========================================================");
            $display("LEVEL 9: Beyond Correction Capacity (Expected Failure)");
            $display("========================================================");

            L = 64;
            seed = 900;

            start_test("6-bit burst should cause decode errors");
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            for (i = 0; i < 2048; i = i + 1) error_mask[i] = 0;

            // Flip both bits of 3 consecutive symbols (6 bit errors in burst)
            error_mask[20] = 1; error_mask[21] = 1;  // symbol 10
            error_mask[22] = 1; error_mask[23] = 1;  // symbol 11
            error_mask[24] = 1; error_mask[25] = 1;  // symbol 12

            reset_dut();
            send_frame(info_bits, L, error_mask);

            if (g_dec_count >= L) begin
                err_count = count_errors(g_dec_bits, info_bits, L);
                $display("  Decoded %0d bits, %0d errors", g_dec_count, err_count);
                if (err_count == 0) begin
                    $display("  FAIL: 6-bit burst should cause decode errors (d_free=7, t=3)");
                    test_pass = 0;
                end else begin
                    $display("  Correctly produced %0d errors (decoder limit demonstrated)", err_count);
                end
            end else begin
                $display("  FAIL: not enough decoded bits (%0d < %0d)", g_dec_count, L);
                test_pass = 0;
            end

            end_test();
        end
    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_viterbi_extended.vcd");
        $dumpvars(0, tb_viterbi_extended);

        $display("========================================================");
        $display("Viterbi Decoder Extended Test Suite");
        $display("========================================================");
        $display("K=%0d, M=%0d, S=%0d, D=%0d", K, M, S, D);
        $display("G0=%03o, G1=%03o (octal)", G0_OCT, G1_OCT);
        $display("========================================================");

        test_num = 1;
        all_pass = 1;
        g_collecting = 0;

        // Initialize
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // Run test levels
        level3_double_errors();
        level4_bsc_sweep();
        level7_backpressure();
        level8_reset();
        level9_expected_failure();

        // Final summary
        $display("\n========================================================");
        $display("EXTENDED TEST SUITE COMPLETE");
        $display("========================================================");

        if (all_pass) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end

        $display("========================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLOCK_PERIOD * 5000000);
        $display("\nERROR: Test timeout!");
        $finish;
    end

endmodule

`default_nettype wire
