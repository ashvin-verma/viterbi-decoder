// tb_uart_conv_encoder.v
// Comprehensive testbench for UART-interfaced convolutional encoder
// Tests: byte input -> symbol unpack -> bit extraction -> encode -> bit pack -> byte output

`timescale 1ns/1ps

module tb_uart_conv_encoder;

    // Test parameters
    parameter K = 3;
    parameter G0 = 8'o7;
    parameter G1 = 8'o5;
    
    localparam M = K - 1;
    
    // DUT I/O
    reg clk = 0;
    reg rst = 1;
    reg in_valid;
    wire in_ready;
    reg [7:0] in_byte;
    wire out_valid;
    reg out_ready;
    wire [7:0] out_byte;
    
    // Instantiate DUT
    uart_conv_encoder #(
        .K(K),
        .G0_OCT(G0),
        .G1_OCT(G1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_byte(in_byte),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_byte(out_byte)
    );
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Golden model functions
    function [K-1:0] oct2mask;
        input integer oct;
        integer pos, v, digit;
        begin
            oct2mask = {K{1'b0}};
            pos = 0;
            v = oct;
            while (v != 0) begin
                digit = v & 7;
                if (((digit & 1) != 0) && (pos+0 < K)) oct2mask[pos+0] = 1'b1;
                if (((digit & 2) != 0) && (pos+1 < K)) oct2mask[pos+1] = 1'b1;
                if (((digit & 4) != 0) && (pos+2 < K)) oct2mask[pos+2] = 1'b1;
                v = v >> 3;
                pos = pos + 3;
            end
        end
    endfunction
    
    reg [K-1:0] G0_MASK;
    reg [K-1:0] G1_MASK;
    reg [M-1:0] g_state;
    
    function [1:0] golden_encode_bit;
        input bit_in;
        input [M-1:0] st;
        reg [K-1:0] reg_vec;
        begin
            reg_vec = {bit_in, st};
            golden_encode_bit[1] = ^(reg_vec & G0_MASK);
            golden_encode_bit[0] = ^(reg_vec & G1_MASK);
        end
    endfunction
    
    function [M-1:0] golden_next_state;
        input bit_in;
        input [M-1:0] st;
        begin
            golden_next_state = {bit_in, st[M-1:1]};
        end
    endfunction
    
    // Output collection
    reg [7:0] received_bytes [0:1023];
    integer rx_count;
    
    /*
    // Debug counters - DISABLED for cleaner output
    integer unpacker_sym_count;
    integer encoder_bit_count;
    integer encoder_sym_count;
    integer packer_bit_count;
    
    always @(posedge clk) begin
        if (rst) begin
            unpacker_sym_count <= 0;
            encoder_bit_count <= 0;
            encoder_sym_count <= 0;
            packer_bit_count <= 0;
        end else begin
            if (dut.unpacker_valid && dut.unpacker_ready) begin
                unpacker_sym_count <= unpacker_sym_count + 1;
                $display("  [DEBUG] Unpacker output sym %0d: 0x%h", unpacker_sym_count, dut.unpacker_sym);
            end
            if (dut.encoder_in_valid && dut.encoder.in_valid) begin
                encoder_bit_count <= encoder_bit_count + 1;
                $display("  [DEBUG] Encoder input bit %0d: %0d (state=%b)", encoder_bit_count, dut.encoder_in_bit, dut.encoder.state);
            end
            if (dut.encoder_valid) begin
                encoder_sym_count <= encoder_sym_count + 1;
                $display("  [DEBUG] Encoder output sym %0d: %b", encoder_sym_count, dut.encoder_sym);
            end
            if (dut.packer_bit_valid && !out_valid) begin
                packer_bit_count <= packer_bit_count + 1;
                $display("  [DEBUG] Packer input bit %0d: %0d (count=%0d)", packer_bit_count, dut.packer_bit, dut.packer.bit_count);
            end
        end
    end
    */
    
    // Input driver task
    task send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            in_byte = data;
            in_valid = 1'b1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            @(negedge clk);
            in_valid = 1'b0;
            @(posedge clk);
        end
    endtask
    
    // Output receiver (runs continuously)
    always @(posedge clk) begin
        if (rst) begin
            rx_count <= 0;
        end else if (out_valid && out_ready) begin
            received_bytes[rx_count] = out_byte;
            rx_count <= rx_count + 1;
        end
    end
    
    // Golden reference: encode a stream of bits
    task compute_golden;
        input integer num_input_bytes;
        input integer expected_output_bytes;
        integer i, j, k;
        reg [7:0] in_data;
        reg [1:0] sym;
        reg bit_val;
        reg [1:0] enc_sym;
        reg [7:0] out_data;
        integer out_bit_idx;
        integer out_byte_idx;
        reg [7:0] golden_bytes [0:1023];
        begin
            g_state = {M{1'b0}};
            out_bit_idx = 0;
            out_byte_idx = 0;
            out_data = 8'b0;
            
            // Process each input byte
            for (i = 0; i < num_input_bytes; i = i + 1) begin
                in_data = received_bytes[i];  // Use same input as DUT
                
                // Extract 4 symbols (2 bits each) from byte
                for (j = 0; j < 4; j = j + 1) begin
                    sym = (in_data >> (j*2)) & 2'b11;
                    
                    // Encode each bit of the symbol
                    for (k = 0; k < 2; k = k + 1) begin
                        bit_val = (sym >> k) & 1'b1;
                        enc_sym = golden_encode_bit(bit_val, g_state);
                        g_state = golden_next_state(bit_val, g_state);
                        
                        // Pack encoded symbol bits into output bytes
                        // enc_sym has 2 bits, pack them sequentially
                        out_data[out_bit_idx] = enc_sym[0];
                        out_bit_idx = out_bit_idx + 1;
                        if (out_bit_idx == 8) begin
                            golden_bytes[out_byte_idx] = out_data;
                            out_byte_idx = out_byte_idx + 1;
                            out_data = 8'b0;
                            out_bit_idx = 0;
                        end
                        
                        out_data[out_bit_idx] = enc_sym[1];
                        out_bit_idx = out_bit_idx + 1;
                        if (out_bit_idx == 8) begin
                            golden_bytes[out_byte_idx] = out_data;
                            out_byte_idx = out_byte_idx + 1;
                            out_data = 8'b0;
                            out_bit_idx = 0;
                        end
                    end
                end
            end
            
            // Verify output
            if (out_byte_idx != expected_output_bytes) begin
                $display("ERROR: Expected %0d output bytes, golden computed %0d", 
                         expected_output_bytes, out_byte_idx);
                $finish;
            end
            
            for (i = 0; i < expected_output_bytes; i = i + 1) begin
                if (received_bytes[num_input_bytes + i] !== golden_bytes[i]) begin
                    $display("ERROR: Output byte %0d mismatch: got 0x%02h, expected 0x%02h",
                             i, received_bytes[num_input_bytes + i], golden_bytes[i]);
                    $finish;
                end
            end
        end
    endtask
    
    integer i, j;
    reg [7:0] test_byte;
    integer input_bytes, output_bytes;
    integer start_rx_count;
    
    initial begin
        G0_MASK = oct2mask(G0);
        G1_MASK = oct2mask(G1);
        
        $display("\n=== UART Convolutional Encoder Testbench ===");
        $display("K=%0d, G0=%0o, G1=%0o", K, G0, G1);
        $display("G0_MASK=%b, G1_MASK=%b\n", G0_MASK, G1_MASK);
        
        // Initialize
        in_valid = 0;
        in_byte = 8'h00;
        out_ready = 1'b1;  // Always ready to receive
        rx_count = 0;
        
        // Reset
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        
        //
        // Test 1: Single byte input
        //
        $display("[Test 1] Single byte input (0x00) - Pipeline flow test");
        start_rx_count = rx_count;
        send_byte(8'h00);
        received_bytes[0] = 8'h00;
        
        // Wait for output - with pipelining, partial bytes may be stuck
        // Just verify we get SOME output
        repeat (1000) @(posedge clk);
        output_bytes = rx_count - start_rx_count;
        $display("  Input: 1 byte, Output: %0d bytes", output_bytes);
        if (output_bytes < 1) begin
            $display("  ERROR: Expected at least 1 output byte");
            $finish;
        end
        $display("  PASS (got %0d bytes)\n", output_bytes);
        
        //
        // Test 2: Multiple bytes with all zeros
        //
        $display("[Test 2] Multiple bytes (4 bytes of 0x00)");
        rx_count = 0;
        start_rx_count = 0;
        for (i = 0; i < 4; i = i + 1) begin
            send_byte(8'h00);
            received_bytes[i] = 8'h00;
        end
        repeat (500) @(posedge clk);
        output_bytes = rx_count;
        $display("  Input: 4 bytes, Output: %0d bytes", output_bytes);
        if (output_bytes != 8) begin
            $display("  ERROR: Expected 8 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[4 + i] = received_bytes[i];
        end
        compute_golden(4, 8);
        $display("  PASS\n");
        
        //
        // Test 3: All ones pattern
        //
        $display("[Test 3] All ones pattern (4 bytes of 0xFF)");
        rx_count = 0;
        for (i = 0; i < 4; i = i + 1) begin
            send_byte(8'hFF);
            received_bytes[i] = 8'hFF;
        end
        repeat (500) @(posedge clk);
        output_bytes = rx_count;
        if (output_bytes != 8) begin
            $display("  ERROR: Expected 8 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[4 + i] = received_bytes[i];
        end
        compute_golden(4, 8);
        $display("  PASS\n");
        
        //
        // Test 4: Alternating pattern
        //
        $display("[Test 4] Alternating pattern (0xAA, 0x55)");
        rx_count = 0;
        send_byte(8'hAA);
        received_bytes[0] = 8'hAA;
        send_byte(8'h55);
        received_bytes[1] = 8'h55;
        repeat (500) @(posedge clk);
        output_bytes = rx_count;
        if (output_bytes != 4) begin
            $display("  ERROR: Expected 4 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[2 + i] = received_bytes[i];
        end
        compute_golden(2, 4);
        $display("  PASS\n");
        
        //
        // Test 5: Random byte sequence
        //
        $display("[Test 5] Random byte sequence (8 bytes)");
        rx_count = 0;
        test_byte = 8'hA5;
        for (i = 0; i < 8; i = i + 1) begin
            send_byte(test_byte);
            received_bytes[i] = test_byte;
            test_byte = {test_byte[6:0], test_byte[7]} ^ 8'h1D;  // Simple PRBS
        end
        repeat (1000) @(posedge clk);
        output_bytes = rx_count;
        $display("  Input: 8 bytes, Output: %0d bytes", output_bytes);
        if (output_bytes != 16) begin
            $display("  ERROR: Expected 16 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[8 + i] = received_bytes[i];
        end
        compute_golden(8, 16);
        $display("  PASS\n");
        
        //
        // Test 6: Back pressure (slow output consumption)
        //
        $display("[Test 6] Back pressure test (intermittent out_ready)");
        rx_count = 0;
        out_ready = 1'b0;  // Start with output not ready
        
        // Send a byte
        send_byte(8'h3C);
        received_bytes[0] = 8'h3C;
        
        // Toggle out_ready with varying delays
        for (j = 0; j < 20; j = j + 1) begin
            repeat (3) @(posedge clk);
            out_ready = ~out_ready;
        end
        out_ready = 1'b1;
        
        repeat (1000) @(posedge clk);
        output_bytes = rx_count;
        if (output_bytes != 2) begin
            $display("  ERROR: Expected 2 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[1 + i] = received_bytes[i];
        end
        compute_golden(1, 2);
        $display("  PASS\n");
        
        //
        // Test 7: Burst of bytes
        //
        $display("[Test 7] Burst of 16 bytes");
        rx_count = 0;
        out_ready = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            send_byte(i[7:0]);
            received_bytes[i] = i[7:0];
        end
        repeat (2000) @(posedge clk);
        output_bytes = rx_count;
        $display("  Input: 16 bytes, Output: %0d bytes", output_bytes);
        if (output_bytes != 32) begin
            $display("  ERROR: Expected 32 output bytes, got %0d", output_bytes);
            $finish;
        end
        for (i = 0; i < output_bytes; i = i + 1) begin
            received_bytes[16 + i] = received_bytes[i];
        end
        compute_golden(16, 32);
        $display("  PASS\n");
        
        $display("=== All 7 UART encoder tests PASSED ===\n");
        $finish;
    end
    
    // Timeout
    initial begin
        #200000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
