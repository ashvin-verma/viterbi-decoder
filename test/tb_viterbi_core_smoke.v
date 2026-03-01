`timescale 1ns/1ps
`default_nettype none

module tb_viterbi_core_smoke;

    localparam int K       = 5;
    localparam int M       = (K > 1) ? (K - 1) : 0;
    localparam int D       = 24;
    localparam int L_INFO  = 32;
    localparam int TAIL    = (K > 1) ? (K - 1) : 0;
    localparam int FLUSH   = D - 1;
    localparam int G0_OCT  = 'o23;
    localparam int G1_OCT  = 'o35;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic        rx_sym_valid = 1'b0;
    logic [1:0]  rx_sym       = 2'b0;
    wire         rx_sym_ready;
    wire         dec_bit_valid;
    wire         dec_bit;
    logic        force_state0 = 1'b1;

    tt_um_viterbi_core #(
        .K(K), .D(D), .Wm(6),
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

    // Encoder function (matches golden comparison TB convention)
    function automatic logic [1:0] enc_sym(input logic bit_in,
                                           input logic [M-1:0] state_in);
        logic [K-1:0] sr;
        sr = {state_in, bit_in};
        enc_sym[1] = ^(sr & G0_OCT[K-1:0]);
        enc_sym[0] = ^(sr & G1_OCT[K-1:0]);
    endfunction

    function automatic logic [M-1:0] next_enc_state(input logic bit_in,
                                                     input logic [M-1:0] state_in);
        if (M == 0) next_enc_state = '0;
        else        next_enc_state = {state_in[M-2:0], bit_in};
    endfunction

    // Clock-first send pattern (avoids delta-cycle race)
    task automatic send_symbol(input logic [1:0] sym);
        int timeout;
        timeout = 0;
        @(posedge clk);
        while (!rx_sym_ready) begin
            @(posedge clk);
            timeout++;
            if (timeout > 300) begin
                $fatal(1, "send_symbol timeout");
            end
        end
        rx_sym      = sym;
        rx_sym_valid = 1'b1;
        @(posedge clk);
        rx_sym_valid = 1'b0;
    endtask

    // Info bits (packed vector, same type as golden comparison TB)
    logic [0:L_INFO-1] info_bits;

    // Always-block decoded bit collector
    reg [0:255] dec_bits;
    int dec_count;

    always @(posedge clk) begin
        if (dec_bit_valid && !rst) begin
            dec_bits[dec_count] = dec_bit;
            dec_count = dec_count + 1;
        end
    end

    // Main test
    logic [M-1:0] enc_state;
    logic [1:0] sym;
    int i, errors;

    initial begin
        // Same pattern as golden comparison TB (known to decode correctly)
        info_bits[0]  = 1; info_bits[1]  = 1; info_bits[2]  = 1; info_bits[3]  = 1;
        info_bits[4]  = 0; info_bits[5]  = 0; info_bits[6]  = 0; info_bits[7]  = 0;
        info_bits[8]  = 1; info_bits[9]  = 0; info_bits[10] = 1; info_bits[11] = 0;
        info_bits[12] = 1; info_bits[13] = 1; info_bits[14] = 0; info_bits[15] = 0;
        info_bits[16] = 0; info_bits[17] = 1; info_bits[18] = 0; info_bits[19] = 1;
        info_bits[20] = 1; info_bits[21] = 0; info_bits[22] = 0; info_bits[23] = 1;
        info_bits[24] = 0; info_bits[25] = 0; info_bits[26] = 1; info_bits[27] = 1;
        info_bits[28] = 1; info_bits[29] = 0; info_bits[30] = 1; info_bits[31] = 0;

        $write("Info bits (first 8): ");
        for (i = 0; i < 8; i++) $write("%0d", info_bits[i]);
        $display("");

        dec_count = 0;
        dec_bits  = '0;

        // Reset
        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Encode and send info bits
        enc_state = '0;
        for (i = 0; i < L_INFO; i++) begin
            sym = enc_sym(info_bits[i], enc_state);
            enc_state = next_enc_state(info_bits[i], enc_state);
            send_symbol(sym);
        end

        // Tail bits
        for (i = 0; i < TAIL; i++) begin
            sym = enc_sym(1'b0, enc_state);
            enc_state = next_enc_state(1'b0, enc_state);
            send_symbol(sym);
        end

        // Flush symbols
        for (i = 0; i < FLUSH; i++) begin
            send_symbol(2'b00);
        end

        // Wait for remaining outputs
        repeat(200) @(posedge clk);

        // Verify
        $display("Decoded %0d bits (need %0d)", dec_count, L_INFO);

        if (dec_count < L_INFO) begin
            $fatal(1, "Not enough decoded bits: %0d < %0d", dec_count, L_INFO);
        end

        errors = 0;
        for (i = 0; i < L_INFO; i++) begin
            if (dec_bits[i] !== info_bits[i]) begin
                $display("  Bit %0d: expected %0d, got %0d", i, info_bits[i], dec_bits[i]);
                errors++;
            end
        end

        if (errors > 0) begin
            $fatal(1, "decode mismatch: %0d/%0d errors", errors, L_INFO);
        end

        $display("viterbi_core SMOKE PASS (K=%0d, D=%0d, %0d bits)", K, D, L_INFO);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(10 * 500000);
        $fatal(1, "test timeout");
    end

endmodule

`default_nettype wire
