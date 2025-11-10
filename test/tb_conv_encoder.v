`timescale 1ns/1ps

module tb_conv_encoder;

    // Parameters
    parameter K = 3;
    parameter G0_OCT = 8'o07;
    parameter G1_OCT = 8'o05;
    parameter CLK_PERIOD = 10;  // 10ns = 100MHz
    
    // DUT signals
    reg clk;
    reg rst_n;
    reg bit_in;
    reg bit_valid;
    wire [1:0] sym_out;
    wire sym_valid;
    
    // Test control
    integer errors;
    integer test_num;
    
    // Instantiate DUT
    conv_encoder #(
        .K(K),
        .G0_OCT(G0_OCT),
        .G1_OCT(G1_OCT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .sym_out(sym_out),
        .sym_valid(sym_valid)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Helper task: Apply reset
    task apply_reset;
        begin
            rst_n = 0;
            bit_in = 0;
            bit_valid = 0;
            repeat(5) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask
    
    // Helper task: Send a bit
    task send_bit;
        input bit_val;
        begin
            @(posedge clk);
            bit_in = bit_val;
            bit_valid = 1;
            @(posedge clk);
            bit_valid = 0;
        end
    endtask
    
    // Helper task: Send a bit and check output
    task send_bit_check;
        input bit_val;
        input [1:0] expected_sym;
        begin
            @(posedge clk);
            bit_in = bit_val;
            bit_valid = 1;
            @(posedge clk);
            #1;  // Small delay to sample after clock edge
            
            if (sym_valid !== 1'b1) begin
                $display("ERROR: sym_valid not asserted when expected");
                errors = errors + 1;
            end else if (sym_out !== expected_sym) begin
                $display("ERROR: Expected symbol 2'b%b, got 2'b%b (input bit=%b)", 
                         expected_sym, sym_out, bit_val);
                errors = errors + 1;
            end else begin
                $display("  OK: Input bit=%b -> Symbol=2'b%b", bit_val, sym_out);
            end
            
            bit_valid = 0;
        end
    endtask
    
    // Helper task: Wait for idle
    task wait_idle;
        integer i;
        begin
            bit_valid = 0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk);
                #1;
                if (sym_valid === 1'b1) begin
                    $display("WARNING: sym_valid asserted during idle");
                end
            end
        end
    endtask
    
    // Golden reference function (matches C code)
    function [1:0] calc_expected_sym;
        input [1:0] state;  // Previous state (M=K-1=2 bits)
        input in_bit;       // Current input bit
        reg [2:0] sr;       // Shift register {state, in_bit}
        reg y0, y1;
        begin
            sr = {state, in_bit};
            // G0 = 7 (octal) = 3'b111
            y0 = ^(sr & 3'b111);
            // G1 = 5 (octal) = 3'b101
            y1 = ^(sr & 3'b101);
            calc_expected_sym = {y0, y1};
        end
    endfunction
    
    // Main test sequence
    initial begin
        $display("\n=== Convolutional Encoder Testbench ===");
        $display("K=%0d, G0=%o, G1=%o\n", K, G0_OCT, G1_OCT);
        
        errors = 0;
        test_num = 0;
        
        // Initialize
        apply_reset();
        
        // ===== Test 1: All zeros =====
        test_num = test_num + 1;
        $display("\n[Test %0d] All zeros input", test_num);
        apply_reset();
        
        // State starts at 00
        // Input 0: sr=000, G0=111 -> y0=0, G1=101 -> y1=0 -> sym=00
        send_bit_check(0, 2'b00);
        // State now 00
        send_bit_check(0, 2'b00);
        send_bit_check(0, 2'b00);
        send_bit_check(0, 2'b00);
        
        wait_idle();
        
        // ===== Test 2: All ones =====
        test_num = test_num + 1;
        $display("\n[Test %0d] All ones input", test_num);
        apply_reset();
        
        // State starts at 00
        // Input 1: sr=001, G0=111 -> y0=1, G1=101 -> y1=1 -> sym=11
        send_bit_check(1, 2'b11);
        // State now 01
        // Input 1: sr=011, G0=111 -> y0=0, G1=101 -> y1=0 -> sym=00
        send_bit_check(1, 2'b00);
        // State now 11
        // Input 1: sr=111, G0=111 -> y0=1, G1=101 -> y1=1 -> sym=11
        send_bit_check(1, 2'b11);
        // State wraps to 11 (stays)
        send_bit_check(1, 2'b11);
        
        wait_idle();
        
        // ===== Test 3: Alternating pattern =====
        test_num = test_num + 1;
        $display("\n[Test %0d] Alternating pattern (0,1,0,1...)", test_num);
        apply_reset();
        
        send_bit_check(0, 2'b00);  // State: 00->00
        send_bit_check(1, 2'b11);  // State: 00->01
        send_bit_check(0, 2'b10);  // State: 01->10
        send_bit_check(1, 2'b01);  // State: 10->01
        send_bit_check(0, 2'b10);  // State: 01->10
        send_bit_check(1, 2'b01);  // State: 10->01
        
        wait_idle();
        
        // ===== Test 4: Known sequence with tail =====
        test_num = test_num + 1;
        $display("\n[Test %0d] Known sequence: 1,0,1,1,0 + tail", test_num);
        apply_reset();
        
        // Manually computed using reference encoder
        send_bit_check(1, 2'b11);  // State: 00->01
        send_bit_check(0, 2'b10);  // State: 01->10
        send_bit_check(1, 2'b01);  // State: 10->01
        send_bit_check(1, 2'b10);  // State: 01->11
        send_bit_check(0, 2'b01);  // State: 11->10
        
        // Tail bits (2 zeros for K=3)
        send_bit_check(0, 2'b11);  // State: 10->00
        send_bit_check(0, 2'b00);  // State: 00->00
        
        wait_idle();
        
        // ===== Test 5: Random sequence =====
        test_num = test_num + 1;
        $display("\n[Test %0d] Random sequence (20 bits)", test_num);
        apply_reset();
        
        begin
            integer i;
            reg [1:0] state;
            reg rand_bit;
            reg [1:0] expected;
            
            state = 2'b00;
            for (i = 0; i < 20; i = i + 1) begin
                // Simple LFSR for pseudo-random bits
                rand_bit = (i & 1) ^ ((i >> 1) & 1) ^ ((i >> 3) & 1);
                expected = calc_expected_sym(state, rand_bit);
                
                send_bit_check(rand_bit, expected);
                
                // Update state
                state = {state[0], rand_bit};
            end
        end
        
        wait_idle();
        
        // ===== Test 6: Verify sym_valid timing =====
        test_num = test_num + 1;
        $display("\n[Test %0d] Verify sym_valid timing", test_num);
        apply_reset();
        
        // sym_valid should only be high when bit_valid was high on previous cycle
        @(posedge clk);
        bit_valid = 0;
        @(posedge clk);
        #1;
        if (sym_valid !== 1'b0) begin
            $display("ERROR: sym_valid high when bit_valid not asserted");
            errors = errors + 1;
        end
        
        @(posedge clk);
        bit_in = 1;
        bit_valid = 1;
        @(posedge clk);
        #1;
        if (sym_valid !== 1'b1) begin
            $display("ERROR: sym_valid not high after bit_valid");
            errors = errors + 1;
        end
        
        bit_valid = 0;
        @(posedge clk);
        #1;
        if (sym_valid !== 1'b0) begin
            $display("ERROR: sym_valid still high after bit_valid deasserted");
            errors = errors + 1;
        end
        
        wait_idle();
        
        // ===== Test 7: Burst mode =====
        test_num = test_num + 1;
        $display("\n[Test %0d] Burst mode (continuous bit_valid)", test_num);
        apply_reset();
        
        begin
            integer i;
            reg [1:0] state;
            reg [1:0] expected;
            reg [9:0] test_pattern;
            
            test_pattern = 10'b1011001101;
            state = 2'b00;
            
            for (i = 0; i < 10; i = i + 1) begin
                expected = calc_expected_sym(state, test_pattern[i]);
                
                @(posedge clk);
                bit_in = test_pattern[i];
                bit_valid = 1;
                @(posedge clk);
                #1;
                
                if (sym_out !== expected) begin
                    $display("ERROR at bit %0d: Expected 2'b%b, got 2'b%b", 
                             i, expected, sym_out);
                    errors = errors + 1;
                end
                
                state = {state[0], test_pattern[i]};
            end
            
            bit_valid = 0;
        end
        
        wait_idle();
        
        // ===== Summary =====
        $display("\n=== Test Complete ===");
        $display("Total tests: %0d", test_num);
        $display("Total errors: %0d", errors);
        
        if (errors == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** TESTS FAILED ***\n");
        end
        
        #100;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000;  // 100us timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end
    
    // Optional: Waveform dumping
    initial begin
        $dumpfile("tb_conv_encoder.vcd");
        $dumpvars(0, tb_conv_encoder);
    end

endmodule
