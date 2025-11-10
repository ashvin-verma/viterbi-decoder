// Viterbi Decoder Testbench - Level 0: Noiseless Loopback
// Reads test vectors from file and verifies decoder output

`timescale 1ns/1ps

module tb_viterbi_level0();
    
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
    
    // Test variables
    integer file;
    integer status;
    integer frame_num;
    integer errors;
    integer total_bits;
    integer bit_count;
    integer sym_count;
    
    // Storage for test vectors
    reg [1:0] all_symbols [0:NUM_FRAMES*(L_FRAME+M)-1];  // Flattened array
    reg all_expected [0:NUM_FRAMES*(L_FRAME+M-D)-1];    // Flattened array
    
    // Test task
    task run_frame_test;
        input integer frame_id;
        integer i;
        integer sym_idx;
        integer dec_idx;
        integer frame_errors;
        
        begin
            $display("Testing Frame %0d...", frame_id);
            
            // Reset decoder
            @(posedge clk);
            rst = 1;
            force_state0 = 1;  // Use state 0 as end state (tail-terminated)
            rx_sym_valid = 0;
            @(posedge clk);
            @(posedge clk);
            rst = 0;
            @(posedge clk);
            
            // Send symbols
            sym_idx = 0;
            dec_idx = 0;
            
            for (i = 0; i < L_FRAME + M; i++) begin
                // Wait for ready
                while (!rx_sym_ready) @(posedge clk);
                
                // Send symbol
                rx_sym = symbols[i];
                rx_sym_valid = 1;
                
                // Capture decoded output (starts after D symbols)
                @(posedge clk);
                if (dec_bit_valid) begin
                    decoded_bits[dec_idx] = dec_bit;
                    dec_idx = dec_idx + 1;
                end
                
                sym_idx = sym_idx + 1;
            end
            
            // Deassert valid
            rx_sym_valid = 0;
            
            // Collect remaining outputs (D bits will be dropped, so we should get L_FRAME total)
            while (dec_idx < L_FRAME) begin
                @(posedge clk);
                if (dec_bit_valid) begin
                    if (dec_idx < L_FRAME) begin
                        decoded_bits[dec_idx] = dec_bit;
                        dec_idx = dec_idx + 1;
                    end
                end
                
                // Timeout check
                if (dec_idx >= L_FRAME * 2) begin
                    $display("ERROR: Timeout waiting for decoded bits!");
                    $finish;
                end
            end
            
            // Wait a few more cycles
            repeat(10) @(posedge clk);
            
            // Compare with expected (skip first D bits)
            frame_errors = 0;
            for (i = D; i < L_FRAME; i++) begin
                if (decoded_bits[i-D] !== expected_bits[i-D]) begin
                    frame_errors = frame_errors + 1;
                    if (frame_errors <= 10) begin
                        $display("  Error at bit %0d: decoded=%b expected=%b", 
                                 i, decoded_bits[i-D], expected_bits[i-D]);
                    end
                end
            end
            
            $display("  Frame %0d: %0d errors / %0d bits (%.2f%%)", 
                     frame_id, frame_errors, L_FRAME-D,
                     100.0 * frame_errors / (L_FRAME-D));
            
            errors = errors + frame_errors;
            total_bits = total_bits + (L_FRAME - D);
        end
    endtask
    
    // Main test
    initial begin
        $display("=================================================");
        $display("Viterbi Decoder Test - Level 0: Noiseless");
        $display("K=%0d, M=%0d, S=%0d, D=%0d", K, M, S, D);
        $display("G0=%03o, G1=%03o (octal)", G0_OCT, G1_OCT);
        $display("=================================================");
        
        // Open test vector file
        file = $fopen("test_vectors_k3.txt", "r");
        if (file == 0) begin
            $display("ERROR: Cannot open test_vectors_k3.txt");
            $finish;
        end
        
        // Initialize
        clk = 0;
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        errors = 0;
        total_bits = 0;
        
        repeat(5) @(posedge clk);
        
        // Read and test each frame
        frame_num = 0;
        
        // TODO: Parse file and run tests
        // For now, just do a simple pattern test
        
        $display("\nSkipping file parsing - running simple pattern test instead");
        
        // Simple test: encode 010101... pattern
        for (frame_num = 0; frame_num < 5; frame_num++) begin
            // Generate alternating pattern
            for (bit_count = 0; bit_count < L_FRAME; bit_count++) begin
                info_bits[bit_count] = bit_count[0];  // Alternating 01010...
                expected_bits[bit_count] = bit_count[0];
            end
            
            // Simple encoding (y0=bit, y1=bit for now - need proper encoder)
            for (sym_count = 0; sym_count < L_FRAME + M; sym_count++) begin
                if (sym_count < L_FRAME) begin
                    symbols[sym_count] = {info_bits[sym_count], info_bits[sym_count]};
                end else begin
                    symbols[sym_count] = 2'b00;  // Tail
                end
            end
            
            run_frame_test(frame_num);
        end
        
        // Final summary
        $display("\n=================================================");
        $display("LEVEL 0 Complete");
        $display("Total errors: %0d / %0d bits (%.4f%%)", 
                 errors, total_bits, 100.0 * errors / total_bits);
        
        if (errors == 0) begin
            $display("*** PASS ***");
        end else begin
            $display("*** FAIL ***");
        end
        $display("=================================================");
        
        $fclose(file);
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLOCK_PERIOD * 100000);
        $display("ERROR: Test timeout!");
        $finish;
    end
    
endmodule
