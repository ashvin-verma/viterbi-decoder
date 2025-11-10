// Comprehensive Viterbi Decoder Testbench
// Levels 0-9: From basic loopback to stress tests

`timescale 1ns/1ps

module tb_viterbi_decoder();
    // Test configuration - can be overridden
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter WM = 6;  // Path metric width
    
    // Test parameters
    parameter L_FRAME = 256;  // Frame length in bits
    parameter NUM_FRAMES = 10;
    parameter CLOCK_PERIOD = 10;
    
    // DUT signals
    reg clk;
    reg rst_n;
    
    // Symbol input (unpacker simulation)
    reg [1:0] rx_sym;
    reg rx_sym_valid;
    wire rx_sym_ready;
    
    // Decoded output
    wire dec_bit;
    wire dec_bit_valid;
    
    // Control
    reg force_state0;
    reg init_frame;
    
    // DUT instantiation (placeholder - will connect to actual viterbi_core)
    viterbi_core #(
        .K(K),
        .D(D),
        .Wm(WM)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx_sym(rx_sym),
        .rx_sym_valid(rx_sym_valid),
        .rx_sym_ready(rx_sym_ready),
        .dec_bit(dec_bit),
        .dec_bit_valid(dec_bit_valid),
        .force_state0(force_state0),
        .init_frame(init_frame)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end
    
    // Test level selection
    integer test_level;
    integer errors;
    integer total_bits;
    
    // Golden model integration (C model via DPI or file I/O)
    // For now, we'll use simple patterns
    
    //=================================================================
    // LEVEL 0: Noiseless Loopback
    //=================================================================
    task level0_noiseless_loopback();
        integer frame;
        integer bit_idx;
        integer sym_count;
        integer dec_count;
        reg [0:L_FRAME-1] input_bits;
        reg [0:L_FRAME+M-1] expected_output;
        reg [0:L_FRAME-1] decoded_bits;
        
        $display("\n=== LEVEL 0: Noiseless Loopback ===");
        $display("Frame length: %0d bits", L_FRAME);
        $display("Number of frames: %0d", NUM_FRAMES);
        
        errors = 0;
        total_bits = 0;
        
        for (frame = 0; frame < NUM_FRAMES; frame++) begin
            // Generate random input bits
            for (bit_idx = 0; bit_idx < L_FRAME; bit_idx++) begin
                input_bits[bit_idx] = $random & 1;
            end
            
            // TODO: Encode with golden model (for now, just pass through)
            // In real test, call C encoder or implement Verilog encoder
            
            // Reset DUT
            @(posedge clk);
            rst_n = 0;
            init_frame = 1;
            force_state0 = 0;
            rx_sym_valid = 0;
            @(posedge clk);
            @(posedge clk);
            rst_n = 1;
            @(posedge clk);
            init_frame = 0;
            
            // Send encoded symbols
            sym_count = 0;
            for (bit_idx = 0; bit_idx < L_FRAME + M; bit_idx++) begin
                // Simple encoding for test (need proper golden encoder)
                @(posedge clk);
                rx_sym_valid = 1;
                rx_sym = 2'b00;  // Placeholder
                sym_count = sym_count + 1;
            end
            
            @(posedge clk);
            rx_sym_valid = 0;
            
            // Wait for decoder to finish
            repeat(100) @(posedge clk);
            
            $display("Frame %0d: Sent %0d symbols", frame, sym_count);
        end
        
        $display("LEVEL 0 Complete: %0d errors / %0d bits", errors, total_bits);
    endtask
    
    //=================================================================
    // LEVEL 1: Trellis End-Effects
    //=================================================================
    task level1_tail_terminated();
        $display("\n=== LEVEL 1A: Tail-Terminated Frames ===");
        
        // Test with K-1 tail zeros
        // force_state0 = 1 to use state 0 as end state
        
        $display("LEVEL 1A: Not yet implemented");
    endtask
    
    task level1_free_running();
        $display("\n=== LEVEL 1B: Free-Running (No Tail) ===");
        
        // Test without tail bits
        // Use s_end = argmin(pm_prev)
        
        $display("LEVEL 1B: Not yet implemented");
    endtask
    
    task level1_short_frames();
        $display("\n=== LEVEL 1C: Short Frames (L <= D) ===");
        
        // Test with frame length <= D
        // Should emit 0 or define behavior
        
        $display("LEVEL 1C: Not yet implemented");
    endtask
    
    //=================================================================
    // LEVEL 2: Single-Error Correction
    //=================================================================
    task level2_single_error();
        $display("\n=== LEVEL 2: Single-Error Correction ===");
        
        // Flip exactly one coded bit per frame
        // Expect 0 decoded errors (within dfree capability)
        
        $display("LEVEL 2: Not yet implemented");
    endtask
    
    //=================================================================
    // Main Test Sequence
    //=================================================================
    initial begin
        $display("=================================================");
        $display("Viterbi Decoder Comprehensive Test Suite");
        $display("K=%0d, M=%0d, S=%0d, D=%0d, Wm=%0d", K, M, S, D, WM);
        $display("=================================================");
        
        // Initialize
        clk = 0;
        rst_n = 0;
        rx_sym = 0;
        rx_sym_valid = 0;
        force_state0 = 0;
        init_frame = 0;
        
        // Wait for reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // Run test levels
        test_level = 0;
        
        // Level 0
        if (test_level <= 0) begin
            level0_noiseless_loopback();
        end
        
        // Level 1
        if (test_level <= 1) begin
            level1_tail_terminated();
            level1_free_running();
            level1_short_frames();
        end
        
        // Level 2
        if (test_level <= 2) begin
            level2_single_error();
        end
        
        // Summary
        $display("\n=================================================");
        $display("Test Suite Complete");
        $display("=================================================");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLOCK_PERIOD * 1000000);  // 1M cycles timeout
        $display("ERROR: Test timeout!");
        $finish;
    end
    
endmodule
