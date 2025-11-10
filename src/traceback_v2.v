`default_nettype none

module traceback_v2 #(
    parameter int K = 7,
    parameter int M = K - 1,
    parameter int D = 40
) (
    input  wire clk,
    input  wire rst,

    input  wire start,
    input  wire [($clog2(D) > 0 ? $clog2(D) : 1)-1:0] start_time,
    input  wire [M-1:0]                                start_state,
    input  wire                                        force_state0,

    output reg  [($clog2(D) > 0 ? $clog2(D) : 1)-1:0]  tb_time,
    output reg  [M-1:0]                                tb_state,
    input  wire                                        tb_surv_bit,

    output reg                                         busy,
    output reg                                         dec_bit_valid,
    output reg                                         dec_bit
);

    localparam int TIME_W  = (D > 1) ? $clog2(D) : 1;
    localparam int COUNT_W = (D > 1) ? $clog2(D) : 1;

    typedef enum logic [1:0] {
        TB_IDLE,
        TB_PRIME,
        TB_RUN
    } tb_state_e;

    tb_state_e          tb_fsm;
    reg [COUNT_W-1:0]   depth;
    reg                 surv_bit_q;
`ifdef TRACEBACK_V2_DEBUG
    integer start_count;
    integer done_count;
`endif

    wire [TIME_W-1:0] prev_time = (tb_time == {TIME_W{1'b0}})
                                  ? TIME_W'(D > 0 ? D - 1 : 0)
                                  : (tb_time - TIME_W'(1));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tb_fsm        <= TB_IDLE;
            busy          <= 1'b0;
            depth         <= {COUNT_W{1'b0}};
            tb_time       <= {TIME_W{1'b0}};
            tb_state      <= {M{1'b0}};
            dec_bit_valid <= 1'b0;
            dec_bit       <= 1'b0;
            surv_bit_q    <= 1'b0;
`ifdef TRACEBACK_V2_DEBUG
            start_count   <= 0;
            done_count    <= 0;
`endif
        end else begin
            dec_bit_valid <= 1'b0;
            surv_bit_q    <= tb_surv_bit;

            case (tb_fsm)
                TB_IDLE: begin
                    if (start) begin
                        busy          <= 1'b1;
                        depth         <= {COUNT_W{1'b0}};
                        tb_time       <= start_time;
                        tb_state      <= force_state0 ? {M{1'b0}} : start_state;
                        tb_fsm        <= TB_PRIME;
`ifdef TRACEBACK_V2_DEBUG
                        start_count   <= start_count + 1;
`endif
                    end
                end
                TB_PRIME: begin
                    tb_fsm <= TB_RUN;
                end
                TB_RUN: begin
                    tb_state <= {surv_bit_q, tb_state[M-1:1]};
                    tb_time  <= prev_time;
                    depth    <= depth + COUNT_W'(1);
                    if (depth == COUNT_W'(D > 0 ? D - 1 : 0)) begin
                        // Output survivor bit directly (matches C golden model)
                        dec_bit       <= surv_bit_q;
                        dec_bit_valid <= 1'b1;
                        busy          <= 1'b0;
                        tb_fsm        <= TB_IDLE;
`ifdef TRACEBACK_V2_DEBUG
                        done_count    <= done_count + 1;
`endif
                    end
                end
                default: tb_fsm <= TB_IDLE;
            endcase
        end
    end

`ifdef TRACEBACK_V2_DEBUG
    final begin
        $display("TRACEBACK_V2 stats: start=%0d done=%0d", start_count, done_count);
    end
`endif

endmodule

`default_nettype wire
