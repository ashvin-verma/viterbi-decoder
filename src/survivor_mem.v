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
    if (rst) begin
      wr_ptr <= {$clog2(D){1'b0}};
      mem[0] <= {S{1'b0}};
      mem[1] <= {S{1'b0}};
      mem[2] <= {S{1'b0}};
      mem[3] <= {S{1'b0}};
      mem[4] <= {S{1'b0}};
      mem[5] <= {S{1'b0}};
      mem[6] <= {S{1'b0}};
      mem[7] <= {S{1'b0}};
      mem[8] <= {S{1'b0}};
      mem[9] <= {S{1'b0}};
    end else if (wr_en) begin
      mem[wr_ptr] <= surv_row;
      if (wr_ptr == D - 1)
        wr_ptr <= {$clog2(D){1'b0}};
      else
        wr_ptr <= wr_ptr + 1;
    end else begin
    end
  end

  assign surv_bit = mem[rd_time][rd_state];

endmodule