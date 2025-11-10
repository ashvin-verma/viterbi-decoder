`timescale 1ns/1ps

module tb_traceback_simple;
    parameter M = 2;
    parameter D = 6;
    parameter S = 4;
    
    reg clk = 0;
    reg rst = 1;
    reg [2:0] wr_ptr = 0;
    reg [M-1:0] s_end = 0;
    reg force_state0 = 0;
    wire [2:0] tb_time;
    wire [M-1:0] tb_state;
    reg tb_surv_bit;
    wire dec_bit_valid;
    wire dec_bit;
    
    // Simple survivor memory - all 1s
    reg [S-1:0] surv_mem [0:D-1];
    
    always #5 clk = ~clk;
    
    assign tb_surv_bit = surv_mem[tb_time][tb_state];
    
    traceback #(.M(M), .D(D)) dut (
        .clk(clk),
        .rst(rst),
        .wr_ptr(wr_ptr),
        .s_end(s_end),
        .force_state0(force_state0),
        .tb_time(tb_time),
        .tb_state(tb_state),
        .tb_surv_bit(tb_surv_bit),
        .dec_bit_valid(dec_bit_valid),
        .dec_bit(dec_bit)
    );
    
    integer i;
    integer outputs_seen = 0;
    
    always @(posedge clk) begin
        $display("%0t: state=%0d force=%0b dec_valid=%0b tb_count=%0d", $time, dut.state, force_state0, dec_bit_valid, dut.tb_count);
    end
    
    initial begin
        // Initialize memory
        for (i = 0; i < D; i = i + 1) begin
            surv_mem[i] = 4'b1111;  // All survivor bits = 1
        end
        
        repeat(5) @(posedge clk);
        @(negedge clk);
        rst = 0;
        
        // Trigger a traceback - set inputs BEFORE posedge
        @(negedge clk);
        wr_ptr = 3;
        s_end = 2'b11;  // Start from state 3
        force_state0 = 1;
        
        @(negedge clk);
        force_state0 = 0;
        
        // Wait for output
        repeat(20) @(posedge clk);
        
        if (outputs_seen == 0) begin
            $display("FAIL: No outputs produced");
        end else begin
            $display("PASS: Module produced %0d output(s)", outputs_seen);
        end
        $finish;
    end
    
    always @(posedge clk) begin
        if (dec_bit_valid) begin
            outputs_seen = outputs_seen + 1;
            $display("  >>> Output %0d: dec_bit=%0b", outputs_seen, dec_bit);
        end
    end
    
endmodule
