// Trace the decoding issue
`timescale 1ns/1ps

module tb_trace_issue();
    
    parameter K = 3;
    parameter M = K - 1;
    parameter D = 6;
    parameter WM = 6;
    parameter G0_OCT = 8'o07;  // 111 binary
    parameter G1_OCT = 8'o05;  // 101 binary
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
    
    task send_symbol(input [1:0] sym);
        begin
            while (!rx_sym_ready) @(posedge clk);
            rx_sym = sym;
            rx_sym_valid = 1;
            $display("T=%0t: Sending symbol %b", $time, sym);
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    integer bit_count;
    logic [0:31] dec_bits;
    
    initial begin
        $display("Trace Decoding Issue");
        $display("====================");
        $display("G0 = %b (XOR of shift register & G0)", G0_OCT[2:0]);
        $display("G1 = %b (XOR of shift register & G1)", G1_OCT[2:0]);
        $display("");
        
        // Manual encoding of pattern: 1 1 1 1
        // SR starts at 00
        // Bit 0 = 1: SR = 001 -> G0: 001&111=001 XOR=1, G1: 001&101=001 XOR=1 -> symbols: 11
        // Bit 1 = 1: SR = 011 -> G0: 011&111=011 XOR=0, G1: 011&101=001 XOR=1 -> symbols: 01  
        // Bit 2 = 1: SR = 111 -> G0: 111&111=111 XOR=1, G1: 111&101=101 XOR=0 -> symbols: 10
        // Bit 3 = 1: SR = 111 -> G0: 111&111=111 XOR=1, G1: 111&101=101 XOR=0 -> symbols: 10
        
        $display("Expected encoding for 1111:");
        $display("  Bit 0=1: SR=001 -> (1 XOR) & 111=1, (1 XOR) & 101=1 -> 11");
        $display("  Bit 1=1: SR=011 -> (011 XOR) & 111=0, (011 XOR) & 101=1 -> 01");
        $display("  Bit 2=1: SR=111 -> (111 XOR) & 111=1, (111 XOR) & 101=0 -> 10");
        $display("  Bit 3=1: SR=111 -> (111 XOR) & 111=1, (111 XOR) & 101=0 -> 10");
        $display("");
        
        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        bit_count = 0;
        
        fork
            begin
                $display("Sending encoded symbols for 1111:");
                send_symbol(2'b11);  // Bit 0 = 1
                send_symbol(2'b01);  // Bit 1 = 1
                send_symbol(2'b10);  // Bit 2 = 1
                send_symbol(2'b10);  // Bit 3 = 1
                send_symbol(2'b00);  // Tail bit 0 = 0: SR=110 -> 110&111=1, 110&101=0 -> 10... wait
                send_symbol(2'b00);  // Tail bit 1 = 0
                $display("Done sending");
            end
            
            begin
                forever begin
                    @(posedge clk);
                    if (dec_bit_valid) begin
                        dec_bits[bit_count] = dec_bit;
                        $display("T=%0t: *** DECODED BIT %0d = %b ***", $time, bit_count, dec_bit);
                        bit_count = bit_count + 1;
                    end
                end
            end
        join_any
        
        repeat(500) begin
            @(posedge clk);
            if (dec_bit_valid) begin
                dec_bits[bit_count] = dec_bit;
                $display("T=%0t: *** DECODED BIT %0d = %b ***", $time, bit_count, dec_bit);
                bit_count = bit_count + 1;
            end
        end
        
        $display("\n=== RESULTS ===");
        $display("Sent: 1111 (+ tail)");
        $display("Got %0d bits:", bit_count);
        for (int i = 0; i < bit_count; i = i + 1) begin
            $display("  Bit %0d: %b", i, dec_bits[i]);
        end
        
        $finish;
    end
    
    initial begin
        #(CLOCK_PERIOD * 20000);
        $display("TIMEOUT");
        $finish;
    end
    
endmodule
