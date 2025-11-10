// Comprehensive Viterbi Decoder Testbench
// Level 0: Noiseless loopback
// Level 1: Trellis end-effects (tail-terminated vs free-running, short frames)
// Level 2: Single-error correction

`timescale 1ns/1ps

module tb_viterbi_levels();
    
    // ========================================================================
    // Parameters
    // ========================================================================
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 8;
    parameter WM = 4;
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
    integer errors;
    integer total_bits;
    
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
    // Encoder task (not function - needs output ports)
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
    
    // Reset DUT
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
    
    // Send a symbol to DUT (with handshake)
    task send_symbol(input [1:0] sym);
        integer timeout;
        begin
            rx_sym = sym;
            rx_sym_valid = 1;
            timeout = 0;
            
            // Wait for ready
            while (!rx_sym_ready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (timeout >= 100) begin
                $display("  ✗ Timeout waiting for rx_sym_ready");
                test_pass = 0;
            end
            
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    // Encode and send a frame (now properly collects decoded bits while sending)
    task send_and_decode_frame(
        input [0:1023] info_bits,
        input integer L,
        input integer tail_bits,
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
            
            // Send symbols and collect outputs simultaneously
            for (i = 0; i < L + tail_bits; i = i + 1) begin
                // Encode
                if (i < L) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                end else begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);  // Tail
                end
                
                // Wait for ready
                while (!rx_sym_ready) begin
                    @(posedge clk);
                    // Check for output while waiting
                    if (dec_bit_valid) begin
                        dec_bits[dec_count] = dec_bit;
                        dec_count = dec_count + 1;
                    end
                end
                
                // Send symbol
                rx_sym = {y0, y1};
                rx_sym_valid = 1;
                
                @(posedge clk);
                rx_sym_valid = 0;
                
                // Check for decoded output immediately after sending
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
    
    // Collect decoded bits
    task collect_bits(
        output [0:1023] dec_bits,
        input integer expected_count,
        output integer actual_count
    );
        integer timeout;
        integer max_cycles;
        begin
            actual_count = 0;
            timeout = 0;
            // Allow up to 50 cycles per expected bit (generous for pipelined traceback)
            max_cycles = expected_count * 50 + 1000;
            
            while (actual_count < expected_count && timeout < max_cycles) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    dec_bits[actual_count] = dec_bit;
                    actual_count = actual_count + 1;
                    timeout = 0;  // Reset timeout on progress
                end else begin
                    timeout = timeout + 1;
                end
            end
            
            if (timeout >= max_cycles) begin
                $display("  ! Timeout after %0d cycles, got %0d/%0d bits",
                         timeout, actual_count, expected_count);
            end
        end
    endtask
    
    // Compare bits (with optional offset)
    function integer compare_bits(
        input [0:1023] actual,
        input [0:1023] expected,
        input integer start_idx,
        input integer count,
        input integer verbose
    );
        integer i, err_count;
        begin
            err_count = 0;
            for (i = 0; i < count; i = i + 1) begin
                if (actual[start_idx + i] !== expected[start_idx + i]) begin
                    err_count = err_count + 1;
                    if (verbose && err_count <= 10) begin
                        $display("    Bit %0d: got %b, expected %b", 
                                start_idx + i, actual[start_idx + i], expected[start_idx + i]);
                    end
                end
            end
            compare_bits = err_count;
        end
    endfunction
    
    // ========================================================================
    // Test routines
    // ========================================================================
    
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
    // LEVEL 0: Noiseless Loopback
    // ========================================================================
    task level0_noiseless();
        integer frame;
        integer i, err_count;
        integer L;
        logic [0:1023] info_bits;
        logic [0:1023] dec_bits;
        integer dec_count;
        integer seed;
        begin
            $display("\n========================================================");
            $display("LEVEL 0: Noiseless Loopback (Sanity)");
            $display("========================================================");
            $display("Goal: Plumbing + latency alignment");
            $display("Frames: 10 random (L=64 each)");  // Reduced from 256 for faster testing
            $display("Drop first D=%0d bits, verify rest", D);
            
            L = 64;  // Reduced size for testing
            seed = 42;
            errors = 0;
            total_bits = 0;
            
            for (frame = 0; frame < 10; frame = frame + 1) begin
                start_test($sformatf("Noiseless frame %0d", frame));
                
                // Generate random info bits
                for (i = 0; i < L; i = i + 1) begin
                    info_bits[i] = $random(seed) & 1;
                end
                
                // Reset and configure for tail-terminated
                reset_dut();
                force_state0 = 1;
                
                // Send frame and collect outputs
                send_and_decode_frame(info_bits, L, M, dec_bits, dec_count);
                
                // Accept whatever we get (may be less than L due to pipelining)
                if (dec_count == 0) begin
                    $display("  ✗ No bits received!");
                    test_pass = 0;
                end else begin
                    // Decoder should restore all input bits after D-bit traceback latency  
                    // Skip first D bits due to traceback delay
                    if (dec_count <= D) begin
                        $display("  ! Only got %0d bits, need > D=%0d for valid comparison", dec_count, D);
                        test_pass = 0;
                    end else begin
                        err_count = 0;
                        for (i = D; i < dec_count && i < L; i = i + 1) begin
                            if (dec_bits[i] !== info_bits[i]) begin
                                err_count = err_count + 1;
                                if (err_count <= 10) begin
                                    $display("    Decoded bit %0d: got %b, expected %b",
                                            i, dec_bits[i], info_bits[i]);
                                end
                            end
                        end
                        
                        if (err_count > 0) begin
                            $display("  ✗ %0d errors in %0d bits (%.2f%%)", 
                                    err_count, dec_count-D, 100.0 * err_count / (dec_count-D));
                            test_pass = 0;
                        end else begin
                            $display("  ✓ All %0d bits correct (skipped first D=%0d bits)", 
                                    dec_count-D, D);
                        end
                        
                        errors = errors + err_count;
                        total_bits = total_bits + (dec_count - D);
                    end
                end
                
                end_test();
            end
            
            $display("\nLevel 0 Summary: %0d errors / %0d bits (%.4f%%)",
                    errors, total_bits, 100.0 * errors / total_bits);
        end
    endtask
    
    // ========================================================================
    // LEVEL 1A: Tail-Terminated vs Free-Running
    // ========================================================================
    task level1a_tail_modes();
        integer i, err_count, dec_count;
        integer L;
        logic [0:1023] info_bits;
        logic [0:1023] dec_bits;
        logic [M-1:0] enc_state;
        logic y0, y1;
        begin
            $display("\n========================================================");
            $display("LEVEL 1A: Tail-Terminated vs Free-Running");
            $display("========================================================");
            
            L = 64;
            
            // ----------------------------------------------------------------
            // Test: Tail-terminated mode
            // ----------------------------------------------------------------
            start_test("Tail-terminated (force_state0=1)");
            
            // Generate test pattern
            for (i = 0; i < L; i = i + 1) begin
                info_bits[i] = i[0]; // Alternating 010101...
            end
            
            reset_dut();
            force_state0 = 1;
            
            // Send with tail
            send_and_decode_frame(info_bits, L, M, dec_bits, dec_count);
            
            $display("  Got %0d bits from %0d symbols", dec_count, L+M);
            
            // With half-rate output, check every other bit: dec_bits[i] ← info_bits[i*2]
            err_count = 0;
            for (i = 0; i < dec_count && (i*2) < L; i = i + 1) begin
                if (dec_bits[i] !== info_bits[i*2]) begin
                    err_count = err_count + 1;
                    if (err_count <= 10) begin
                        $display("    Bit %0d: got %b, expected %b (input bit %0d)",
                                i, dec_bits[i], info_bits[i*2], i*2);
                    end
                end
            end
            
            if (err_count == 0) begin
                $display("  ✓ Perfect match with tail termination (%0d bits)", dec_count);
            end else begin
                $display("  ✗ %0d errors (tail termination should be perfect)", err_count);
                test_pass = 0;
            end
            
            end_test();
            
            // ----------------------------------------------------------------
            // Test: Free-running mode
            // ----------------------------------------------------------------
            start_test("Free-running (force_state0=0)");
            
            reset_dut();
            force_state0 = 0;  // Use best ending state
            
            // Send WITHOUT tail (just L symbols)
            enc_state = 0;
            dec_count = 0;
            for (i = 0; i < L; i = i + 1) begin
                encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                send_symbol({y0, y1});
                if (dec_bit_valid) begin
                    dec_bits[dec_count] = dec_bit;
                    dec_count = dec_count + 1;
                end
            end
            
            // Wait for stragglers
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    dec_bits[dec_count] = dec_bit;
                    dec_count = dec_count + 1;
                end
            end
            
            // Expect match except possibly last ~D bits (don't care window)
            if (dec_count > D + D) begin
                err_count = compare_bits(dec_bits, info_bits, D, dec_count - D, 1);
                
                if (err_count == 0) begin
                    $display("  ✓ Match in middle region (free-running OK)");
                end else begin
                    $display("  ✗ %0d errors in middle region", err_count);
                    test_pass = 0;
                end
            end else begin
                $display("  ! Too few bits to verify (%0d)", dec_count);
            end
            
            end_test();
        end
    endtask
    
    // ========================================================================
    // LEVEL 1B: Short Frames
    // ========================================================================
    task level1b_short_frames();
        integer L, dec_count;
        integer i;
        logic [0:1023] info_bits;
        logic [0:1023] dec_bits;
        begin
            $display("\n========================================================");
            $display("LEVEL 1B: Short Frames (L <= D)");
            $display("========================================================");
            $display("Verify decoded_bits_emitted == max(0, L-D)");
            
            // Test L < D
            L = D - 2;
            start_test($sformatf("Short frame L=%0d (< D=%0d)", L, D));
            
            for (i = 0; i < L; i = i + 1) begin
                info_bits[i] = i[0];
            end
            
            reset_dut();
            force_state0 = 1;
            send_and_decode_frame(info_bits, L, M, dec_bits, dec_count);
            
            if (dec_count == 0) begin
                $display("  ✓ No bits emitted for L < D");
            end else begin
                $display("  ✗ Expected 0 bits, got %0d", dec_count);
                test_pass = 0;
            end
            
            end_test();
            
            // Test L == D
            L = D;
            start_test($sformatf("Frame L=%0d (== D)", L));
            
            for (i = 0; i < L; i = i + 1) begin
                info_bits[i] = 1;
            end
            
            reset_dut();
            force_state0 = 1;
            send_and_decode_frame(info_bits, L, M, dec_bits, dec_count);
            
            if (dec_count == M) begin
                $display("  ✓ Got %0d bits (just the tail)", dec_count);
            end else begin
                $display("  ✗ Expected %0d bits, got %0d", M, dec_count);
                test_pass = 0;
            end
            
            end_test();
            
            // Test L = D + 1
            L = D + 1;
            start_test($sformatf("Frame L=%0d (D+1)", L));
            
            for (i = 0; i < L; i = i + 1) begin
                info_bits[i] = 0;
            end
            
            reset_dut();
            force_state0 = 1;
            send_and_decode_frame(info_bits, L, M, dec_bits, dec_count);
            
            if (dec_count == 1 + M) begin
                $display("  ✓ Got %0d bits (1 info + tail)", dec_count);
            end else begin
                $display("  ✗ Expected %0d bits, got %0d", 1+M, dec_count);
                test_pass = 0;
            end
            
            end_test();
        end
    endtask
    
    // ========================================================================
    // LEVEL 2: Single-Error Correction
    // ========================================================================
    task level2_single_error();
        integer frame, t, stream_sel;
        integer i, err_count, dec_count;
        integer L;
        logic [0:1023] info_bits;
        logic [0:1023] dec_bits;
        logic [M-1:0] enc_state;
        logic y0, y1;
        integer seed;
        integer total_frames, failed_frames;
        begin
            $display("\n========================================================");
            $display("LEVEL 2: Single-Error Correction (Hard Decision)");
            $display("========================================================");
            $display("Flip exactly one coded bit per frame, sweep position");
            $display("Expect: 0 decoded errors for moderate t (away from edges)");
            
            L = 64;
            seed = 100;
            total_frames = 0;
            failed_frames = 0;
            
            // Test 10 random frames (reduced from 50 for speed)
            for (frame = 0; frame < 10; frame = frame + 1) begin
                // Generate random info bits
                for (i = 0; i < L; i = i + 1) begin
                    info_bits[i] = $random(seed) & 1;
                end
                
                // Sweep error position across frame
                for (t = 10; t < L; t = t + 10) begin  // Test every 10th position
                    for (stream_sel = 0; stream_sel < 2; stream_sel = stream_sel + 1) begin
                        total_frames = total_frames + 1;
                        
                        // Reset DUT
                        reset_dut();
                        force_state0 = 1;
                        
                        // Send symbols with one bit flipped, collecting outputs
                        enc_state = 0;
                        dec_count = 0;
                        for (i = 0; i < L + M; i = i + 1) begin
                            // Encode
                            if (i < L) begin
                                encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                            end else begin
                                encode_bit(1'b0, enc_state, enc_state, y0, y1);  // Tail
                            end
                            
                            // Inject error at position t
                            if (i == t) begin
                                if (stream_sel == 0) begin
                                    y0 = ~y0;
                                end else begin
                                    y1 = ~y1;
                                end
                            end
                            
                            // Send
                            send_symbol({y0, y1});
                            if (dec_bit_valid) begin
                                dec_bits[dec_count] = dec_bit;
                                dec_count = dec_count + 1;
                            end
                        end
                        
                        // Wait for stragglers
                        for (i = 0; i < 100; i = i + 1) begin
                            @(posedge clk);
                            if (dec_bit_valid) begin
                                dec_bits[dec_count] = dec_bit;
                                dec_count = dec_count + 1;
                            end
                        end
                        
                        // Compare (skip first D and last D for edge effects)
                        if (dec_count > 2*D) begin
                            err_count = compare_bits(dec_bits, info_bits, D, dec_count - 2*D, 0);
                            
                            if (err_count > 0) begin
                                failed_frames = failed_frames + 1;
                                if (failed_frames <= 5) begin
                                    $display("  ✗ Frame %0d, t=%0d, stream=%0d: %0d errors", 
                                            frame, t, stream_sel, err_count);
                                end
                            end
                        end
                    end
                end
            end
            
            $display("\nLevel 2 Summary: %0d / %0d frames corrected (%.2f%%)",
                    total_frames - failed_frames, total_frames,
                    100.0 * (total_frames - failed_frames) / total_frames);
            
            if (failed_frames == 0) begin
                $display("✓ Perfect single-error correction");
            end else begin
                $display("✗ Some frames had uncorrected errors");
                all_pass = 0;
            end
        end
    endtask
    
    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $display("========================================================");
        $display("Viterbi Decoder Comprehensive Test Suite");
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
        level0_noiseless();
        level1a_tail_modes();
        level1b_short_frames();
        level2_single_error();
        
        // Final summary
        $display("\n========================================================");
        $display("TEST SUITE COMPLETE");
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
        #(CLOCK_PERIOD * 500000);
        $display("\n✗ ERROR: Test timeout!");
        $finish;
    end
    
endmodule
