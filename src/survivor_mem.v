module survivor_mem #(
    parameter K = 5,
    parameter M = K - 1,
    parameter S = (1 << M),
    parameter Wm = 8,
    parameter D = 10
) (
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire [S-1:0] surv_row,

    output reg [$clog2(D)-1:0] wr_ptr,

    input wire [$clog2(S)-1:0] rd_state,
    input wire [$clog2(D)-1:0] rd_time,

    output wire surv_bit
);

  reg [S-1:0] mem [0:D-1];

  always @(posedge clk) begin
    if (rst)
      wr_ptr <= {$clog2(D){1'b0}};
    else if (wr_en)
      wr_ptr <= (wr_ptr == D - 1) ? {$clog2(D){1'b0}} : wr_ptr + 1'b1;
  end

  // Rows have no reset: the core's warm-up counter holds off the first
  // traceback until D rows have been written, so no row is read unwritten.
  always @(posedge clk) begin
    if (wr_en)
      mem[wr_ptr] <= surv_row;
  end

  // Write-first on collision (if client ever reads the row being written)
  wire [$clog2(D)-1:0] wr_idx = wr_ptr;
  assign surv_bit = (wr_en && (rd_time == wr_idx)) ? surv_row[rd_state]
                                                   : mem[rd_time][rd_state];

endmodule
