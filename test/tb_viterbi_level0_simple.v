// Viterbi Decoder Testbench - Level 0: Noiseless Loopback (Simplified)
// Reads test vectors from hex files

`timescale 1ns/1ps

module tb_viterbi_level0_simple();
    
    // Parameters matching the DUT
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter WM = 6;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    
    parameter CLOCK_PERIOD = 10;
    parameter L_FRAME = 64;  // Must match gen_hex_vectors.c
    parameter NUM_FRAMES = 10;
    parameter NSYM_FRAME = L_FRAME + M;  // 66 symbols per frame
    parameter NBIT_EXPECTED = L_FRAME + M - D;  // 60 bits expected
    
    // DUT signals
    reg clk;
    reg rst;
    
    // Symbol stream input
    reg rx_sym_valid;
    wire rx_sym_ready;
    reg [1:0] rx_sym;
    
    // Decoded output stream
    wire dec_bit_valid;
    wire dec_bit;
    
    // Control
    reg force_state0;
    
    // DUT instantiation
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
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end
    
    // Test storage
    reg [1:0] symbols [0:NUM_FRAMES*NSYM_FRAME-1];
    reg expected [0:NUM_FRAMES*NBIT_EXPECTED-1];
    
    // Test variables
    integer frame;
    integer sym_idx, exp_idx;
    integer dec_count, sym_count;
    integer errors, total_bits;
    integer i;
    reg [1:0] sym;
    reg exp_bit;
    integer frame_errors;
    
    // Decoded bit collection
    reg decoded [0:NBIT_EXPECTED-1];
    integer dec_idx;
    integer accept_count;
    
    // Main test
    initial begin
        $display("=================================================");
        $display("Viterbi Decoder Test - Level 0: Noiseless");
        $display("K=%0d, M=%0d, S=%0d, D=%0d", K, M, S, D);
        $display("G0=%03o, G1=%03o (octal)", G0_OCT, G1_OCT);
        $display("Frame: %0d bits, %0d symbols", L_FRAME, NSYM_FRAME);
        $display("Expected: %0d bits (first %0d dropped)", NBIT_EXPECTED, D);
        $display("=================================================\n");
        
        // Read test vectors
        $readmemh("symbols.mem", symbols);
        $readmemh("expected.mem", expected);
        
        // Initialize
        clk = 0;
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;  // Tail-terminated mode
        errors = 0;
        total_bits = 0;
        accept_count = 0;
        
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // Process each frame
        for (frame = 0; frame < NUM_FRAMES; frame++) begin
            $display("Frame %0d:", frame);
            
            // NO per-frame reset - decoder is streaming!
            // Only reset at the very beginning
            
            // Send symbols and collect output
            dec_idx = 0;
            sym_count = 0;
            
            // Send symbols continuously
            for (sym_idx = 0; sym_idx < NSYM_FRAME; sym_idx++) begin
                // Get symbol from memory
                sym = symbols[frame * NSYM_FRAME + sym_idx];
                
                // Wait for ready (decoder might be busy)
                while (!rx_sym_ready) begin
                    @(posedge clk);
                    // Collect outputs while waiting
                    if (dec_bit_valid && dec_idx < NBIT_EXPECTED) begin
                        decoded[dec_idx] = dec_bit;
                        dec_idx = dec_idx + 1;
                    end
                end
                
                // Send symbol
                rx_sym = sym;
                rx_sym_valid = 1;
                @(posedge clk);
                
                // Collect decoded output
                if (dec_bit_valid && dec_idx < NBIT_EXPECTED) begin
                    decoded[dec_idx] = dec_bit;
                    dec_idx = dec_idx + 1;
                end
                
                rx_sym_valid = 0;
                sym_count = sym_count + 1;
            end
            
            $display("  Sent %0d symbols", sym_count);
            
            // Wait for remaining outputs (traceback takes time)
            repeat(100) begin
                @(posedge clk);
                if (dec_bit_valid && dec_idx < NBIT_EXPECTED) begin
                    decoded[dec_idx] = dec_bit;
                    dec_idx = dec_idx + 1;
                end
            end
            
            // Compare with expected
            frame_errors = 0;
            for (i = 0; i < NBIT_EXPECTED; i++) begin
                exp_bit = expected[frame * NBIT_EXPECTED + i];
                if (i < dec_idx) begin
                    if (decoded[i] !== exp_bit) begin
                        frame_errors = frame_errors + 1;
                        if (frame_errors <= 5) begin
                            $display("  Error at bit %0d: got=%b exp=%b", i, decoded[i], exp_bit);
                        end
                    end
                end else begin
                    frame_errors = frame_errors + 1;
                    if (frame_errors <= 5) begin
                        $display("  Missing bit %0d (expected=%b)", i, exp_bit);
                    end
                end
            end
            
            $display("  Decoded %0d bits, %0d errors (%.1f%%)", 
                     dec_idx, frame_errors, 100.0 * frame_errors / NBIT_EXPECTED);
            
            errors = errors + frame_errors;
            total_bits = total_bits + NBIT_EXPECTED;
        end
        
        // Summary
        $display("\n=================================================");
        $display("LEVEL 0 Complete");
        $display("Total errors: %0d / %0d bits", errors, total_bits);
        $display("BER: %.6f", 1.0 * errors / total_bits);
        
        if (errors == 0) begin
            $display("*** PASS - Perfect decoding! ***");
        end else begin
            $display("*** FAIL ***");
        end
        $display("=================================================");
        
        $finish;
    end
    
    always @(posedge clk) begin
        if (rx_sym_valid && rx_sym_ready) begin
            accept_count <= accept_count + 1;
        end
    end
    
    final begin
        $display("TB accepts: %0d", accept_count);
    end
    
    // Timeout watchdog
    initial begin
        #(CLOCK_PERIOD * 100000);
        $display("ERROR: Test timeout!");
        $finish;
    end
    
endmodule
