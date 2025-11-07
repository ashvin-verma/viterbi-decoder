module survivor_mem #(
    parameter K = 5,
    parameter M = K - 1,
    parameter S = 2^M,
    parameter Wm = 8,
    parameter D = 10
) (
    input logic clk,
    input logic rst,
    input logic wr_ptr,
    input logic [S-1:0] rd_state,
    input logic [D-1:0] rd_time,

    output logic surv_bit
);

reg [S-1:0] mem [D-1:0];



assign surv_bit = mem[rd_time][rd_state];

endmodule