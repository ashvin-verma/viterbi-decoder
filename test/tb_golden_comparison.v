// Golden model comparison for debugging
`timescale 1ns/1ps

module tb_golden_comparison();
    
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
    parameter WM = 6;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    parameter CLOCK_PERIOD = 10;
    
    reg clk, rst, rx_sym_valid, force_state0;
    wire rx_sym_ready, dec_bit_valid, dec_bit;
    reg [1:0] rx_sym;
    
    tt_um_viterbi_core #(
        .K(K), .D(D), .Wm(WM),
        .G0_OCT(G0_OCT), .G1_OCT(G1_OCT)
    ) dut (
        .clk(clk), .rst(rst),
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
    
    // Encoder
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
            state_out = sr[K-2:0];
        end
    endtask
    
    // Golden Viterbi decoder model
    task golden_viterbi_step(
        input [1:0] rx_symbols,
        input integer step_num,
        output [0:S-1] survivor_bits,
        output [M-1:0] best_state
    );
        integer state, pred0, pred1, bit0, bit1;
        logic [1:0] exp0, exp1;
        integer bm0, bm1, pm0, pm1, metric0, metric1;
        integer best_metric;
        integer path_metrics_curr [0:S-1];
        integer path_metrics_prev [0:S-1];
        logic [K-1:0] sr;
        
        begin
            // Initialize on first step
            if (step_num == 0) begin
                for (state = 0; state < S; state = state + 1) begin
                    path_metrics_prev[state] = (state == 0) ? 0 : 999999;
                end
            end
            
            // ACS for each state
            for (state = 0; state < S; state = state + 1) begin
                // Two predecessors for this state
                pred0 = state >> 1;           // Predecessor with bit 0
                pred1 = pred0 | (1 << (M-1)); // Predecessor with bit 1
                bit0 = state & 1;             // Input bit from pred0
                bit1 = state & 1;             // Input bit from pred1 (same LSB)
                
                // Expected symbols from pred0 with bit 0 or 1
                sr = {pred0[M-1:0], bit0[0]};
                exp0[1] = ^(sr & G0_OCT[K-1:0]);
                exp0[0] = ^(sr & G1_OCT[K-1:0]);
                
                sr = {pred1[M-1:0], bit1[0]};
                exp1[1] = ^(sr & G1_OCT[K-1:0]);
                exp1[0] = ^(sr & G1_OCT[K-1:0]);
                
                // Branch metrics (Hamming distance)
                bm0 = ((rx_symbols[1] != exp0[1]) ? 1 : 0) + ((rx_symbols[0] != exp0[0]) ? 1 : 0);
                bm1 = ((rx_symbols[1] != exp1[1]) ? 1 : 0) + ((rx_symbols[0] != exp1[0]) ? 1 : 0);
                
                // Path metrics
                pm0 = path_metrics_prev[pred0];
                pm1 = path_metrics_prev[pred1];
                
                metric0 = pm0 + bm0;
                metric1 = pm1 + bm1;
                
                // Select survivor
                if (metric1 < metric0) begin
                    path_metrics_curr[state] = metric1;
                    survivor_bits[state] = 1;  // Chose pred1
                end else begin
                    path_metrics_curr[state] = metric0;
                    survivor_bits[state] = 0;  // Chose pred0
                end
            end
            
            // Find best state
            best_metric = path_metrics_curr[0];
            best_state = 0;
            for (state = 1; state < S; state = state + 1) begin
                if (path_metrics_curr[state] < best_metric) begin
                    best_metric = path_metrics_curr[state];
                    best_state = state;
                end
            end
            
            // Copy current to prev for next iteration
            for (state = 0; state < S; state = state + 1) begin
                path_metrics_prev[state] = path_metrics_curr[state];
            end
        end
    endtask
    
    task send_symbol(input [1:0] sym);
        begin
            while (!rx_sym_ready) @(posedge clk);
            rx_sym = sym;
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    integer i, bit_count, sym_count;
    logic [M-1:0] enc_state;
    logic y0, y1;
    logic [0:7] info_bits;
    logic [0:15] symbols;
    logic [0:15] dec_bits;
    logic [0:S-1] golden_surv [0:15];
    logic [M-1:0] golden_best [0:15];
    
    initial begin
        $display("Golden Model Comparison");
        $display("=======================");
        
        // Simple test: 11110000
        info_bits = 8'b11110000;
        $display("Input bits: %b", info_bits);
        
        // Encode
        enc_state = 0;
        sym_count = 0;
        for (i = 0; i < 8; i = i + 1) begin
            encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
            symbols[sym_count*2] = y0;
            symbols[sym_count*2+1] = y1;
            $display("Bit %0d=%b: enc_state=%02b -> y0=%b y1=%b (sym=%b%b)", 
                    i, info_bits[i], enc_state, y0, y1, y0, y1);
            sym_count = sym_count + 1;
        end
        
        // Tail
        for (i = 0; i < M; i = i + 1) begin
            encode_bit(1'b0, enc_state, enc_state, y0, y1);
            symbols[sym_count*2] = y0;
            symbols[sym_count*2+1] = y1;
            $display("Tail %0d: enc_state=%02b -> y0=%b y1=%b", i, enc_state, y0, y1);
            sym_count = sym_count + 1;
        end
        
        $display("\nRunning golden model...");
        for (i = 0; i < sym_count; i = i + 1) begin
            golden_viterbi_step({symbols[i*2], symbols[i*2+1]}, i, golden_surv[i], golden_best[i]);
            $display("Step %0d: rx=%b%b, survivors=%b, best_state=%02b", 
                    i, symbols[i*2], symbols[i*2+1], golden_surv[i], golden_best[i]);
        end
        
        $display("\nRunning DUT...");
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        bit_count = 0;
        for (i = 0; i < sym_count; i = i + 1) begin
            send_symbol({symbols[i*2], symbols[i*2+1]});
            if (dec_bit_valid) begin
                dec_bits[bit_count] = dec_bit;
                $display("  Symbol %0d: decoded bit %0d = %b", i, bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        // Wait for remaining
        repeat(200) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                dec_bits[bit_count] = dec_bit;
                $display("  (straggler) decoded bit %0d = %b", bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        $display("\n=== COMPARISON ===");
        $display("Input:   %b", info_bits);
        $display("Decoded: ", );
        for (i = 0; i < bit_count && i < 8; i = i + 1) begin
            $write("%b", dec_bits[i]);
        end
        $display("");
        $display("Got %0d bits total", bit_count);
        
        $display("\nSkipping first D=%0d bits:", D);
        for (i = D; i < bit_count && i < 8; i = i + 1) begin
            if (dec_bits[i] == info_bits[i]) begin
                $display("  Bit %0d: %b ✓", i, dec_bits[i]);
            end else begin
                $display("  Bit %0d: expected %b, got %b ✗", i, info_bits[i], dec_bits[i]);
            end
        end
        
        $finish;
    end
    
    initial begin
        #(CLOCK_PERIOD * 20000);
        $display("TIMEOUT");
        $finish;
    end
    
endmodule
