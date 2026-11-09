`timescale 1ns/1ps
// Standalone testbench for ber_tester: runs several thresholds, prints counts.
module tb_ber_tester;
`ifndef TB_K
  `define TB_K 7
  `define TB_D 42
  `define TB_G0 121
  `define TB_G1 91
`endif
`ifndef TB_LANES
  `define TB_LANES 2
`endif
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg        wr_en = 0;
    reg [4:0]  wr_addr = 0, rd_addr = 0;
    reg [31:0] wr_data = 0;
    wire [31:0] rd_data;

    ber_tester #(.K(`TB_K), .D(`TB_D), .G0_OCT(`TB_G0), .G1_OCT(`TB_G1), .LANES(`TB_LANES)) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data));

    task wr(input [4:0] a, input [31:0] d);
        begin @(negedge clk); wr_en = 1; wr_addr = a; wr_data = d; @(negedge clk); wr_en = 0; end
    endtask
    task rd(input [4:0] a, output [31:0] d);
        begin @(negedge clk); rd_addr = a; #1 d = rd_data; end
    endtask

    reg [31:0] st, bits, errs, flips, chb, cyc;
    integer n;
    task run(input [31:0] th, input [31:0] nbits);
        begin
            wr(5'd2, th); wr(5'd3, nbits); wr(5'd4, 0); wr(5'd5, 0);
            wr(5'd0, 32'd1);
            st = 1;
            while (st[0]) begin repeat (200) @(posedge clk); rd(5'd1, st); end
            rd(5'd8, bits); rd(5'd10, errs); rd(5'd12, flips); rd(5'd14, chb); rd(5'd16, cyc);
            $display("RESULT thresh=%0d p=%f bits=%0d errs=%0d flips=%0d chbits=%0d cycles=%0d chBER=%f decBER=%f status=%h",
                th, th/4294967296.0, bits, errs, flips, chb, cyc,
                flips*1.0/chb, errs*1.0/bits, st);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk); rst_n = 1;
        run(32'd0,          32'd3000);      // clean channel: must be 0 errors
        run(32'd85899346,   32'd5000);      // p = 0.02
        run(32'd214748365,  32'd5000);      // p = 0.05
        run(32'd429496730,  32'd3000);      // p = 0.10
        $finish;
    end
endmodule
