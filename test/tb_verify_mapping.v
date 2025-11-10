// Verify exact bit-to-bit mapping
`timescale 1ns/1ps

module tb_verify_mapping();
    
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
            state_out = sr[K-2:0];  // Shift: take lower K-1 bits
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
    logic [M-1:0] enc_state;
    logic y0, y1;
    logic [0:15] info_bits;
    logic [0:15] dec_bits;
    
    initial begin
        $display("Verify Bit Mapping");
        $display("==================");
        
        // Test pattern: alternating 1010...
        for (i = 0; i < 16; i = i + 1) begin
            info_bits[i] = i[0];
        end
        
        $display("Input bits: %b", info_bits);
        
        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // Encode and send each bit
        enc_state = 0;
        bit_count = 0;
        
        fork
            begin
                for (i = 0; i < 16; i = i + 1) begin
                    encode_bit(info_bits[i], enc_state, enc_state, y0, y1);
                    $display("Bit %0d: %b -> symbols %b%b", i, info_bits[i], y0, y1);
                    send_symbol({y0, y1});
                end
                
                // Send tail
                for (i = 0; i < M; i = i + 1) begin
                    encode_bit(1'b0, enc_state, enc_state, y0, y1);
                    $display("Tail %0d: 0 -> symbols %b%b", i, y0, y1);
                    send_symbol({y0, y1});
                end
            end
            
            begin
                forever begin
                    @(posedge clk);
                    if (dec_bit_valid) begin
                        dec_bits[bit_count] = dec_bit;
                        $display("  -> Decoded bit %0d = %b", bit_count, dec_bit);
                        bit_count = bit_count + 1;
                    end
                end
            end
        join_any
        
        // Wait for remaining
        repeat(200) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                dec_bits[bit_count] = dec_bit;
                $display("  -> Decoded bit %0d = %b", bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        $display("\n=== RESULTS ===");
        $display("Sent %0d info bits + %0d tail = %0d symbols total", 16, M, 16+M);
        $display("Received %0d decoded bits", bit_count);
        $display("");
        $display("Input:  %b", info_bits);
        if (bit_count >= 16) begin
            $display("Output: %b", dec_bits[0:15]);
            
            if (dec_bits[0:15] == info_bits[0:15]) begin
                $display("\n✓✓✓ PERFECT MATCH! ✓✓✓");
            end else begin
                $display("\n✗ MISMATCH - comparing bit by bit:");
                for (i = 0; i < 16; i = i + 1) begin
                    if (dec_bits[i] !== info_bits[i]) begin
                        $display("  Bit %0d: expected %b, got %b", i, info_bits[i], dec_bits[i]);
                    end
                end
            end
        end else begin
            $display("Output: (only %0d bits)", bit_count);
            for (i = 0; i < bit_count; i = i + 1) begin
                $display("  Bit %0d: %b", i, dec_bits[i]);
            end
            $display("\n✗ Got fewer bits than expected (%0d < 16)", bit_count);
        end
        
        $finish;
    end
    
    initial begin
        #(CLOCK_PERIOD * 20000);
        $display("TIMEOUT");
        $finish;
    end
    
endmodule
