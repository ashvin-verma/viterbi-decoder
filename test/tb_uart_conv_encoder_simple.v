// tb_uart_conv_encoder_simple.v
// Simplified UART encoder test - validates connectivity and basic data flow

`timescale 1ns/1ps

module tb_uart_conv_encoder_simple;

    parameter K = 3;
    parameter G0 = 8'o7;
    parameter G1 = 8'o5;
    
    reg clk = 0;
    reg rst = 1;
    reg in_valid;
    wire in_ready;
    reg [7:0] in_byte;
    wire out_valid;
    reg out_ready;
    wire [7:0] out_byte;
    
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
    
    always #5 clk = ~clk;
    
    // Monitor output
    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            out_count = out_count + 1;
            $display("  Output byte %0d: 0x%02h", out_count, out_byte);
        end
    end
    
    integer out_count;
    integer i;
    
    initial begin
        $display("\n=== UART Encoder Simple Test ===");
        $display("K=%0d, G0=%0o, G1=%0o\n", K, G0, G1);
        
        in_valid = 0;
        in_byte = 8'h00;
        out_ready = 1'b1;
        out_count = 0;
        
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        
        // Test 1: Send 4 bytes
        $display("[Test 1] Send 4 bytes of 0x00");
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            in_byte = 8'h00;
            in_valid = 1'b1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            @(negedge clk);
            in_valid = 1'b0;
            repeat (10) @(posedge clk);
        end
        
        repeat (1000) @(posedge clk);
        $display("  Received %0d output bytes", out_count);
        if (out_count > 0) begin
            $display("  PASS - Data flowing through pipeline\n");
        end else begin
            $display("  FAIL - No output received\n");
            $finish;
        end
        
        // Test 2: Send different pattern
        $display("[Test 2] Send 8 bytes with varying pattern");
        out_count = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            in_byte = i[7:0];
            in_valid = 1'b1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            @(negedge clk);
            in_valid = 1'b0;
            repeat (10) @(posedge clk);
        end
        
        repeat (2000) @(posedge clk);
        $display("  Received %0d output bytes", out_count);
        if (out_count > 0) begin
            $display("  PASS - Data flowing through pipeline\n");
        end else begin
            $display("  FAIL - No output received\n");
            $finish;
        end
        
        $display("=== All simple tests PASSED ===");
        $display("NOTE: UART encoder demonstrates basic data flow");
        $display("      Core encoding logic verified in dedicated encoder testbenches\n");
        $finish;
    end
    
    initial begin
        #100000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
