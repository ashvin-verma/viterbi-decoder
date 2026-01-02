// Simple Viterbi decoder test
`timescale 1ns/1ps

module simple_test;
    reg clk, rst_n, ena;
    reg [7:0] ui_in, uio_in;
    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_ashvin_viterbi dut (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .ui_in(ui_in), .uio_in(uio_in),
        .uo_out(uo_out), .uio_out(uio_out), .uio_oe(uio_oe)
    );

    // Clock
    always #5 clk = ~clk;

    // Encoder function matching decoder's expected format
    function [1:0] encode;
        input [1:0] state;
        input bit_in;
        reg [2:0] r;
        begin
            r = {state, bit_in};
            encode = {^(r & 3'b111), ^(r & 3'b101)};  // G0=7, G1=5
        end
    endfunction

    integer i, errors, timeout;
    reg [1:0] enc_state;
    reg [1:0] symbols [0:7];
    reg [7:0] test_bits;
    reg [7:0] decoded;

    initial begin
        $display("=== Simple Viterbi Test ===");
        clk = 0; rst_n = 0; ena = 1;
        ui_in = 0; uio_in = 0;

        // Reset
        #100 rst_n = 1;
        #100;

        // Test pattern matching cocotb: [1, 0, 1, 1, 0, 1, 0, 0] (LSB first in array)
        test_bits = 8'b00101101;  // bit[0]=1, bit[1]=0, bit[2]=1, etc.
        $display("Input bits: %b", test_bits);

        // Encode
        enc_state = 0;
        for (i = 0; i < 8; i = i + 1) begin
            symbols[i] = encode(enc_state, test_bits[i]);
            enc_state = {enc_state[0], test_bits[i]};
        end

        $display("Encoded symbols:");
        for (i = 0; i < 8; i = i + 1)
            $display("  sym[%0d] = %b", i, symbols[i]);

        // Feed symbols to decoder
        for (i = 0; i < 8; i = i + 1) begin
            // Wait for rx_ready
            timeout = 0;
            while (!(uo_out[0]) && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("FAIL: Timeout waiting for rx_ready at symbol %0d", i);
                $finish;
            end

            // Send symbol
            ui_in = {4'b0, symbols[i], 1'b1};  // sym[1:0] << 1 | valid
            @(posedge clk);
            ui_in = 0;
            repeat(3) @(posedge clk);
        end

        $display("All symbols sent, starting decode...");

        // Start decode
        ui_in = 8'h08;  // start bit
        @(posedge clk);
        ui_in = 0;
        repeat(5) @(posedge clk);

        // Wait for decode to complete (busy goes low)
        timeout = 0;
        while (uo_out[3] && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 500) begin
            $display("FAIL: Timeout waiting for decode to complete");
            $finish;
        end
        $display("Decode completed in %0d cycles", timeout);
        repeat(10) @(posedge clk);

        // Read decoded bits
        decoded = 0;
        for (i = 0; i < 8; i = i + 1) begin
            timeout = 0;
            while (!(uo_out[1]) && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("FAIL: Timeout waiting for out_valid at bit %0d", i);
                $finish;
            end

            decoded[i] = uo_out[2];

            // Acknowledge
            ui_in = 8'h10;  // read_ack
            @(posedge clk);
            ui_in = 0;
            repeat(3) @(posedge clk);
        end

        $display("Decoded bits: %b", decoded);

        // Verify
        errors = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (decoded[i] !== test_bits[i]) errors = errors + 1;
        end

        $display("Bit errors: %0d / 8", errors);

        if (errors == 0)
            $display("=== TEST PASSED ===");
        else
            $display("=== TEST FAILED ===");

        $finish;
    end

endmodule
