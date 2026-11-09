`timescale 1ns/1ps
module tb_smoke;
    reg clk = 0, resetn = 0;
    always #10 clk = ~clk;
    reg [17:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg [31:0] wdata = 0; reg [3:0] wstrb = 4'hF;
    wire awready, wready, bvalid, arready, rvalid; wire [1:0] bresp, rresp; wire [31:0] rdata;
    tb_fb_system dut (.clk(clk), .resetn(resetn),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready));
    integer n;
    initial begin
        for (n = 0; n < 20; n = n + 1) begin
            @(posedge clk);
            $display("t=%0t cycle %0d", $time, n);
            if (n == 5) resetn = 1;
        end
        araddr = 18'h014; arvalid = 1;
        @(posedge clk); while (!arready) @(posedge clk);
        arvalid = 0;
        @(posedge clk); while (!rvalid) @(posedge clk);
        $display("HW_CONFIG = %h", rdata);
        $finish;
    end
endmodule
