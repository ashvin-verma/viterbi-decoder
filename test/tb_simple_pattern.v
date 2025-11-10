`timescale 1ns/1ps

module tb_simple_pattern;
    localparam K = 3;
    localparam M = K - 1;
    localparam S = 1 << M;
    localparam D = 8;
    localparam Wm = 4;
    localparam G0 = 3'o7;
    localparam G1 = 3'o5;
    
    reg clk, rst;
    reg [1:0] rx_sym;
    reg rx_sym_valid;
    wire rx_sym_ready;
    wire dec_bit;
    wire dec_bit_valid;
    reg force_state0;
    
    // Instantiate decoder
    tt_um_viterbi_core #(
        .K(K), .D(D), .Wm(Wm), .G0_OCT(G0), .G1_OCT(G1)
    ) dut (
        .clk(clk), .rst(rst),
        .rx_sym(rx_sym), .rx_sym_valid(rx_sym_valid), .rx_sym_ready(rx_sym_ready),
        .dec_bit(dec_bit), .dec_bit_valid(dec_bit_valid),
        .force_state0(force_state0)
    );
    
    // Clock
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Encoder task - matching C golden model
    task automatic encode_bit;
        input [M-1:0] state_in;
        input in_bit;
        output [M-1:0] state_out;
        output y0, y1;
        reg [K-1:0] sr;
        begin
            state_out = {state_in[M-2:0], in_bit};  // LSB insertion
            sr = {state_in, in_bit};  // For polynomial application
            y0 = ^(sr & G0);
            y1 = ^(sr & G1);
        end
    endtask
    
    task send_symbol;
        input [1:0] sym;
        begin
            @(posedge clk);
            rx_sym = sym;
            rx_sym_valid = 1;
            while (!rx_sym_ready) @(posedge clk);
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask
    
    // Test
    integer i;
    reg [M-1:0] enc_state;
    reg y0, y1;
    reg [7:0] test_pattern;
    reg [63:0] decoded_bits;
    integer dec_count;
    
    // Continuous output collection
    always @(posedge clk) begin
        if (dec_bit_valid) begin
            decoded_bits[dec_count] = dec_bit;
            dec_count = dec_count + 1;
            $display("[%0t] Decoded bit %0d: %b", $time, dec_count-1, dec_bit);
        end
    end
    
    // Monitor traceback activity
    always @(posedge clk) begin
        if (dec_bit_valid) begin
            $display("[%0t] OUTPUT: bit=%b (state=%d, busy=%b, tb_start=%b)", 
                $time, dec_bit, dut.state, dut.tb_busy, dut.tb_start);
        end
        if (dut.tb_start) begin
            $display("[%0t] TB_START: time=%0d, state=%0d, s_end_mux=%0d", 
                $time, dut.tb_start_time, dut.tb_start_state, dut.s_end_mux);
        end
        if (dut.surv_wr_en) begin
            $display("[%0t] SURV_WR: ptr=%0d, row=%b", 
                $time, dut.surv_wr_ptr, dut.surv_row);
        end
    end
    
    initial begin
        $dumpfile("tb_simple_pattern.vcd");
        $dumpvars(0, tb_simple_pattern);
        
        // Test pattern: 01010101 (bit 0=0, bit 1=1, bit 2=0, etc.)
        test_pattern = 8'b10101010;  // Reversed because Verilog bit order is [7:0]
        
        $display("=== Test Pattern: 01010101 ===\n");
        
        // Reset
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        rx_sym = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        // Encode and send
        enc_state = 0;
        dec_count = 0;
        decoded_bits = 0;
        $display("Encoding:");
        for (i = 0; i < 8; i = i + 1) begin
            encode_bit(enc_state, test_pattern[i], enc_state, y0, y1);
            $display("  Bit %0d: %b -> State %b -> Symbol %b%b", 
                    i, test_pattern[i], enc_state, y0, y1);
            send_symbol({y0, y1});
        end
        
        // Tail bits
        $display("\nTail bits:");
        for (i = 0; i < M; i = i + 1) begin
            encode_bit(enc_state, 1'b0, enc_state, y0, y1);
            $display("  Tail %0d: 0 -> State %b -> Symbol %b%b", 
                    i, enc_state, y0, y1);
            send_symbol({y0, y1});
        end
        
        // Wait for all outputs
        $display("\nWaiting for outputs...");
        repeat(100) @(posedge clk);
        
        // Compare
        $display("\n=== Comparison ===");
        $display("Sent     : %b", test_pattern);
        $display("Received : %b", decoded_bits[7:0]);
        
        if (decoded_bits[7:0] == test_pattern) begin
            $display("✓ PERFECT MATCH!");
        end else begin
            $display("✗ MISMATCH!");
            for (i = 0; i < 8; i = i + 1) begin
                if (decoded_bits[i] != test_pattern[i]) begin
                    $display("  Bit %0d: expected %b, got %b", 
                            i, test_pattern[i], decoded_bits[i]);
                end
            end
        end
        
        $display("\nTotal decoded bits: %0d", dec_count);
        
        $finish;
    end
    
endmodule
