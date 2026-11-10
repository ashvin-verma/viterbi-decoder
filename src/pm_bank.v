module pm_bank #(
    parameter K = 5,
    parameter M = K - 1,
    parameter S = 1 << M,  // 2^M using shift operator
    parameter Wm = 8
) (
    input wire clk,
    input wire rst,
    input wire init_frame,
    input wire [M-1:0] rd_idx0,
    input wire [M-1:0] rd_idx1,
    input wire wr_en,
    input wire [M-1:0] wr_idx,
    input wire [Wm-1:0] wr_pm,
    input wire swap_banks,

    output reg [Wm-1:0] rd_pm0,
    output reg [Wm-1:0] rd_pm1,

    output reg prev_A // debug, TODO: remove
);

  reg [Wm-1:0] bank0 [0:S-1];
  reg [Wm-1:0] bank1 [0:S-1];
  integer i;

  // Combinational read from previous bank
  always @(*) begin
    if (prev_A) begin
      rd_pm0 = bank0[rd_idx0];
      rd_pm1 = bank0[rd_idx1];
    end else begin
      rd_pm0 = bank1[rd_idx0];
      rd_pm1 = bank1[rd_idx1];
    end
  end

  // Bank pointer: the only state here that needs a reset.
  always @(posedge clk) begin
    if (rst)
      prev_A <= 1'b1;  // After reset, Bank A is previous
    else if (swap_banks)
      prev_A <= ~prev_A;
  end

  // Bank storage has no reset: init_frame seeds the previous bank before the
  // first sweep, and every sweep writes all S entries of the current bank before
  // the swap, so no entry is read before it is written. Resetting these 2*S*Wm
  // flops only cost area and a large rst buffer tree.
  always @(posedge clk) begin
    if (init_frame) begin
      if (prev_A) begin
        bank0[0] <= {Wm{1'b0}};  // PM for state 0
        for (i = 1; i < S; i = i + 1)
          bank0[i] <= {Wm{1'b1}};  // INF for all other states
      end else begin
        bank1[0] <= {Wm{1'b0}};
        for (i = 1; i < S; i = i + 1)
          bank1[i] <= {Wm{1'b1}};
      end
    end

    // Write to current bank (opposite of previous)
    if (wr_en) begin
      if (prev_A)
        bank1[wr_idx] <= wr_pm;
      else
        bank0[wr_idx] <= wr_pm;
    end
  end

endmodule