module pm_bank #(
    parameter K = 5,
    parameter M = K - 1,
    parameter S = 2^M
    parameter Wm = 8
) (
    input logic clk,
    input logic rst,
    input logic init_frame,
    input logic [M-1:0] rd_idx0,
    input logic [M-1:0] rd_idx1,
    input logic wr_en,
    input logic [M-1:0] wr_idx,
    input logic [Wm-1:0] wr_pm,
    input logic swap_banks,

    output logic [Wm-1:0] rd_pm0,
    output logic [Wm-1:0] rd_pm1

    output logic prev_A // debug, TODO: remove
);

reg [Wm-1:0] bank0 [S-1:0];
reg [Wm-1:0] bank1 [S-1:0];

always @ (*) begin
    if (prev_A) begin
        rd_pm0 = bank0[rd_idx0];
        rd_pm1 = bank0[rd_idx1];
    end else begin
        rd_pm0 = bank1[rd_idx0];
        rd_pm1 = bank1[rd_idx1];
    end
end

always @ (posedge clk) begin
    if (rst) begin
        bank0 <= {S{Wm}'0};
        bank1 <= {S{Wm}'0};
        prev_A <= 1'b0;
    end else begin
        if (init_frame) begin
            if (prev_A) begin
                bank1[0] <= 0;
                bank1[S-1:1] <= { (S-1) { {Wm{1'b1}} } }; // Max value
            end else begin
                bank0[0] <= 0;
                bank0[S-1:1] <= { (S-1) { {Wm{1'b1}} } }; // Max value
            end
        end
        if (wr_en) begin
            if (prev_A) bank1[wr_idx] <= wr_pm;
            else bank0[wr_idx] <= wr_pm;
        end
        if (swap_banks) begin
            prev_A <= ~prev_A;
        end
    end
end

endmodule