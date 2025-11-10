`timescale 1ns/1ps

module tb_surv_dump;
    localparam K = 3;
    localparam M = K - 1;
    localparam S = 1 << M;
    localparam D = 8;
    localparam Wm = 4;
    localparam G0 = 3'o7;
    localparam G1 = 3'o5;
    
    reg clk, rst;
    reg [1:0] sym_in;
    reg sym_valid;
    wire sym_ready;
    wire dec_bit;
    wire dec_bit_valid;
    reg force_state0;
    
    // Instantiate decoder
    tt_um_viterbi_core #(
        .K(K), .D(D), .Wm(Wm), .G0_OCT(G0), .G1_OCT(G1)
    ) dut (
        .clk(clk), .rst(rst),
        .rx_sym(sym_in), .rx_sym_valid(sym_valid), .rx_sym_ready(sym_ready),
        .dec_bit(dec_bit), .dec_bit_valid(dec_bit_valid),
        .force_state0(force_state0)
    );
    
    // Clock
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Encoder task - matching C golden model
    task automatic encoder;
        input [M-1:0] state_in;
        input in_bit;
        output [M-1:0] state_out;
        output [1:0] sym_out;
        reg [K-1:0] sr;
        begin
            state_out = {state_in[M-2:0], in_bit};  // LSB insertion
            sr = {state_in, in_bit};  // For polynomial application
            sym_out = {^(sr & G0), ^(sr & G1)};
        end
    endtask
    
    // Test stimulus
    reg [7:0] test_bits;
    reg [1:0] encoded_syms [0:99];
    integer sym_count;
    integer i;
    reg [M-1:0] enc_state;
    
    initial begin
        $dumpfile("tb_surv_dump.vcd");
        $dumpvars(0, tb_surv_dump);
        
        // Simple test pattern: 10101010
        test_bits = 8'b10101010;
        
        // Encode
        enc_state = 0;
        sym_count = 0;
        
        $display("=== ENCODING ===");
        for (i = 0; i < 8; i = i + 1) begin
            encoder(enc_state, test_bits[i], enc_state, encoded_syms[sym_count]);
            $display("Bit %0d: %b -> State %b -> Symbol %b", i, test_bits[i], enc_state, encoded_syms[sym_count]);
            sym_count = sym_count + 1;
        end
        
        // Tail bits
        for (i = 0; i < M; i = i + 1) begin
            encoder(enc_state, 1'b0, enc_state, encoded_syms[sym_count]);
            $display("Tail %0d: 0 -> State %b -> Symbol %b", i, enc_state, encoded_syms[sym_count]);
            sym_count = sym_count + 1;
        end
        
        // Reset decoder
        rst = 1;
        sym_valid = 0;
        force_state0 = 1;
        sym_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        // Feed symbols
        $display("\n=== DECODING ===");
        for (i = 0; i < sym_count; i = i + 1) begin
            @(posedge clk);
            sym_in = encoded_syms[i];
            sym_valid = 1;
            
            // Wait for ready
            while (!sym_ready) @(posedge clk);
            
            $display("T=%0d: Symbol %b accepted", i, sym_in);
        end
        
        @(posedge clk);
        sym_valid = 0;
        
        // Wait for output
        repeat(50) @(posedge clk);
        
        // Dump survivor memory
        $display("\n=== SURVIVOR MEMORY ===");
        for (i = 0; i < D; i = i + 1) begin
            $display("T=%0d: S0=%b S1=%b S2=%b S3=%b", i,
                dut.surv_mem.mem[i][0],
                dut.surv_mem.mem[i][1],
                dut.surv_mem.mem[i][2],
                dut.surv_mem.mem[i][3]
            );
        end
        
        $finish;
    end
    
    // Monitor outputs
    always @(posedge clk) begin
        if (dec_bit_valid) begin
            $display("OUTPUT: bit=%b at time %0t", dec_bit, $time);
        end
        
        // Monitor ACS decisions during sweep
        if (dut.state == 3'd2) begin // ST_SWEEP
            $display("  SWEEP idx=%0d: pm0=%0d pm1=%0d bm0=%0d bm1=%0d -> pm_out=%0d surv=%b",
                dut.sweep_idx, dut.pm0, dut.pm1, dut.bm0, dut.bm1, dut.pm_out, dut.surv_sel);
        end
        
        // Monitor survivor row writes
        if (dut.surv_wr_en) begin
            $display("SURV_WR T=%0d: S0=%b S1=%b S2=%b S3=%b", 
                dut.surv_wr_ptr,
                dut.surv_row[0], dut.surv_row[1], dut.surv_row[2], dut.surv_row[3]);
        end
    end
    
endmodule
