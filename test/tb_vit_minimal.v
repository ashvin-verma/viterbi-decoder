// Minimal Viterbi test - inline everything
`timescale 1ns/1ps

module tb_vit_minimal();
    parameter K = 3;
    parameter M = 2;
    parameter S = 4;

    reg clk, rst, start;
    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255];
    wire done;
    wire [7:0] out_len;
    wire bits_out [0:255];

    viterbi_simple_v2 #(.K(3)) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .frame_len(frame_len),
        .syms_in(syms_in),
        .done(done),
        .out_len(out_len),
        .bits_out(bits_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer i, errors;
    reg [K-1:0] r;
    reg [M-1:0] st;

    initial begin
        $display("\n=== Minimal Viterbi Test ===\n");

        // Encode pattern: bit 8 = 1, rest = 0
        st = 0;
        for (i = 0; i < 32; i = i + 1) begin
            r = {st, (i == 8) ? 1'b1 : 1'b0};
            syms_in[i] = {^(r & 3'b111), ^(r & 3'b101)};
            st = {st[0], (i == 8) ? 1'b1 : 1'b0};  // LSB insertion
        end
        frame_len = 32;

        // Reset (using exact sequence from tb_state_test)
        rst = 1; start = 0;
        #30;
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Starting decoder, frame_len=%0d", frame_len);
        start = 1;
        @(posedge clk);
        #1;
        $display("After start clock: state=%0d", dut.state);
        start = 0;

        // Wait and monitor
        i = 0;
        while (i < 200 && !done) begin
            @(posedge clk);
            #1;  // Small delay after clock to let signals settle
            if (i < 50)
                $display("Cycle %3d: state=%0d t=%0d tb_t=%0d done=%b",
                         i, dut.state, dut.t, dut.tb_t, done);
            i = i + 1;
        end

        if (done)
            $display("Done asserted at cycle %0d", i);

        if (!done) begin
            $display("TIMEOUT - state=%0d t=%0d tb_t=%0d\n",
                     dut.state, dut.t, dut.tb_t);
            $finish;
        end

        // Print decoded bits
        $display("\nDecoded bits:");
        for (i = 0; i < 32; i = i + 4) begin
            $display("  [%2d-%2d] %b %b %b %b",
                i, i+3, bits_out[i], bits_out[i+1], bits_out[i+2], bits_out[i+3]);
        end

        // Check
        errors = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if ((i == 8 && !bits_out[i]) || (i != 8 && bits_out[i])) begin
                if (errors < 10)
                    $display("ERR bit[%0d]: exp=%b got=%b", i, (i==8), bits_out[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("✓ PASS: All %0d bits correct!\n", out_len);
        else
            $display("✗ FAIL: %0d/%0d errors\n", errors, out_len);

        $finish;
    end

endmodule
