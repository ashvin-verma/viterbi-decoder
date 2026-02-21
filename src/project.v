/*
 * Tiny Tapeout Viterbi Decoder — Parameterizable Modular Design
 * Rate 1/2 convolutional code decoder, K=3 through K=9+
 * Default: K=5, G0=23o, G1=35o (WiFi/WiMAX standard)
 *
 * UART byte interface:
 *   Input:  uio_in[7:0]  = 4 packed 2-bit symbols per byte
 *           ui_in[0]     = byte_valid
 *           ui_in[3]     = start (begin decoding)
 *           ui_in[4]     = read_ack
 *   Output: uio_out[7:0] = 8 decoded bits per byte
 *           uo_out[0]    = byte_in_ready
 *           uo_out[1]    = byte_out_valid
 *           uo_out[3]    = busy
 *           uo_out[4]    = done
 */

`default_nettype none

module tt_um_ashvin_viterbi #(
    parameter K         = 5,
    parameter G0_OCT    = 'o23,
    parameter G1_OCT    = 'o35,
    parameter MAX_FRAME = 32,
    parameter PM_WIDTH  = 8
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam M          = K - 1;
    localparam NUM_STATES = 1 << M;
    localparam Wb         = 2;
    localparam STATE_BITS = (M < 1) ? 1 : M;
    localparam FRAME_BITS = 6;

    wire rst = ~rst_n;

    // Interface
    wire byte_valid = ui_in[0];
    wire start_cmd  = ui_in[3];
    wire read_ack   = ui_in[4];

    // FSM states
    localparam [2:0] S_IDLE       = 3'd0,
                     S_RECEIVE    = 3'd1,
                     S_ACS_INIT   = 3'd2,
                     S_ACS        = 3'd3,
                     S_ACS_COMMIT = 3'd4,
                     S_FIND_BEST  = 3'd5,
                     S_TRACE      = 3'd6,
                     S_OUTPUT     = 3'd7;

    reg [2:0] state;

    // Symbol buffer
    reg [MAX_FRAME*2-1:0] sym_buf;
    reg [FRAME_BITS-1:0]  sym_count;
    reg [FRAME_BITS-1:0]  frame_len;

    // ACS sweep
    reg [FRAME_BITS-1:0]  acs_time;
    reg [STATE_BITS-1:0]  sweep_idx;

    localparam SURV_ABITS = $clog2(MAX_FRAME);

    // Survivor memory interface
    reg                       surv_init_frame;
    reg                       surv_wr_en;
    reg  [NUM_STATES-1:0]     surv_row;
    wire [SURV_ABITS-1:0]     surv_wr_ptr;
    reg  [STATE_BITS-1:0]     surv_rd_state;
    reg  [SURV_ABITS-1:0]     surv_rd_time;
    wire                      surv_bit;

    // PM bank interface
    reg                    pm_init_frame;
    reg                    pm_swap_banks;
    reg                    pm_wr_en;
    reg  [STATE_BITS-1:0]  pm_wr_idx;
    reg  [PM_WIDTH-1:0]    pm_wr_data;
    wire [PM_WIDTH-1:0]    pm_rd0;
    wire [PM_WIDTH-1:0]    pm_rd1;
    wire                   pm_prev_A;

    // Find-best
    reg [STATE_BITS-1:0]  scan_idx;
    reg [PM_WIDTH-1:0]    best_metric;
    reg [STATE_BITS-1:0]  best_state;

    // Traceback
    reg [FRAME_BITS-1:0]  tb_time;
    reg [STATE_BITS-1:0]  tb_state;

    // Output buffer
    reg [MAX_FRAME-1:0]   out_buf;
    reg [FRAME_BITS-1:0]  out_total;
    reg                   frame_done;
    reg [7:0]             out_byte_reg;
    reg                   out_byte_valid;
    reg [FRAME_BITS-1:0]  out_byte_pos;

    // ACS init counter
    reg [1:0] init_cnt;

    // =========================================================================
    // ACS datapath
    // =========================================================================
    wire [STATE_BITS-1:0] pred0_acs = sweep_idx >> 1;
    wire [STATE_BITS-1:0] pred1_acs = (sweep_idx >> 1) | (1 << (M - 1));
    wire                  input_bit = sweep_idx[0];

    // Muxed read addresses: during FIND_BEST, read scan_idx via rd_idx0
    wire [M-1:0] pm_rd_addr0 = (state == S_FIND_BEST) ? scan_idx[M-1:0] : pred0_acs[M-1:0];
    wire [M-1:0] pm_rd_addr1 = pred1_acs[M-1:0];

    wire [1:0] current_sym = sym_buf[acs_time * 2 +: 2];

    wire [1:0] exp0, exp1;
    wire [Wb-1:0] bm0, bm1;
    wire [PM_WIDTH-1:0] acs_pm_out;
    wire                acs_surv;

    // =========================================================================
    // Status outputs
    // =========================================================================
    wire byte_in_ready = (state == S_IDLE) || (state == S_RECEIVE);
    wire busy          = (state != S_IDLE) && (state != S_RECEIVE) && (state != S_OUTPUT);

    assign uo_out[0]   = byte_in_ready;
    assign uo_out[1]   = out_byte_valid;
    assign uo_out[2]   = 1'b0;
    assign uo_out[3]   = busy;
    assign uo_out[4]   = frame_done;
    assign uo_out[7:5] = 3'b0;

    assign uio_out = out_byte_valid ? out_byte_reg : 8'b0;
    assign uio_oe  = {8{out_byte_valid}};

    wire _unused = &{ena, 1'b0};

    // =========================================================================
    // Submodule instantiations
    // =========================================================================

    expected_bits #(
        .K(K), .G0_OCT(G0_OCT), .G1_OCT(G1_OCT)
    ) eb0 (
        .pred     (pred0_acs[M-1:0]),
        .b        (input_bit),
        .expected (exp0)
    );

    expected_bits #(
        .K(K), .G0_OCT(G0_OCT), .G1_OCT(G1_OCT)
    ) eb1 (
        .pred     (pred1_acs[M-1:0]),
        .b        (input_bit),
        .expected (exp1)
    );

    branch_metric #(.Wb(Wb)) bm_inst (
        .rx_sym   (current_sym),
        .exp_sym0 (exp0),
        .exp_sym1 (exp1),
        .bm0      (bm0),
        .bm1      (bm1)
    );

    acs_core #(.Wm(PM_WIDTH), .Wb(Wb)) acs_inst (
        .pm0    (pm_rd0),
        .pm1    (pm_rd1),
        .bm0    (bm0),
        .bm1    (bm1),
        .pm_out (acs_pm_out),
        .surv   (acs_surv)
    );

    pm_bank #(.K(K), .Wm(PM_WIDTH)) pm_inst (
        .clk        (clk),
        .rst        (rst),
        .init_frame (pm_init_frame),
        .rd_idx0    (pm_rd_addr0),
        .rd_idx1    (pm_rd_addr1),
        .wr_en      (pm_wr_en),
        .wr_idx     (pm_wr_idx[M-1:0]),
        .wr_pm      (pm_wr_data),
        .swap_banks (pm_swap_banks),
        .rd_pm0     (pm_rd0),
        .rd_pm1     (pm_rd1),
        .prev_A     (pm_prev_A)
    );

    survivor_mem #(.K(K), .Wm(PM_WIDTH), .D(MAX_FRAME)) surv_inst (
        .clk        (clk),
        .rst        (rst),
        .init_frame (surv_init_frame),
        .wr_en      (surv_wr_en),
        .surv_row   (surv_row),
        .wr_ptr     (surv_wr_ptr),
        .rd_state   (surv_rd_state[M-1:0]),
        .rd_time    (surv_rd_time),
        .surv_bit   (surv_bit)
    );

    // =========================================================================
    // FSM
    // =========================================================================
    integer k;

    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            sym_count      <= 0;
            frame_len      <= 0;
            acs_time       <= 0;
            sweep_idx      <= 0;
            scan_idx       <= 0;
            best_metric    <= {PM_WIDTH{1'b1}};
            best_state     <= 0;
            tb_time        <= 0;
            tb_state       <= 0;
            out_buf        <= 0;
            out_total      <= 0;
            frame_done     <= 0;
            out_byte_reg   <= 0;
            out_byte_valid <= 0;
            out_byte_pos   <= 0;
            sym_buf        <= 0;
            surv_init_frame <= 0;
            surv_wr_en     <= 0;
            surv_row       <= 0;
            surv_rd_state  <= 0;
            surv_rd_time   <= 0;
            pm_init_frame  <= 0;
            pm_swap_banks  <= 0;
            pm_wr_en       <= 0;
            pm_wr_idx      <= 0;
            pm_wr_data     <= 0;
            init_cnt       <= 0;
        end else begin
            // Deassert one-shot signals each cycle
            pm_init_frame   <= 0;
            pm_swap_banks   <= 0;
            pm_wr_en        <= 0;
            surv_init_frame <= 0;
            surv_wr_en      <= 0;

            case (state)

                S_IDLE: begin
                    frame_done     <= 0;
                    out_byte_valid <= 0;
                    sym_count      <= 0;
                    if (byte_valid) begin
                        sym_buf[7:0] <= uio_in;
                        sym_count    <= 4;
                        state        <= S_RECEIVE;
                    end
                end

                S_RECEIVE: begin
                    out_byte_valid <= 0;
                    if (byte_valid && sym_count < MAX_FRAME) begin
                        sym_buf[sym_count*2 +: 8] <= uio_in;
                        if (sym_count + 4 <= MAX_FRAME)
                            sym_count <= sym_count + 4;
                        else
                            sym_count <= MAX_FRAME[FRAME_BITS-1:0];
                    end
                    if (start_cmd && sym_count > 0) begin
                        frame_len <= sym_count;
                        init_cnt  <= 0;
                        state     <= S_ACS_INIT;
                    end
                end

                S_ACS_INIT: begin
                    case (init_cnt)
                        2'd0: begin
                            pm_init_frame   <= 1;
                            surv_init_frame <= 1;
                            init_cnt        <= 2'd1;
                        end
                        2'd1: begin
                            pm_swap_banks <= 1;
                            init_cnt      <= 2'd2;
                        end
                        2'd2: begin
                            acs_time  <= 0;
                            sweep_idx <= 0;
                            surv_row  <= 0;
                            state     <= S_ACS;
                        end
                        default: init_cnt <= 0;
                    endcase
                end

                S_ACS: begin
                    pm_wr_en   <= 1;
                    pm_wr_idx  <= sweep_idx;
                    pm_wr_data <= acs_pm_out;
                    surv_row[sweep_idx] <= acs_surv;

                    if (sweep_idx == NUM_STATES - 1) begin
                        state <= S_ACS_COMMIT;
                    end else begin
                        sweep_idx <= sweep_idx + 1;
                    end
                end

                S_ACS_COMMIT: begin
                    surv_wr_en    <= 1;
                    pm_swap_banks <= 1;

                    if (acs_time == frame_len - 1) begin
                        state         <= S_FIND_BEST;
                    end else begin
                        acs_time  <= acs_time + 1;
                        sweep_idx <= 0;
                        state     <= S_ACS;
                    end
                end

                S_FIND_BEST: begin
                    // 1-cycle delay: lets last survivor write complete
                    // before traceback reads mem[frame_len-1]
                    tb_state      <= 0;
                    surv_rd_state <= 0;
                    tb_time       <= frame_len - 1;
                    surv_rd_time  <= frame_len - 1;
                    state         <= S_TRACE;
                end

                S_TRACE: begin
                    out_buf[tb_time] <= tb_state[0];

                    tb_state      <= {surv_bit, tb_state[STATE_BITS-1:1]};
                    surv_rd_state <= {surv_bit, tb_state[STATE_BITS-1:1]};

                    if (tb_time == 0) begin
                        out_total      <= frame_len - M;
                        out_byte_pos   <= 0;
                        out_byte_valid <= 0;
                        state          <= S_OUTPUT;
                    end else begin
                        tb_time      <= tb_time - 1;
                        surv_rd_time <= tb_time - 1;
                    end
                end

                S_OUTPUT: begin
                    if (!out_byte_valid) begin
                        if (out_byte_pos < out_total) begin
                            for (k = 0; k < 8; k = k + 1) begin
                                if (out_byte_pos + k < MAX_FRAME)
                                    out_byte_reg[k] <= out_buf[out_byte_pos + k];
                                else
                                    out_byte_reg[k] <= 1'b0;
                            end
                            out_byte_valid <= 1;
                        end else begin
                            frame_done <= 1;
                            if (start_cmd)
                                state <= S_IDLE;
                        end
                    end else if (read_ack) begin
                        out_byte_valid <= 0;
                        if (out_byte_pos + 8 >= out_total)
                            out_byte_pos <= out_total;
                        else
                            out_byte_pos <= out_byte_pos + 8;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
