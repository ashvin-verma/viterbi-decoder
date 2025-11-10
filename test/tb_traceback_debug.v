`timescale 1ns/1ps

module tb_traceback_debug;

parameter K = 3;
parameter M = K - 1;
parameter S = 1 << M;
parameter D = 6;
parameter G0_OCT = 3'o07;
parameter G1_OCT = 3'o05;

// Clock and reset
logic clk = 0;
logic rst;
logic force_state0;

// DUT
logic [1:0] rx_sym;
logic rx_sym_valid;
logic rx_sym_ready;
logic dec_bit;
logic dec_bit_valid;

tt_um_viterbi_core #(
    .K(K),
    .D(D),
    .G0_OCT(G0_OCT),
    .G1_OCT(G1_OCT)
) dut (
    .clk(clk),
    .rst(rst),
    .rx_sym_valid(rx_sym_valid),
    .rx_sym_ready(rx_sym_ready),
    .rx_sym(rx_sym),
    .dec_bit_valid(dec_bit_valid),
    .dec_bit(dec_bit),
    .force_state0(force_state0)
);

// Clock generation
always #5 clk = ~clk;

// Encoder task
task automatic encode_bit(
    input  logic       bit_in,
    input  logic [M-1:0] state_in,
    output logic [M-1:0] state_out,
    output logic       y0,
    output logic       y1
);
    logic [K-1:0] sr;
    // Convention: bit 0 (LSB) = newest input, bits [K-1:1] = state
    // So SR = {state_in, bit_in}
    sr = {state_in, bit_in};
    
    y0 = ^(sr & G0_OCT);
    y1 = ^(sr & G1_OCT);
    
    // Next state: shift left, insert bit_in at LSB
    // next_state = (state_in << 1) | bit_in, but keeping only M bits
    // Which is equivalent to: {state_in[M-2:0], bit_in}
    state_out = {state_in[M-2:0], bit_in};
endtask

// Test
reg [15:0] test_bits;
reg [M-1:0] enc_state, next_state;
reg y0, y1;
integer bit_idx, i, dec_count, errors, sym_count;
reg [15:0] decoded;
reg [9:0] expected, received;

// Monitor signals
integer commit_count, tb_start_count, tb_done_count;
integer output_count;
always @(posedge clk) begin
    if (rx_sym_valid && rx_sym_ready) begin
        sym_count = sym_count + 1;
        $display("  [T=%0d] Symbol %0d accepted: %b", $time/10, sym_count, rx_sym);
    end
    // Monitor internal DUT state
    if (dut.state == dut.ST_COMMIT) begin
        commit_count = commit_count + 1;
        $display("  [T=%0d] COMMIT %0d (best_state=%b)", $time/10, commit_count, dut.best_state);
    end
    if (dut.tb_dec_valid) begin
        tb_done_count = tb_done_count + 1;
        $display("  [T=%0d] TRACEBACK OUTPUT %0d: bit=%b", $time/10, tb_done_count, dut.dec_bit);
    end
    if (dut.tb_start) begin
        tb_start_count = tb_start_count + 1;
        $display("  [T=%0d] TRACEBACK START %0d (state=%b, time=%0d, busy=%b)", 
                 $time/10, tb_start_count, dut.tb_start_state, dut.tb_start_time, dut.tb_busy);
    end
    // Monitor OUTPUT
    if (dec_bit_valid) begin
        output_count = output_count + 1;
        $display("  [T=%0d] OUTPUT %0d: bit=%b", $time/10, output_count, dec_bit);
    end
end

initial begin
    $dumpfile("tb_traceback_debug.vcd");
    $dumpvars(0, tb_traceback_debug);
    
    sym_count = 0;
    commit_count = 0;
    tb_start_count = 0;
    tb_done_count = 0;
    output_count = 0;
    
    // Reset
    rst = 1;
    rx_sym_valid = 0;
    force_state0 = 0;  // Free-running mode
    repeat(5) @(posedge clk);
    rst = 0;
    @(posedge clk);
    
    // Test sequence: simple known pattern
    test_bits = 16'b1010_1100_1111_0000;
    enc_state = 0;
    bit_idx = 0;
    
    $display("\n=== Encoding Test Sequence ===");
    for (i = 15; i >= 0; i = i - 1) begin  // MSB first
        encode_bit(test_bits[i], enc_state, next_state, y0, y1);
        $display("Bit[%0d]=%b, State: %b -> %b, Symbols: %b%b, SR=%b%b%b", 
                 i, test_bits[i], enc_state, next_state, y0, y1,
                 test_bits[i], enc_state[1], enc_state[0]);
        
        // Send symbols to decoder
        rx_sym = {y0, y1};
        rx_sym_valid = 1;
        @(posedge clk);
        while (!rx_sym_ready) @(posedge clk);
        
        enc_state = next_state;
    end
    
    rx_sym_valid = 0;
    
    // Wait for all outputs
    $display("\n=== Waiting for outputs ===");
    repeat(100) @(posedge clk);
    
    // Now check results
    $display("\n=== Results ===");
    $display("Total monitor outputs seen: %0d", output_count);
    
    // Compare (first 10 outputs should match first 10 input bits)
    expected = test_bits[15:6];  // First 10 bits sent
    received = decoded[9:0];      // First 10 bits decoded
    errors = 0;
    
    $display("\n=== Comparison ===");
    $display("Input bits [15:6]: %b", expected);
    $display("Output bits [9:0]: %b", received);
    $display("Match: %b", expected == received);
    
    for (i = 0; i < 10; i = i + 1) begin
        if (expected[i] != received[i]) begin
            $display("ERROR at bit %0d: expected %b, got %b", i, expected[i], received[i]);
            errors = errors + 1;
        end
    end
    $display("Total errors: %0d / 10", errors);
    
    repeat(10) @(posedge clk);
    $finish;
end

// Separate always block to collect decoded bits
initial begin
    decoded = 0;
    dec_count = 0;
    
    // Wait for reset to finish
    wait(rst == 0);
    @(posedge clk);
    
    // Collect bits as they arrive
    while (dec_count < 16) begin
        @(posedge clk);
        if (dec_bit_valid) begin
            decoded[dec_count] = dec_bit;
            $display("Collected decoded bit %0d: %b", dec_count, dec_bit);
            dec_count = dec_count + 1;
        end
    end
    
    $display("Collection complete: got %0d bits", dec_count);
end

endmodule
