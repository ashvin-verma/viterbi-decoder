`default_nettype none

module traceback_v2 #(
    parameter int K = 7,
    parameter int M = K - 1,
    parameter int D = 40
)(
    input  wire clk,
    input  wire rst,

    // Single-cycle start for one traceback burst
    input  wire start,
    input  wire [((D>1)?$clog2(D):1)-1:0] start_time,   // row index = newest row (t): (wr_ptr-1)
    input  wire [M-1:0]                   start_state,  // end state at time t (or 0 if forced)
    input  wire                           force_state0,

    // Survivor read interface
    output reg  [((D>1)?$clog2(D):1)-1:0] tb_time,      // drives survivor_mem.rd_time
    output reg  [M-1:0]                   tb_state,     // drives survivor_mem.rd_state
    input  wire                           tb_surv_bit,  // survivor_mem.surv_bit

    // Status + decoded bit (1 pulse per burst)
    output reg                            busy,
    output reg                            dec_bit_valid,
    output reg                            dec_bit
);

    localparam int TIME_W  = (D>1)?$clog2(D):1;
    localparam int COUNT_W = (D>1)?$clog2(D):1;

    typedef enum logic [1:0] { TB_IDLE, TB_PRIME, TB_RUN } tb_e;
    tb_e fsm;

    reg [COUNT_W-1:0] depth;       // counts 0..D-1
    reg               surv_q;      // registered survivor bit from current (time,state)

    // Prev time index (wrap)
    wire [TIME_W-1:0] time_prev =
        (tb_time == {TIME_W{1'b0}}) ? TIME_W'(D>0?D-1:0) : (tb_time - TIME_W'(1));

    // State predecessor given bit (shift-in at MSB)
    function automatic [M-1:0] pred_state(input [M-1:0] s, input bit b);
        pred_state = {b, s[M-1:1]};
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fsm           <= TB_IDLE;
            busy          <= 1'b0;
            depth         <= '0;
            tb_time       <= '0;
            tb_state      <= '0;
            dec_bit_valid <= 1'b0;
            dec_bit       <= 1'b0;
            surv_q        <= 1'b0;
        end else begin
            // default outputs
            dec_bit_valid <= 1'b0;

            // always capture current survivor bit (for use next cycle)
            surv_q <= tb_surv_bit;

            unique case (fsm)
            TB_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy     <= 1'b1;
                    depth    <= '0;
                    tb_time  <= start_time;
                    tb_state <= force_state0 ? '0 : start_state;
                    fsm      <= TB_PRIME;      // allow 1 cycle for first surv read
                end
            end

            TB_PRIME: begin
                // tb_surv_bit is now valid for (tb_time, tb_state).
                // Take the first traceback step using the combinational read.
                tb_state <= pred_state(tb_state, tb_surv_bit);
                tb_time  <= time_prev;
                depth    <= COUNT_W'(1);
                fsm      <= TB_RUN;
            end

            TB_RUN: begin
                // Step one time back using combinational survivor read
                // (tb_surv_bit reflects current tb_time/tb_state registered values)
                tb_state <= pred_state(tb_state, tb_surv_bit);
                tb_time  <= time_prev;
                depth    <= depth + COUNT_W'(1);

                if (depth == COUNT_W'(D>0?D-1:0)) begin
                    dec_bit       <= tb_state[0];
                    dec_bit_valid <= 1'b1;
                    busy          <= 1'b0;
                    fsm           <= TB_IDLE;
                end
            end

            default: fsm <= TB_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
