// Test K=4 Viterbi decoder
`timescale 1ns/1ps

module tb_k4();
    parameter K = 4;
    parameter M = 3;
    parameter S = 8;

    reg clk, rst, start;
    reg [7:0] frame_len;
    reg [1:0] syms_in [0:255];
    wire done;
    wire [7:0] out_len;
    wire bits_out [0:255];

    // K=4: G0=15 (octal) = 4'b1111, G1=17 (octal) = 4'b1111
    viterbi_simple_v2 #(
        .K(4),
        .G0(4'b1111),  // G0=17 octal
        .G1(4'b1101)   // G1=15 octal
    ) dut (
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
        $display("\n=== K=4 Viterbi Test ===");
        $display("States: %0d, G0=4'b1111, G1=4'b1101\n", S);

        // Encode pattern: bit 12 = 1, rest = 0
        st = 0;
        for (i = 0; i < 32; i = i + 1) begin
            r = {st, (i == 12) ? 1'b1 : 1'b0};
            syms_in[i] = {^(r & 4'b1111), ^(r & 4'b1101)};
            st = {st[M-2:0], (i == 12) ? 1'b1 : 1'b0};  // LSB insertion
        end
        frame_len = 32;

        // Reset
        rst = 1; start = 0;
        #30;
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Starting decoder...");
        $display("Before start: state=%0d", dut.state);
        start = 1;
        @(posedge clk);
        #1;
        $display("After start pulse: state=%0d", dut.state);
        start = 0;

        // Wait
        i = 0;
        while (i < 200 && !done) begin
            @(posedge clk);
            #1;
            if (i < 10)
                $display("Cycle %0d: state=%0d t=%0d", i, dut.state, dut.t);
            i = i + 1;
        end

        if (!done) begin
            $display("TIMEOUT at cycle %0d\n", i);
            $finish;
        end

        $display("Completed at cycle %0d\n", i);

        // Check
        errors = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if ((i == 12 && !bits_out[i]) || (i != 12 && bits_out[i])) begin
                if (errors < 10)
                    $display("ERR bit[%0d]: exp=%b got=%b", i, (i==12), bits_out[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("✓ PASS: All 32 bits correct for K=4!\n");
        else
            $display("✗ FAIL: %0d errors\n", errors);

        $finish;
    end

endmodule
