`default_nettype none

module tt_um_viterbi_core #(
    parameter int K       = 4,
    parameter int D       = 24,
    parameter int Wm      = 4,
    parameter int G0_OCT  = 'o17,  // K=4 default (17,13)
    parameter int G1_OCT  = 'o13
)(
    input  logic        clk,
    input  logic        rst,

    // Symbol stream input
    input  logic        rx_sym_valid,
    output logic        rx_sym_ready,
    input  logic [1:0]  rx_sym,

    // Decoded output stream
    output logic        dec_bit_valid,
    output logic        dec_bit,

    // Tail handling
    input  logic        force_state0
);

    localparam int M  = (K > 1) ? (K - 1) : 1;
    localparam int S  = 1 << M;
    localparam int Wb = 2;

    initial begin
        if (K < 2) begin
            $error("viterbi_core: K must be >= 2");
        end
    end

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SWEEP,
        ST_COMMIT
    } state_t;

    state_t state, state_next;

    logic [1:0]                   rx_sym_q;
    logic                         accept_sym;
    logic [$clog2(S)-1:0]         sweep_idx;
    logic                         last_idx;
    logic [M-1:0]                 p0;
    logic [M-1:0]                 p1;
    logic [1:0]                   exp0;
    logic [1:0]                   exp1;
    logic [Wb-1:0]                bm0;
    logic [Wb-1:0]                bm1;
    logic [Wm-1:0]                pm0;
    logic [Wm-1:0]                pm1;
    logic [Wm-1:0]                pm_out;
    logic                         surv_sel;
    logic [S-1:0]                 surv_row;
    logic                         swap_banks;
    logic                         surv_wr_en;
    logic                         pm_wr_en;
    logic                         init_pending;
    logic                         init_frame_pulse;
    logic [Wm-1:0]                best_metric;
    logic [M-1:0]                 best_state;
    logic [M-1:0]                 s_end_state;
    logic                         prev_bank_sel;
    logic [$clog2(D)-1:0]         surv_wr_ptr;
    logic [$clog2(D)-1:0]         tb_time;
    logic [M-1:0]                 tb_state;
    logic                         trace_surv_bit;
    logic                         tb_dec_valid;
    logic                         tb_dec_bit;

    assign rx_sym_ready = (state == ST_IDLE);
    assign accept_sym   = rx_sym_valid && rx_sym_ready;
    assign last_idx     = (sweep_idx == S-1);
    assign pm_wr_en     = (state == ST_SWEEP);
    assign surv_wr_en   = (state == ST_COMMIT);
    assign swap_banks   = (state == ST_COMMIT);

    // FSM --------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        state_next = state;
        unique case (state)
            ST_IDLE: begin
                if (accept_sym) begin
                    state_next = ST_SWEEP;
                end
            end
            ST_SWEEP: begin
                if (last_idx) begin
                    state_next = ST_COMMIT;
                end
            end
            ST_COMMIT: begin
                state_next = ST_IDLE;
            end
            default: state_next = ST_IDLE;
        endcase
    end

    // Symbol capture ---------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sym_q <= 2'b0;
        end else if (accept_sym) begin
            rx_sym_q <= rx_sym;
        end
    end

    // Sweep index ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sweep_idx <= {$clog2(S){1'b0}};
        end else if (accept_sym) begin
            sweep_idx <= {$clog2(S){1'b0}};
        end else if (state == ST_SWEEP) begin
            if (!last_idx) begin
                sweep_idx <= sweep_idx + 1'b1;
            end
        end
    end

    // Survivor row accumulation ----------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            surv_row <= {S{1'b0}};
        end else if (accept_sym) begin
            surv_row <= {S{1'b0}};
        end else if (state == ST_SWEEP) begin
            surv_row[sweep_idx] <= surv_sel;
        end
    end

    // Track best state -------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            best_metric <= {Wm{1'b1}};
            best_state  <= {M{1'b0}};
        end else if (accept_sym) begin
            best_metric <= {Wm{1'b1}};
            best_state  <= {M{1'b0}};
        end else if (state == ST_SWEEP) begin
            if (pm_out < best_metric) begin
                best_metric <= pm_out;
                best_state  <= sweep_idx;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s_end_state <= {M{1'b0}};
        end else if (state == ST_COMMIT) begin
            s_end_state <= best_state;
        end
    end

    // Path-metric init pulse -------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            init_pending     <= 1'b1;
            init_frame_pulse <= 1'b0;
        end else begin
            init_frame_pulse <= 1'b0;
            if (accept_sym && init_pending) begin
                init_frame_pulse <= 1'b1;
                init_pending     <= 1'b0;
            end
        end
    end

    // Branch infrastructure --------------------------------------------------
    localparam logic [M-1:0] MSB_MASK = (1 << (M-1));
    logic [M-1:0] base_pred;

    assign base_pred = sweep_idx >> 1;
    assign p0        = base_pred;
    assign p1        = base_pred | MSB_MASK;

    expected_bits #(
        .K      (K),
        .G0_OCT (G0_OCT),
        .G1_OCT (G1_OCT)
    ) expect0 (
        .pred    (p0),
        .b       (1'b0),
        .expected(exp0)
    );

    expected_bits #(
        .K      (K),
        .G0_OCT (G0_OCT),
        .G1_OCT (G1_OCT)
    ) expect1 (
        .pred    (p1),
        .b       (1'b1),
        .expected(exp1)
    );

    branch_metric #(
        .Wb(Wb)
    ) branch_metric_hd (
        .rx_sym   (rx_sym_q),
        .exp_sym0 (exp0),
        .exp_sym1 (exp1),
        .bm0      (bm0),
        .bm1      (bm1)
    );

    acs_core #(
        .Wm(Wm),
        .Wb(Wb)
    ) acs (
        .pm0    (pm0),
        .pm1    (pm1),
        .bm0    (bm0),
        .bm1    (bm1),
        .pm_out (pm_out),
        .surv   (surv_sel)
    );

    pm_bank #(
        .K (K),
        .Wm(Wm)
    ) pm_buffer (
        .clk        (clk),
        .rst        (rst),
        .init_frame (init_frame_pulse),
        .rd_idx0    (p0),
        .rd_idx1    (p1),
        .wr_en      (pm_wr_en),
        .wr_idx     (sweep_idx),
        .wr_pm      (pm_out),
        .swap_banks (swap_banks),
        .rd_pm0     (pm0),
        .rd_pm1     (pm1),
        .prev_A     (prev_bank_sel)
    );

    survivor_mem #(
        .K (K),
        .Wm(Wm),
        .D (D)
    ) surv_mem (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (surv_wr_en),
        .surv_row(surv_row),
        .wr_ptr  (surv_wr_ptr),
        .rd_state(tb_state),
        .rd_time (tb_time),
        .surv_bit(trace_surv_bit)
    );

    wire [M-1:0] s_end_mux = force_state0 ? {M{1'b0}} : s_end_state;

    traceback #(
        .M (M),
        .D (D)
    ) tb_core (
        .clk          (clk),
        .rst          (rst),
        .wr_ptr       (surv_wr_ptr),
        .s_end        (s_end_mux),
        .force_state0 (force_state0),
        .tb_time      (tb_time),
        .tb_state     (tb_state),
        .tb_surv_bit  (trace_surv_bit),
        .dec_bit_valid(tb_dec_valid),
        .dec_bit      (tb_dec_bit)
    );

    assign dec_bit_valid = tb_dec_valid;
    assign dec_bit       = tb_dec_bit;

endmodule

`default_nettype wire
