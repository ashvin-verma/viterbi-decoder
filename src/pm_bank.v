module pm_bank #(
    parameter K = 5,
    parameter M = K - 1,
    parameter S = 1 << M,
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

    output reg prev_A
);

  reg [Wm-1:0] bank0 [0:S-1];
  reg [Wm-1:0] bank1 [0:S-1];
  integer i;

  // Effective read bank: if swap_banks is pending (will take effect this edge),
  // read from the bank that will become "previous" after the swap.
  wire read_from_A = swap_banks ? ~prev_A : prev_A;

  // Combinational read
  always @(*) begin
    if (read_from_A) begin
      rd_pm0 = bank0[rd_idx0];
      rd_pm1 = bank0[rd_idx1];
    end else begin
      rd_pm0 = bank1[rd_idx0];
      rd_pm1 = bank1[rd_idx1];
    end
  end

  // Sequential operations
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < S; i = i + 1) begin
        bank0[i] <= {Wm{1'b0}};
        bank1[i] <= {Wm{1'b0}};
      end
      prev_A <= 1'b1;
    end else begin
      if (init_frame) begin
        if (prev_A) begin
          bank1[0] <= {Wm{1'b0}};
          for (i = 1; i < S; i = i + 1)
            bank1[i] <= {1'b0, {(Wm-1){1'b1}}};
        end else begin
          bank0[0] <= {Wm{1'b0}};
          for (i = 1; i < S; i = i + 1)
            bank0[i] <= {1'b0, {(Wm-1){1'b1}}};
        end
      end

      if (wr_en) begin
        if (prev_A)
          bank1[wr_idx] <= wr_pm;
        else
          bank0[wr_idx] <= wr_pm;
      end

      if (swap_banks)
        prev_A <= ~prev_A;
    end
  end

endmodule
