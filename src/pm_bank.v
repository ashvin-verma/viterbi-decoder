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

  // Sequential operations: reset, init, write, swap
  always @(posedge clk) begin
    if (rst) begin
      // Reset both banks to zero
      for (i = 0; i < S; i = i + 1) begin
        bank0[i] <= {Wm{1'b0}};
        bank1[i] <= {Wm{1'b0}};
      end
      prev_A <= 1'b1;  // After reset, Bank A is previous
    end else begin
      // init_frame: initialize current bank for new frame
      if (init_frame) begin
        if (prev_A) begin
          // Bank B is current
          bank1[0] <= {Wm{1'b0}};  // PM for state 0
          for (i = 1; i < S; i = i + 1) begin
            bank1[i] <= {Wm{1'b1}};  // INF for all other states
          end
        end else begin
          // Bank A is current
          bank0[0] <= {Wm{1'b0}};
          for (i = 1; i < S; i = i + 1) begin
            bank0[i] <= {Wm{1'b1}};  // INF
          end
        end
      end
      
      // Write to current bank
      if (wr_en) begin
        if (prev_A) begin
          bank1[wr_idx] <= wr_pm;  // Write to Bank B (current)
        end else begin
          bank0[wr_idx] <= wr_pm;  // Write to Bank A (current)
        end
      end
      
      // Swap banks (toggle prev_A)
      if (swap_banks) begin
        prev_A <= ~prev_A;
      end
    end
  end

endmodule