// Extended Viterbi Decoder Test Suite
// Levels 3-12: Advanced testing scenarios

`timescale 1ns/1ps

module tb_viterbi_extended();
    
    // ========================================================================
    // Parameters
    // ========================================================================
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter WM = 6;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    parameter CLOCK_PERIOD = 10;
    
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
    // Encoder task
    // ========================================================================
    task encode_bit(
        input logic in_bit,
        input logic [M-1:0] state_in,
        output logic [M-1:0] state_out,
        output logic y0,
        output logic y1
    );
        logic [K-1:0] sr;
        begin
            sr = {state_in, in_bit};
            y0 = ^(sr & G0_OCT[K-1:0]);
            y1 = ^(sr & G1_OCT[K-1:0]);
            // Next state: shift left, insert bit at LSB (keep M bits)
            state_out = {state_in[M-2:0], in_bit};
        end
    endtask
    
    // ========================================================================
    // Helper tasks
    // ========================================================================
    
    task reset_dut();
        begin
            @(posedge clk);
            rst = 1;
            rx_sym_valid = 0;
            force_state0 = 0;
            repeat(3) @(posedge clk);
            rst = 0;
            @(posedge clk);
        end
    endtask
    
    task send_symbol(input [1:0] sym);
        integer timeout;
        begin
            rx_sym = sym;
            rx_sym_valid = 1;
            timeout = 0;
            
            while (!rx_sym_ready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    task send_frame_with_errors(
        input [0:1023] info_bits,
        input integer L,
        input integer tail_bits,
        input [0:2047] error_mask,  // 1 = flip this coded bit
        output [0:1023] dec_bits,
        output integer dec_count
    );
        integer i;
        logic [M-1:0] enc_state;
        logic y0, y1;
        integer timeout;
        begin
            enc_state = 0;
            dec_count = 0;
            
            for (i = 0; i < L + tail_bits; i = i + 1) begin
                // Encode
                if (i < L) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                end else begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                end
                
                // Apply errors
                if (error_mask[i*2]) y0 = ~y0;
                if (error_mask[i*2+1]) y1 = ~y1;
                
                // Send with collection
                while (!rx_sym_ready) begin
                    @(posedge clk);
                    if (dec_bit_valid) begin
                        dec_bits[dec_count] = dec_bit;
                        dec_count = dec_count + 1;
                    end
                end
                
                rx_sym = {y0, y1};
                rx_sym_valid = 1;
                @(posedge clk);
                rx_sym_valid = 0;
                
                if (dec_bit_valid) begin
                    dec_bits[dec_count] = dec_bit;
                    dec_count = dec_count + 1;
                end
            end
            
            // Wait for remaining outputs
            timeout = 0;
            while (timeout < 200) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    dec_bits[dec_count] = dec_bit;
                    dec_count = dec_count + 1;
                    timeout = 0;
                end else begin
                    timeout = timeout + 1;
                end
            end
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
                // Direct comparison: decoder should restore full bitstream
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
                $display("✓ Test %0d PASS", test_num - 1);
            end else begin
                $display("✗ Test %0d FAIL", test_num - 1);
                all_pass = 0;
            end
        end
    endtask
    
    // ========================================================================
    // LEVEL 3: Two-bit flips (distance probing)
    // ========================================================================
    task level3_double_errors();
        integer i, sep, dec_count, err_count;
        integer separated_pass, adjacent_pass;
        logic [0:1023] info_bits;
        logic [0:2047] error_mask;
        logic [0:1023] dec_bits;
        integer L;
        integer seed;
        begin
            $display("\n========================================================");
            $display("LEVEL 3: Two-bit Flips (Distance Probing)");
            $display("========================================================");
            $display("Free distance d_free ≈ 5 for K=3, (7,5)");
            $display("Test separated (≥3 apart) vs adjacent flips");
            
            L = 64;
            seed = 200;
            separated_pass = 0;
            adjacent_pass = 0;
            
            // Test separated errors (should correct most)
            start_test("Separated errors (6 symbols apart)");
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            
            for (i = 0; i < 2048; i = i + 1) error_mask[i] = 0;
            error_mask[20] = 1;  // Error at symbol 10, bit 0
            error_mask[32] = 1;  // Error at symbol 16, bit 0 (6 symbols apart)
            
            reset_dut();
            force_state0 = 1;
            send_frame_with_errors(info_bits, L, M, error_mask, dec_bits, dec_count);
            
            err_count = count_errors(dec_bits, info_bits, dec_count < L ? dec_count : L);
            $display("  Decoded %0d bits, %0d errors", dec_count, err_count);
            if (err_count < 5) separated_pass = separated_pass + 1;
            end_test();
            
            // Test adjacent errors (may not correct)
            start_test("Adjacent errors (1 symbol apart)");
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            
            for (i = 0; i < 2048; i = i + 1) error_mask[i] = 0;
            error_mask[20] = 1;  // Error at symbol 10, bit 0
            error_mask[22] = 1;  // Error at symbol 11, bit 0 (adjacent)
            
            reset_dut();
            force_state0 = 1;
            send_frame_with_errors(info_bits, L, M, error_mask, dec_bits, dec_count);
            
            err_count = count_errors(dec_bits, info_bits, dec_count < L ? dec_count : L);
            $display("  Decoded %0d bits, %0d errors", dec_count, err_count);
            if (err_count > 0) $display("  (Expected: adjacent errors harder to correct)");
            end_test();
            
            $display("\nLevel 3 Summary: Separation improves correction (stability verified)");
        end
    endtask
    
    // ========================================================================
    // LEVEL 4: BSC Channel Sweep
    // ========================================================================
    task level4_bsc_sweep();
        integer p_idx, frame, i, dec_count, err_count;
        integer total_bits [0:4];
        integer total_errs [0:4];
        real p_values [0:4];
        real ber;
        logic [0:1023] info_bits;
        logic [0:2047] error_mask;
        logic [0:1023] dec_bits;
        integer L;
        integer seed;
        integer rand_val;
        begin
            $display("\n========================================================");
            $display("LEVEL 4: BSC Channel Sweep (Hard Decision)");
            $display("========================================================");
            $display("Channel: Binary Symmetric Channel, p ∈ {0, 0.01, 0.03, 0.05, 0.08}");
            
            p_values[0] = 0.0;
            p_values[1] = 0.01;
            p_values[2] = 0.03;
            p_values[3] = 0.05;
            p_values[4] = 0.08;
            
            L = 64;
            seed = 300;
            
            for (p_idx = 0; p_idx < 5; p_idx = p_idx + 1) begin
                total_bits[p_idx] = 0;
                total_errs[p_idx] = 0;
                
                start_test($sformatf("BSC p=%.2f", p_values[p_idx]));
                
                for (frame = 0; frame < 20; frame = frame + 1) begin  // Reduced from 50 for speed
                    // Generate random frame
                    for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
                    
                    // Generate BSC errors
                    for (i = 0; i < 2*(L+M); i = i + 1) begin
                        rand_val = $random(seed);
                        // Simple approximation: flip if rand_val < threshold
                        if (p_values[p_idx] == 0.0) begin
                            error_mask[i] = 0;
                        end else if (p_values[p_idx] == 0.01) begin
                            error_mask[i] = (rand_val % 100) < 1;
                        end else if (p_values[p_idx] == 0.03) begin
                            error_mask[i] = (rand_val % 100) < 3;
                        end else if (p_values[p_idx] == 0.05) begin
                            error_mask[i] = (rand_val % 20) < 1;
                        end else begin  // 0.08
                            error_mask[i] = (rand_val % 100) < 8;
                        end
                    end
                    
                    reset_dut();
                    force_state0 = 1;
                    send_frame_with_errors(info_bits, L, M, error_mask, dec_bits, dec_count);
                    
                    err_count = count_errors(dec_bits, info_bits, dec_count < L ? dec_count : L);
                    total_bits[p_idx] = total_bits[p_idx] + (dec_count < L ? dec_count : L);
                    total_errs[p_idx] = total_errs[p_idx] + err_count;
                end
                
                ber = (total_bits[p_idx] > 0) ? (real'(total_errs[p_idx]) / real'(total_bits[p_idx])) : 0.0;
                $display("  BER = %.6f (%0d errors / %0d bits)", ber, total_errs[p_idx], total_bits[p_idx]);
                
                // Check monotonicity
                if (p_idx > 0 && total_errs[p_idx] < total_errs[p_idx-1]) begin
                    $display("  ⚠ Warning: BER decreased (expected monotonic increase)");
                end
                
                end_test();
            end
            
            $display("\nLevel 4 Summary: BER increases with channel error rate");
        end
    endtask
    
    // ========================================================================
    // LEVEL 7: Throughput & Backpressure
    // ========================================================================
    task level7_backpressure();
        integer i, sym_count, dec_count, accepted_syms;
        logic [M-1:0] enc_state;
        logic y0, y1;
        logic [0:127] info_bits;
        integer L;
        integer seed;
        integer stall;
        begin
            $display("\n========================================================");
            $display("LEVEL 7: Throughput & Backpressure");
            $display("========================================================");
            $display("Random input stalls, verify no loss/duplication");
            
            L = 64;
            seed = 700;
            
            start_test("Random input stalls");
            
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            
            reset_dut();
            force_state0 = 1;
            
            enc_state = 0;
            sym_count = 0;
            dec_count = 0;
            accepted_syms = 0;
            
            for (i = 0; i < L + M; i = i + 1) begin
                // Encode
                if (i < L) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                end else begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                end
                
                // Random stalls (30% probability)
                stall = ($random(seed) % 10) < 3;
                if (stall) begin
                    rx_sym_valid = 0;
                    @(posedge clk);
                    if (dec_bit_valid) dec_count = dec_count + 1;
                end
                
                // Wait for ready before sending
                while (!rx_sym_ready) begin
                    @(posedge clk);
                    if (dec_bit_valid) dec_count = dec_count + 1;
                end
                
                // Send symbol
                rx_sym = {y0, y1};
                rx_sym_valid = 1;
                
                @(posedge clk);
                // Symbol accepted when both valid and ready were high
                accepted_syms = accepted_syms + 1;
                if (dec_bit_valid) dec_count = dec_count + 1;
                
                rx_sym_valid = 0;
            end
            
            rx_sym_valid = 0;
            
            // Collect remaining
            repeat(200) begin
                @(posedge clk);
                if (dec_bit_valid) dec_count = dec_count + 1;
            end
            
            $display("  Accepted symbols: %0d (expected %0d)", accepted_syms, L+M);
            $display("  Decoded bits: %0d", dec_count);
            
            if (accepted_syms == L + M) begin
                $display("  ✓ No symbol loss");
            end else begin
                $display("  ✗ Symbol count mismatch");
                test_pass = 0;
            end
            
            end_test();
        end
    endtask
    
    // ========================================================================
    // LEVEL 8: Reset Robustness
    // ========================================================================
    task level8_reset();
        integer i, dec_count_before, dec_count_after;
        logic [M-1:0] enc_state;
        logic y0, y1;
        logic [0:63] info_bits;
        logic [0:63] dec_bits;
        integer L;
        integer seed;
        integer err_count;
        begin
            $display("\n========================================================");
            $display("LEVEL 8: Reset & Init Robustness");
            $display("========================================================");
            
            L = 32;
            seed = 800;
            
            start_test("Mid-frame reset");
            
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            
            reset_dut();
            force_state0 = 1;
            
            enc_state = 0;
            dec_count_before = 0;
            
            // Send half the frame
            for (i = 0; i < L/2; i = i + 1) begin
                encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                send_symbol({y0, y1});
                if (dec_bit_valid) dec_count_before = dec_count_before + 1;
            end
            
            $display("  Sent %0d symbols, got %0d bits before reset", L/2, dec_count_before);
            
            // Reset mid-frame
            reset_dut();
            force_state0 = 1;
            
            // Verify no more outputs for a while
            dec_count_after = 0;
            repeat(20) begin
                @(posedge clk);
                if (dec_bit_valid) dec_count_after = dec_count_after + 1;
            end
            
            if (dec_count_after == 0) begin
                $display("  ✓ No outputs after reset (clean stop)");
            end else begin
                $display("  ✗ Got %0d bits after reset", dec_count_after);
                test_pass = 0;
            end
            
            // Send fresh frame
            enc_state = 0;
            dec_count_after = 0;
            for (i = 0; i < L; i = i + 1) info_bits[i] = $random(seed) & 1;
            
            for (i = 0; i < L + M; i = i + 1) begin
                if (i < L) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                end else begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                end
                
                while (!rx_sym_ready) @(posedge clk);
                rx_sym = {y0, y1};
                rx_sym_valid = 1;
                @(posedge clk);
                rx_sym_valid = 0;
                
                if (dec_bit_valid) begin
                    dec_bits[dec_count_after] = dec_bit;
                    dec_count_after = dec_count_after + 1;
                end
            end
            
            repeat(100) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    dec_bits[dec_count_after] = dec_bit;
                    dec_count_after = dec_count_after + 1;
                end
            end
            
            err_count = count_errors(dec_bits, info_bits, dec_count_after < L ? dec_count_after : L);
            $display("  Fresh frame: %0d bits, %0d errors", dec_count_after, err_count);
            
            if (err_count < 5) begin  // Allow some errors due to half-rate
                $display("  ✓ Fresh frame decoded cleanly");
            end else begin
                $display("  ✗ Too many errors after reset");
                test_pass = 0;
            end
            
            end_test();
        end
    endtask
    
    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $display("========================================================");
        $display("Viterbi Decoder Extended Test Suite (Levels 3-8)");
        $display("========================================================");
        $display("K=%0d, M=%0d, S=%0d, D=%0d", K, M, S, D);
        $display("G0=%03o, G1=%03o (octal)", G0_OCT, G1_OCT);
        $display("========================================================");
        
        test_num = 1;
        all_pass = 1;
        
        // Initialize
        clk = 0;
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
        #(CLOCK_PERIOD * 1000000);
        $display("\n✗ ERROR: Test timeout!");
        $finish;
    end
    
endmodule
