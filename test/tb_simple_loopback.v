// Simple loopback test
`timescale 1ns/1ps

module tb_simple_loopback();
    
    parameter K = 3;
    parameter M = K - 1;
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
    
    task send_symbol(input [1:0] sym);
        begin
            while (!rx_sym_ready) @(posedge clk);
            rx_sym = sym;
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    integer i, bit_count;
    integer match_count, total_check;
    logic [M-1:0] enc_state;
    logic y0, y1;
    logic [0:15] info_bits;
    logic [0:15] dec_bits;
    
    initial begin
        $display("Simple Loopback Test");
        $display("====================");
        
        // Test pattern: 1010 repeating
        info_bits = 16'b1010_1010_1010_1010;
        $display("Input: %b", info_bits);
        
        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // Encode and send
        enc_state = 0;
        bit_count = 0;
        
        fork
            begin
                // Send some training zeros first
                for (i = 0; i < 8; i = i + 1) begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                    $display("Train bit %0d=0: enc_state=%02b -> syms %b%b", 
                            i, enc_state, y0, y1);
                    send_symbol({y0, y1});
                end
                
                // Now send actual data
                for (i = 0; i < 16; i = i + 1) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                    $display("Send bit %0d=%b: enc_state=%02b -> syms %b%b", 
                            i, info_bits[i], enc_state, y0, y1);
                    send_symbol({y0, y1});
                end
                
                // Tail
                for (i = 0; i < M; i = i + 1) begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                    $display("Tail %0d: enc_state=%02b -> syms %b%b", i, enc_state, y0, y1);
                    send_symbol({y0, y1});
                end
                
                $display("\nDone sending, waiting for outputs...");
            end
            
            begin
                forever begin
                    @(posedge clk);
                    if (dec_bit_valid) begin
                        dec_bits[bit_count] = dec_bit;
                        $display("  Dec bit %0d = %b", bit_count, dec_bit);
                        bit_count = bit_count + 1;
                    end
                end
            end
        join_any
        
        repeat(300) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                dec_bits[bit_count] = dec_bit;
                $display("  Dec bit %0d = %b", bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        $display("\n=== RESULTS ===");
        $display("Sent: %b", info_bits);
        if (bit_count >= 16) begin
            $display("Recv: %b", dec_bits[0:15]);
            $display("\nSkipping first D=%0d bits (traceback latency):", D);
            match_count = 0;
            total_check = 0;
            for (i = D; i < 16 && i < bit_count; i = i + 1) begin
                total_check = total_check + 1;
                if (dec_bits[i] == info_bits[i]) begin
                    match_count = match_count + 1;
                    $display("  Bit %0d: %b ✓", i, dec_bits[i]);
                end else begin
                    $display("  Bit %0d: expected %b, got %b ✗", i, info_bits[i], dec_bits[i]);
                end
            end
            if (match_count == total_check) begin
                $display("\n✓✓✓ ALL %0d CHECKED BITS MATCH! ✓✓✓", total_check);
            end else begin
                $display("\n✗ %0d/%0d bits match", match_count, total_check);
            end
        end else begin
            $display("Recv: %0d bits", bit_count);
            for (i = 0; i < bit_count; i = i + 1) begin
                $display("  Bit %0d: %b (expected %b) %s", 
                        i, dec_bits[i], info_bits[i],
                        (dec_bits[i] == info_bits[i]) ? "✓" : "✗");
            end
        end
        
        $finish;
    end
    
    initial begin
        #(CLOCK_PERIOD * 30000);
        $display("TIMEOUT");
        $finish;
    end
    
endmodule
