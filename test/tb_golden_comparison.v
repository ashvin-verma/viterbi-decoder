// Golden model comparison testbench for K=5 Viterbi decoder
// Compares DUT output against a cycle-accurate golden Viterbi model
`timescale 1ns/1ps
`default_nettype none

module tb_golden_comparison();

    parameter K = 5;
    parameter M = K - 1;
    parameter S = 1 << M;
    parameter D = 24;
    parameter WM = 6;
    parameter G0_OCT = 8'o23;
    parameter G1_OCT = 8'o35;
    parameter CLOCK_PERIOD = 10;

    // Test configuration
    parameter L_INFO = 32;                  // info bits
    parameter L_TOTAL = L_INFO + M;         // info + tail
    parameter FLUSH = D - 1;                // flush symbols to push all bits out

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

    // ========================================================================
    // Encoder (matches RTL expected_bits convention)
    // ========================================================================
    function automatic [1:0] encode_sym(
        input logic in_bit,
        input logic [M-1:0] state_in
    );
        logic [K-1:0] sr;
        begin
            sr = {state_in, in_bit};
            encode_sym[1] = ^(sr & G0_OCT[K-1:0]);
            encode_sym[0] = ^(sr & G1_OCT[K-1:0]);
        end
    endfunction

    function automatic [M-1:0] next_enc_state(
        input logic in_bit,
        input logic [M-1:0] state_in
    );
        next_enc_state = {state_in[M-2:0], in_bit};
    endfunction

    // ========================================================================
    // Golden Viterbi decoder model (persistent state)
    // ========================================================================
    integer golden_pm [0:S-1];     // path metrics (persistent across steps)
    logic [S-1:0] golden_surv;     // survivor bits for current step

    task golden_init();
        integer s;
        begin
            for (s = 0; s < S; s = s + 1)
                golden_pm[s] = (s == 0) ? 0 : 999;
        end
    endtask

    task golden_step(
        input [1:0] rx_symbols,
        output [S-1:0] survivor_bits,
        output [M-1:0] best_state_out
    );
        integer s, pred0_idx, pred1_idx;
        logic [K-1:0] sr0, sr1;
        logic [1:0] exp0, exp1;
        integer bm0, bm1, m0, m1;
        integer new_pm [0:S-1];
        integer best_metric;
        begin
            for (s = 0; s < S; s = s + 1) begin
                pred0_idx = s >> 1;
                pred1_idx = (s >> 1) | (1 << (M-1));

                sr0 = {pred0_idx[M-1:0], s[0]};
                exp0[1] = ^(sr0 & G0_OCT[K-1:0]);
                exp0[0] = ^(sr0 & G1_OCT[K-1:0]);

                sr1 = {pred1_idx[M-1:0], s[0]};
                exp1[1] = ^(sr1 & G0_OCT[K-1:0]);
                exp1[0] = ^(sr1 & G1_OCT[K-1:0]);

                bm0 = ((rx_symbols[1] != exp0[1]) ? 1 : 0) +
                       ((rx_symbols[0] != exp0[0]) ? 1 : 0);
                bm1 = ((rx_symbols[1] != exp1[1]) ? 1 : 0) +
                       ((rx_symbols[0] != exp1[0]) ? 1 : 0);

                m0 = golden_pm[pred0_idx] + bm0;
                m1 = golden_pm[pred1_idx] + bm1;

                if (m1 < m0) begin
                    new_pm[s] = m1;
                    survivor_bits[s] = 1;
                end else begin
                    new_pm[s] = m0;
                    survivor_bits[s] = 0;
                end
            end

            // Find best state
            best_metric = new_pm[0];
            best_state_out = 0;
            for (s = 1; s < S; s = s + 1) begin
                if (new_pm[s] < best_metric) begin
                    best_metric = new_pm[s];
                    best_state_out = s[M-1:0];
                end
            end

            // Persist path metrics for next step
            for (s = 0; s < S; s = s + 1)
                golden_pm[s] = new_pm[s];
        end
    endtask

    // ========================================================================
    // DUT send helper
    // ========================================================================
    task send_symbol(input [1:0] sym);
        integer timeout;
        begin
            // Wait for ready: advance clock FIRST so we see post-NBA state
            // (avoids delta-cycle race where ready reflects stale FSM state)
            timeout = 0;
            @(posedge clk);
            while (!rx_sym_ready) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("ERROR: send_symbol timeout waiting for ready");
                    $finish;
                end
            end
            rx_sym = sym;
            rx_sym_valid = 1;
            @(posedge clk);
            rx_sym_valid = 0;
        end
    endtask

    // ========================================================================
    // Concurrent decoded bit collector
    // ========================================================================
    reg [0:255] dec_bits;
    integer dec_count;

    always @(posedge clk) begin
        if (dec_bit_valid && !rst) begin
            dec_bits[dec_count] = dec_bit;
            dec_count = dec_count + 1;
        end
    end

    // ========================================================================
    // Main test
    // ========================================================================
    integer i, errors;
    logic [M-1:0] enc_state;
    logic [1:0] coded_sym;
    logic [0:127] info_bits;
    logic [1:0] all_symbols [0:127];
    integer sym_count;

    // Golden model storage
    logic [S-1:0] surv_history [0:127];
    logic [M-1:0] best_history [0:127];

    initial begin
        $dumpfile("tb_golden_comparison.vcd");
        $dumpvars(0, tb_golden_comparison);

        $display("========================================================");
        $display("Golden Model Comparison (K=%0d, D=%0d)", K, D);
        $display("========================================================");

        // Generate deterministic test pattern
        info_bits = '0;
        info_bits[0]  = 1; info_bits[1]  = 1; info_bits[2]  = 1; info_bits[3]  = 1;
        info_bits[4]  = 0; info_bits[5]  = 0; info_bits[6]  = 0; info_bits[7]  = 0;
        info_bits[8]  = 1; info_bits[9]  = 0; info_bits[10] = 1; info_bits[11] = 0;
        info_bits[12] = 1; info_bits[13] = 1; info_bits[14] = 0; info_bits[15] = 0;
        info_bits[16] = 0; info_bits[17] = 1; info_bits[18] = 0; info_bits[19] = 1;
        info_bits[20] = 1; info_bits[21] = 0; info_bits[22] = 0; info_bits[23] = 1;
        info_bits[24] = 0; info_bits[25] = 0; info_bits[26] = 1; info_bits[27] = 1;
        info_bits[28] = 1; info_bits[29] = 0; info_bits[30] = 1; info_bits[31] = 0;

        $write("Info bits: ");
        for (i = 0; i < L_INFO; i = i + 1) $write("%b", info_bits[i]);
        $display("");

        // Encode
        enc_state = 0;
        sym_count = 0;
        $display("\nEncoding %0d info + %0d tail bits:", L_INFO, M);
        for (i = 0; i < L_TOTAL; i = i + 1) begin
            if (i < L_INFO)
                coded_sym = encode_sym(info_bits[i], enc_state);
            else
                coded_sym = encode_sym(1'b0, enc_state);

            if (i < L_INFO)
                enc_state = next_enc_state(info_bits[i], enc_state);
            else
                enc_state = next_enc_state(1'b0, enc_state);

            all_symbols[sym_count] = coded_sym;
            sym_count = sym_count + 1;

            if (i < 8 || i >= L_INFO)
                $display("  [%2d] bit=%b -> sym=%b%b", i,
                    (i < L_INFO) ? info_bits[i] : 1'b0,
                    coded_sym[1], coded_sym[0]);
        end

        // Add flush symbols
        $display("\nAppending %0d flush symbols (all-zero)", FLUSH);
        for (i = 0; i < FLUSH; i = i + 1) begin
            all_symbols[sym_count] = 2'b00;
            sym_count = sym_count + 1;
        end
        $display("Total symbols to send: %0d", sym_count);

        // Run golden model
        $display("\nRunning golden model...");
        golden_init();
        for (i = 0; i < L_TOTAL; i = i + 1) begin
            golden_step(all_symbols[i], surv_history[i], best_history[i]);
            if (i < 4 || i >= L_TOTAL - 2)
                $display("  Step %2d: rx=%b%b, best_state=%04b",
                    i, all_symbols[i][1], all_symbols[i][0], best_history[i]);
        end

        // Run DUT
        $display("\nRunning DUT...");
        rst = 1;
        rx_sym_valid = 0;
        force_state0 = 1;
        dec_count = 0;
        dec_bits = '0;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        for (i = 0; i < sym_count; i = i + 1) begin
            send_symbol(all_symbols[i]);
        end

        // Wait for remaining outputs
        repeat(200) @(posedge clk);

        // Comparison
        $display("\n========================================================");
        $display("COMPARISON");
        $display("========================================================");
        $display("Decoded %0d bits (expected >= %0d)", dec_count, L_INFO);

        if (dec_count < L_INFO) begin
            $display("FAIL: Not enough decoded bits (%0d < %0d)", dec_count, L_INFO);
            $finish;
        end

        errors = 0;
        for (i = 0; i < L_INFO; i = i + 1) begin
            if (dec_bits[i] !== info_bits[i]) begin
                $display("  Bit %2d: expected %b, got %b  MISMATCH", i, info_bits[i], dec_bits[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS: All %0d info bits match", L_INFO);
        end else begin
            $display("FAIL: %0d / %0d bit errors", errors, L_INFO);
        end

        $display("========================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLOCK_PERIOD * 500000);
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
