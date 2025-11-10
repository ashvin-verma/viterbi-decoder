// Minimal debug test for Viterbi Core
`timescale 1ns/1ps

module tb_viterbi_debug();
    
    parameter K = 3;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 6;
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
    
    integer sym_count, bit_count;
    
    initial begin
        $display("Minimal Viterbi Test");
        $display("K=%0d, M=%0d, S=%0d, D=%0d", K, M, S, D);
        
        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        $display("\nSending 10 symbols (all zeros):");
        sym_count = 0;
        bit_count = 0;
        
        fork
            // Send symbols
            begin
                for (sym_count = 0; sym_count < 10; sym_count = sym_count + 1) begin
                    // Wait for ready
                    while (!rx_sym_ready) @(posedge clk);
                    
                    rx_sym = 2'b00;  // All zeros
                    rx_sym_valid = 1;
                    $display("  T=%0t: Sending symbol %0d = 00", $time, sym_count);
                    
                    @(posedge clk);
                    rx_sym_valid = 0;
                end
            end
            
            // Monitor outputs
            begin
                forever begin
                    @(posedge clk);
                    if (dec_bit_valid) begin
                        $display("  T=%0t: Got decoded bit %0d = %b", $time, bit_count, dec_bit);
                        bit_count = bit_count + 1;
                    end
                end
            end
        join_any
        
        // Wait for remaining outputs
        $display("\nWaiting for remaining outputs...");
        repeat(500) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                $display("  T=%0t: Got decoded bit %0d = %b", $time, bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        $display("\nTotal: sent %0d symbols, received %0d bits", sym_count, bit_count);
        $display("Expected: after D=%0d warmup, should get 1 bit per symbol", D);
        
        if (bit_count >= sym_count - D) begin
            $display("PASS: Got at least %0d bits", sym_count - D);
        end else begin
            $display("FAIL: Expected %0d+ bits, got %0d", sym_count - D, bit_count);
        end
        
        $finish;
    end
    
    initial begin
        #(CLOCK_PERIOD * 10000);
        $display("TIMEOUT");
        $finish;
    end
    
endmodule
