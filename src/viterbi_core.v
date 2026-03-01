`default_nettype none

module tt_um_viterbi_core #(
    parameter int K       = 4,
    parameter int D       = 24,
    parameter int Wm      = 4,
    parameter int G0_OCT  = 'o17,  // default (17,13) for K=4
    parameter int G1_OCT  = 'o13
)(
    input  logic        clk,
    input  logic        rst,

    // Symbol stream in (one symbol accepted per full decode burst)
    input  logic        rx_sym_valid,
    output logic        rx_sym_ready,
    input  logic [1:0]  rx_sym,

    // Decoded output (one bit per accepted symbol after warm-up)
    output logic        dec_bit_valid,
    output logic        dec_bit,

    // Tail handling
    input  logic        force_state0
);

    localparam int M            = (K>1)?(K-1):1;
    localparam int S            = 1 << M;
    localparam int Wb           = 2;                       // hard-decision BM width
    localparam int TIME_W       = (D>1) ? $clog2(D) : 1;   // circular index width
    localparam int WARM_W       = TIME_W + 1;

    typedef enum logic [2:0] { ST_IDLE, ST_INIT, ST_SWEEP, ST_COMMIT, ST_TRACE } fsm_e;
    fsm_e state, state_n;

    // Latches / indices
    logic [1:0]            rx_sym_q;
    logic                  accept_sym;
    logic [$clog2(S)-1:0]  sweep_idx;
    logic                  last_idx;

    // Trellis / ACS wires
    logic [M-1:0]          p0, p1;
    logic [1:0]            exp0, exp1;
    logic [Wb-1:0]         bm0, bm1;
    logic [Wm-1:0]         pm0, pm1, pm_out;
    logic                  surv_sel;

    // Survivor row for this symbol
    logic [S-1:0]          surv_row;

    // Best state argmin over pm_out (curr metrics at time t)
    logic [Wm-1:0]         best_metric;
    logic [$clog2(S)-1:0]  best_state;
    logic [M-1:0]          s_end_state;

    // pm_bank / survivor_mem control
    logic                  pm_wr_en, surv_wr_en, swap_banks;
    logic                  init_pending, init_frame_pulse;
    logic                  prev_is_A;
    logic [TIME_W-1:0]     surv_wr_ptr;

    // Traceback interface
    logic                  tb_busy, tb_start;
    logic [TIME_W-1:0]     tb_start_time;
    logic [M-1:0]          tb_start_state;
    logic [TIME_W-1:0]     tb_time;
    logic [M-1:0]          tb_state;
    logic                  tb_surv_bit;

    // Warm-up counter (how many rows committed)
    logic [WARM_W-1:0]     warm_cnt;
    logic                  tb_warmed_up;

    // ------------------------------------------------------------------------
    // Handshakes / simple decodes
    // ------------------------------------------------------------------------
    assign rx_sym_ready = (state == ST_IDLE);
    assign accept_sym   = rx_sym_valid && rx_sym_ready;
    assign last_idx     = (sweep_idx == S-1);
    assign pm_wr_en     = (state == ST_SWEEP);
    assign surv_wr_en   = (state == ST_COMMIT);
    assign swap_banks   = (state == ST_COMMIT);

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= ST_IDLE;
        else     state <= state_n;
    end

    always_comb begin
        state_n = state;
        unique case (state)
            ST_IDLE  : if (accept_sym)             state_n = ST_INIT;
            ST_INIT  :                              state_n = ST_SWEEP;   // 1-cycle init pulse
            ST_SWEEP : if (last_idx)               state_n = ST_COMMIT;
            ST_COMMIT:                              state_n = ST_TRACE;   // commit row, swap banks, start TB
            ST_TRACE : if (!tb_busy && !tb_start)   state_n = ST_IDLE;     // wait for TB burst to finish (tb_start guards 1-cycle busy propagation delay)
            default  :                              state_n = ST_IDLE;
        endcase
    end

    // Capture symbol at accept
    always_ff @(posedge clk or posedge rst) begin
        if (rst) rx_sym_q <= 2'b0;
        else if (accept_sym) rx_sym_q <= rx_sym;
    end

    // Sweep index
    always_ff @(posedge clk or posedge rst) begin
        if (rst) sweep_idx <= '0;
        else if (accept_sym) sweep_idx <= '0;
        else if (state==ST_SWEEP && !last_idx) sweep_idx <= sweep_idx + 1'b1;
    end

    // Survivor row accumulate
    always_ff @(posedge clk or posedge rst) begin
        if (rst) surv_row <= '0;
        else if (accept_sym) surv_row <= '0;
        else if (state==ST_SWEEP) surv_row[sweep_idx] <= surv_sel;
    end

    // Argmin (track over pm_out during sweep)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            best_metric <= {Wm{1'b1}};
            best_state  <= '0;
        end else if (accept_sym) begin
            best_metric <= {Wm{1'b1}};
            best_state  <= '0;
        end else if (state==ST_SWEEP) begin
            if (pm_out <= best_metric) begin   // tie-break toward *later* state OK
                best_metric <= pm_out;
                best_state  <= sweep_idx;
            end
        end
    end

    // Latch end-state at commit (time t)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s_end_state <= '0;
        else if (state==ST_COMMIT) s_end_state <= best_state[$bits(s_end_state)-1:0];
    end

    // One-time path-metric init pulse (seed state 0 with 0, others INF)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            init_pending     <= 1'b1;
            init_frame_pulse <= 1'b0;
        end else begin
            init_frame_pulse <= 1'b0;
            if (state==ST_IDLE && accept_sym && init_pending) begin
                init_frame_pulse <= 1'b1;
                init_pending     <= 1'b0;
            end
        end
    end

    // p0/p1 from destination state (sweep_idx)
    localparam logic [M-1:0] MSB_MASK = (M>0)? (1 << (M-1)) : '0;
    wire [M-1:0] base_pred = sweep_idx >> 1;
    assign p0 = base_pred;                 // input 0
    assign p1 = base_pred | MSB_MASK;      // input 1

    // Expected symbols for both candidates (input bit = sweep_idx[0])
    expected_bits #(.K(K), .G0_OCT(G0_OCT), .G1_OCT(G1_OCT)) u_exp0 (
        .pred(base_pred), .b(sweep_idx[0]), .expected(exp0)
    );
    expected_bits #(.K(K), .G0_OCT(G0_OCT), .G1_OCT(G1_OCT)) u_exp1 (
        .pred(p1      ), .b(sweep_idx[0]), .expected(exp1)
    );

    // Branch metric (hard decision)
    branch_metric #(.Wb(Wb)) u_bm (
        .rx_sym(rx_sym_q), .exp_sym0(exp0), .exp_sym1(exp1), .bm0(bm0), .bm1(bm1)
    );

    // Add-Compare-Select (saturating adds inside)
    acs_core #(.Wm(Wm), .Wb(Wb)) u_acs (
        .pm0(pm0), .pm1(pm1), .bm0(bm0), .bm1(bm1), .pm_out(pm_out), .surv(surv_sel)
    );

    // Path-metric double buffer
    pm_bank #(.K(K), .Wm(Wm)) u_pmbank (
        .clk(clk), .rst(rst),
        .init_frame(init_frame_pulse),
        .rd_idx0(p0), .rd_idx1(p1),
        .wr_en(pm_wr_en), .wr_idx(sweep_idx), .wr_pm(pm_out),
        .swap_banks(swap_banks),
        .rd_pm0(pm0), .rd_pm1(pm1),
        .prev_A(prev_is_A)
    );

    // Survivor circular buffer (write whole row at commit)
    survivor_mem #(.K(K), .D(D)) u_surv (
        .clk(clk), .rst(rst),
        .wr_en(surv_wr_en), .surv_row(surv_row),
        .wr_ptr(surv_wr_ptr),
        .rd_time(tb_time), .rd_state(tb_state), .surv_bit(tb_surv_bit)
    );

    // Warm-up counting and TB start generation
    // We want TB to start on the *first* commit where the buffer already holds D rows.
    // So: if (warm_cnt == D-1) on this commit, we can start now (decision depth = D-1).
    wire this_commit = (state == ST_COMMIT);
    wire [WARM_W-1:0] warm_cnt_next = warm_cnt + WARM_W'(this_commit);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            warm_cnt     <= '0;
            tb_warmed_up <= 1'b0;
        end else begin
            warm_cnt <= warm_cnt_next;
            if (!tb_warmed_up && this_commit && (warm_cnt == WARM_W'(D>0?D-1:0)))
                tb_warmed_up <= 1'b1;
        end
    end

    // Start TB immediately on commit once warmed, otherwise wait until warmed
    wire [M-1:0] s_end_mux = force_state0 ? '0 : s_end_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tb_start       <= 1'b0;
            tb_start_time  <= '0;
            tb_start_state <= '0;
        end else begin
            tb_start <= 1'b0;  // default
            if (state == ST_COMMIT) begin
                if (tb_warmed_up || (warm_cnt == WARM_W'(D>0?D-1:0))) begin
                    tb_start       <= 1'b1;
                    tb_start_state <= s_end_mux;
                    // survivor_mem presents the index of the row just written (before increment)
                    tb_start_time  <= surv_wr_ptr;
                end
            end
        end
    end

    // Traceback burst: exactly D steps; emit oldest bit (decision depth = D-1)
    traceback_v2 #(.K(K), .D(D)) u_tb (
        .clk(clk), .rst(rst),
        .start(tb_start),
        .start_time(tb_start_time),
        .start_state(tb_start_state),
        .force_state0(force_state0),
        .tb_time(tb_time),
        .tb_state(tb_state),
        .tb_surv_bit(tb_surv_bit),
        .busy(tb_busy),
        .dec_bit_valid(dec_bit_valid),
        .dec_bit(dec_bit)
    );

endmodule

`default_nettype wire
