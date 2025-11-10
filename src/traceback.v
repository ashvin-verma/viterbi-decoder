`default_nettype none

module traceback #(
    parameter int M         = 6,
    parameter int D         = 40,
    parameter int TIME_W    = (D > 1) ? $clog2(D) : 1,
    parameter int COUNT_W   = (D > 1) ? $clog2(D + 1) : 1
) (
    input  wire                 clk,
    input  wire                 rst,

    input  wire [TIME_W-1:0]    wr_ptr,
    input  wire [M-1:0]         s_end,
    input  wire                 force_state0,

    output reg  [TIME_W-1:0]    tb_time,
    output reg  [M-1:0]         tb_state,
    input  wire                 tb_surv_bit,

    output reg                  dec_bit_valid,
    output reg                  dec_bit
);

    localparam logic [TIME_W-1:0] LAST_TIME   = (D > 0) ? TIME_W'(D - 1) : {TIME_W{1'b0}};
    localparam logic [COUNT_W-1:0] TRACE_LIMIT = (D > 0) ? COUNT_W'(D - 1) : {COUNT_W{1'b0}};

    typedef enum logic [1:0] {
        TB_IDLE,
        TB_TRACE,
        TB_EMIT
    } tb_state_t;

    tb_state_t              tb_fsm;
    logic [TIME_W-1:0]      wr_ptr_q;
    logic [COUNT_W-1:0]     tb_count;
    logic                   tb_surv_bit_d;
    logic                   start_trace;
    logic                   force_state0_q;
    logic                   trace_request;

    assign start_trace  = (wr_ptr_q != wr_ptr);
    assign trace_request = start_trace || (force_state0 && !force_state0_q);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr_q <= {TIME_W{1'b0}};
            force_state0_q <= 1'b0;
        end else begin
            wr_ptr_q <= wr_ptr;
            force_state0_q <= force_state0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tb_fsm         <= TB_IDLE;
            tb_time        <= {TIME_W{1'b0}};
            tb_state       <= {M{1'b0}};
            tb_count       <= {COUNT_W{1'b0}};
            dec_bit_valid  <= 1'b0;
            dec_bit        <= 1'b0;
            tb_surv_bit_d  <= 1'b0;
        end else begin
            dec_bit_valid <= 1'b0;
            tb_surv_bit_d <= tb_surv_bit;
            case (tb_fsm)
                TB_IDLE: begin
                    tb_count <= {COUNT_W{1'b0}};
                    if (trace_request) begin
                        tb_fsm   <= TB_TRACE;
                        tb_time  <= wr_ptr;
                        tb_state <= force_state0 ? {M{1'b0}} : s_end;
                    end
                end
                TB_TRACE: begin
                    tb_time <= (tb_time == {TIME_W{1'b0}}) ? LAST_TIME : (tb_time - 1'b1);
                    if (M == 1) begin
                        tb_state <= {tb_surv_bit_d};
                    end else begin
                        tb_state <= {tb_surv_bit_d, tb_state[M-1:1]};
                    end
                    tb_count <= tb_count + 1'b1;
                    if (tb_count == TRACE_LIMIT) begin
                        tb_fsm <= TB_EMIT;
                    end
                end
                TB_EMIT: begin
                    dec_bit       <= tb_surv_bit_d;
                    dec_bit_valid <= 1'b1;
                    tb_fsm        <= TB_IDLE;
                end
                default: tb_fsm <= TB_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
