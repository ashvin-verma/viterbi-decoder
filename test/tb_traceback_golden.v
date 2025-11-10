// Testbench for traceback module using golden model vectors
// Generated from gen_traceback_vectors.c output

`timescale 1ns/1ps

module tb_traceback_golden();
    parameter K = 4;  // Maximum K for the project
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter N = 48;
    parameter T_SYMS = 50;
    parameter T_INFO = T_SYMS - M;  // 48
    parameter T_DEC = T_INFO - D + 1;  // 43 bits expected (but streaming produces 45)

    reg clk;
    reg rst_n;
    reg force_state0;
    reg [$clog2(D)-1:0] wr_ptr;  // Need $clog2(D) bits for D=6 (3 bits)
    reg [$clog2(D)-1:0] rd_time;
    reg [M-1:0] rd_state;
    wire surv_bit;
    wire dec_bit;
    wire dec_bit_valid;

    // Survivor memory model (circular buffer)
    reg [S-1:0] mem [0:D-1];

    // DUT
    traceback #(.K(K), .D(D)) dut (
        .clk(clk),
        .rst(~rst_n),
        .s_end({M{1'b0}}),  // end state = 0
        .force_state0(force_state0),
        .wr_ptr(wr_ptr),
        .tb_surv_bit(surv_bit),
        .tb_time(rd_time),
        .tb_state(rd_state),
        .dec_bit(dec_bit),
        .dec_bit_valid(dec_bit_valid)
    );

    // Memory read
    assign surv_bit = mem[rd_time][rd_state];

    // Clock generation
    always #5 clk = ~clk;

    // Expected output from golden model (STREAMING MODE)
    // Pattern: 010 repeating (t%3 logic with state always 0)
    reg [0:44] expected_output;  // 45 bits
    integer expected_idx;
    integer mismatch_count;
    reg [$clog2(D)-1:0] wr_ptr_log [0:44];  // Log wr_ptr for each traceback

    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        force_state0 = 0;
        wr_ptr = 0;
        expected_idx = 0;
        mismatch_count = 0;

        // Expected output sequence (STREAMING MODE - 45 bits)
        // At each time t (from 5 to 49), state stays at 0, so we read surv[t][0]
        // For K=4: Pattern t%2==0 → surv[t][0]=1, else 0
        // Times 5,6,7,8,9... → 0,1,0,1,0... (alternating, starting with 0 for odd t=5)
        expected_output = 45'b010101010101010101010101010101010101010101010;

        // Initialize survivor memory
        for (integer i = 0; i < D; i = i + 1) begin
            mem[i] = {S{1'b0}};
        end
        
        // Reset
        #10 rst_n = 1;
        #10;

        // Simulate forward pass: write survivor memory and trigger traceback after each write
        for (integer t = 0; t < T_SYMS; t = t + 1) begin
            integer idx;
            reg [S-1:0] surv_row;
            
            // Compute survivor row for this time step
            // For K=4: bit[0] alternates, others stay 0
            surv_row = {S{1'b0}};
            if (t % 2 == 0)
                surv_row[0] = 1'b1;
            
            // Write to circular buffer
            idx = t % D;
            mem[idx] = surv_row;
            
            // Update write pointer to point to NEXT write location
            wr_ptr = (t + 1) % D;
            
            // Log wr_ptr for debugging
            if (t >= D - 1) begin
                wr_ptr_log[t - (D - 1)] = wr_ptr;
            end
            
            // After first D writes, we can start doing traceback
            // Wait for the write to settle
            @(posedge clk);
            
            if (t >= D - 1) begin
                // Trigger traceback
                force_state0 = 1;
                @(posedge clk);
                force_state0 = 0;
                
                // Wait for traceback to complete (approximately D+3 cycles)
                repeat (D + 5) @(posedge clk);
            end
        end
        
        // Wait a bit more for any pending outputs
        repeat (20) @(posedge clk);

        // Summary
        $display("\n=== TEST SUMMARY ===");
        $display("Expected outputs: 45");
        $display("Received outputs: %0d", expected_idx);
        $display("Mismatches: %0d", mismatch_count);
        if (mismatch_count == 0 && expected_idx == 45)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** TEST FAILED ***");
        $finish;
    end

    // Monitor outputs
    always @(posedge clk) begin
        if (dec_bit_valid) begin
            if (expected_idx < 45) begin
                if (dec_bit !== expected_output[expected_idx]) begin
                    $display("TB ERROR: idx=%0d, got=%b, expected=%b",
                             expected_idx, dec_bit, expected_output[expected_idx]);
                    mismatch_count = mismatch_count + 1;
                end else begin
                    $display("TB PASS:  idx=%0d, got=%b, expected=%b",
                             expected_idx, dec_bit, expected_output[expected_idx]);
                end
                expected_idx = expected_idx + 1;
            end
        end
    end

endmodule
