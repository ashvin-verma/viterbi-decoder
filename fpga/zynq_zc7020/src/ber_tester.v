// =============================================================================
// ber_tester.v -- On-chip bit-error-rate tester for the Viterbi decoder
//
// Everything runs in the PL at the fabric clock; the host only programs the
// channel crossover threshold and reads counters:
//
//   PRBS-31 source -> conv encoder -> BSC (xorshift128 RNG vs threshold)
//        -> tt_um_viterbi_core (NORM=1, streaming) -> compare with delayed
//           source bits -> error counters
//
// LANES independent copies run in parallel (different seeds) to multiply
// throughput. The channel flips each code bit independently with
// probability THRESH / 2^32, i.e. a binary symmetric channel -- exactly the
// channel seen by a hard-decision receiver for BPSK over AWGN with
// p = Q(sqrt(2 R Eb/N0)).
//
// Register map (word index = byte offset / 4, block is 0x80 bytes):
//   0x00 CTRL       W   [0]=start (clear + run) [1]=stop [2]=snapshot
//   0x04 STATUS     R   [0]=running [1]=finished [15:8]=LANES [19:16]=K
//   0x08 THRESH     RW  flip threshold (p * 2^32)
//   0x0C MAXBITS_LO RW  stop after this many decoded bits (0 = no limit)
//   0x10 MAXBITS_HI RW
//   0x14 MAXERRS    RW  stop after this many decoded bit errors (0 = none)
//   0x18 SEED       RW
//   0x20/24 BITS    R   decoded bits compared   (snapshot, lo/hi)
//   0x28/2C ERRS    R   decoded bit errors      (snapshot)
//   0x30/34 FLIPS   R   channel bits flipped    (snapshot)
//   0x38/3C CHBITS  R   channel code bits sent  (snapshot)
//   0x40/44 CYCLES  R   clock cycles while running (snapshot)
// Snapshots are taken on CTRL[2] and automatically when a run finishes.
// =============================================================================

`default_nettype none

module ber_tester #(
    parameter K      = 7,
    parameter D      = 42,
    parameter G0_OCT = 'o171,
    parameter G1_OCT = 'o133,
    parameter LANES  = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        wr_en,
    input  wire [4:0]  wr_addr,     // word index
    input  wire [31:0] wr_data,
    input  wire [4:0]  rd_addr,     // word index
    output reg  [31:0] rd_data
);
    localparam M = K - 1;
    localparam [3:0] K4 = K;
    localparam [7:0] L8 = LANES;

    // ---------------------------------------------------------------- regs
    reg [31:0] thresh, maxerrs, seed;
    reg [63:0] maxbits;
    reg        running, finished;
    reg [2:0]  lane_rst_cnt;
    reg [63:0] c_bits, c_errs, c_flips, c_chbits, c_cycles;
    reg [63:0] s_bits, s_errs, s_flips, s_chbits, s_cycles;

    wire start_cmd = wr_en && wr_addr == 5'd0 && wr_data[0];
    wire stop_cmd  = wr_en && wr_addr == 5'd0 && wr_data[1];
    wire snap_cmd  = wr_en && wr_addr == 5'd0 && wr_data[2];
    wire lane_rst  = !rst_n || (lane_rst_cnt != 3'd0);

    // ---------------------------------------------------------------- lanes
    wire [LANES-1:0] l_dec, l_err, l_sym;
    wire [2*LANES-1:0] l_flips;

    genvar g;
    generate
        for (g = 0; g < LANES; g = g + 1) begin : lane
            // xorshift128 RNG, steps every cycle
            reg [31:0] rx, ry, rz, rw, rw_prev;
            wire [31:0] t = rx ^ (rx << 11);
            // PRBS-31 data source
            reg [30:0] prbs;
            wire src_bit = prbs[30] ^ prbs[27];
            // Encoder state
            reg [M-1:0] enc_state;
            wire [1:0] code;
            expected_bits #(.K(K), .RATE(2), .G0_OCT(G0_OCT), .G1_OCT(G1_OCT), .G2_OCT(0))
                u_enc (.pred(enc_state), .b(src_bit), .expected(code));

            wire flip0 = rw      < thresh;
            wire flip1 = rw_prev < thresh;
            wire [1:0] noisy = code ^ {flip0, flip1};

            wire sym_ready, dec_valid, dec_bit;
            wire sym_valid = running && !lane_rst;
            wire accept = sym_valid && sym_ready;

            tt_um_viterbi_core #(
                .K(K), .D(D), .Wm(8), .RATE(2),
                .G0_OCT(G0_OCT), .G1_OCT(G1_OCT), .G2_OCT(0), .NORM(1)
            ) u_core (
                .clk(clk), .rst(lane_rst),
                .rx_sym_valid(sym_valid), .rx_sym_ready(sym_ready), .rx_sym(noisy),
                .dec_bit_valid(dec_valid), .dec_bit(dec_bit),
                .force_state0(1'b0),
                .dbg_sweep(), .dbg_idx(), .dbg_pm(), .dbg_surv(),
                .dbg_commit(), .dbg_best()
            );

            // Reference FIFO of source bits (decoder output is in order)
            reg [127:0] ref_mem;
            reg [6:0]   wp, rp;
            wire ref_bit = ref_mem[rp];

            wire [31:0] lane_seed = seed ^ (32'h9E3779B9 * (g + 1));

            always @(posedge clk) begin
                if (lane_rst) begin
                    rx <= lane_seed; ry <= 32'd362436069;
                    rz <= 32'd521288629 ^ g; rw <= 32'd88675123;
                    rw_prev <= 32'd0;
                    prbs <= (lane_seed[30:0] == 31'd0) ? 31'd1 : lane_seed[30:0];
                    enc_state <= {M{1'b0}};
                    wp <= 7'd0; rp <= 7'd0;
                end else begin
                    rx <= ry; ry <= rz; rz <= rw;
                    rw <= rw ^ (rw >> 19) ^ (t ^ (t >> 8));
                    rw_prev <= rw;
                    if (accept) begin
                        prbs      <= {prbs[29:0], src_bit};
                        enc_state <= {enc_state[M-2:0], src_bit};
                        ref_mem[wp] <= src_bit;
                        wp <= wp + 7'd1;
                    end
                    if (dec_valid) rp <= rp + 7'd1;
                end
            end

            assign l_sym[g]         = accept;
            assign l_flips[2*g +: 2] = accept ? ({1'b0, flip0} + {1'b0, flip1}) : 2'd0;
            assign l_dec[g]         = dec_valid;
            assign l_err[g]         = dec_valid && (dec_bit != ref_bit);
        end
    endgenerate

    // Per-cycle sums across lanes
    reg [7:0] sum_dec, sum_err, sum_sym, sum_flips;
    integer i;
    always @(*) begin
        sum_dec = 0; sum_err = 0; sum_sym = 0; sum_flips = 0;
        for (i = 0; i < LANES; i = i + 1) begin
            sum_dec   = sum_dec   + l_dec[i];
            sum_err   = sum_err   + l_err[i];
            sum_sym   = sum_sym   + l_sym[i];
            sum_flips = sum_flips + l_flips[2*i +: 2];
        end
    end

    wire hit_bits = (maxbits != 64'd0) && (c_bits >= maxbits);
    wire hit_errs = (maxerrs != 32'd0) && (c_errs >= {32'd0, maxerrs});

    // ---------------------------------------------------------------- control
    always @(posedge clk) begin
        if (!rst_n) begin
            thresh <= 32'd0; maxerrs <= 32'd0; seed <= 32'h1234_5678;
            maxbits <= 64'd0;
            running <= 1'b0; finished <= 1'b0; lane_rst_cnt <= 3'd0;
            c_bits <= 0; c_errs <= 0; c_flips <= 0; c_chbits <= 0; c_cycles <= 0;
            s_bits <= 0; s_errs <= 0; s_flips <= 0; s_chbits <= 0; s_cycles <= 0;
        end else begin
            if (lane_rst_cnt != 3'd0) lane_rst_cnt <= lane_rst_cnt - 3'd1;

            if (wr_en) begin
                case (wr_addr)
                    5'd2: thresh        <= wr_data;
                    5'd3: maxbits[31:0] <= wr_data;
                    5'd4: maxbits[63:32]<= wr_data;
                    5'd5: maxerrs       <= wr_data;
                    5'd6: seed          <= wr_data;
                    default: ;
                endcase
            end

            if (start_cmd) begin
                running <= 1'b1; finished <= 1'b0; lane_rst_cnt <= 3'd7;
                c_bits <= 0; c_errs <= 0; c_flips <= 0; c_chbits <= 0; c_cycles <= 0;
            end else if (running) begin
                if (!lane_rst) begin
                    c_bits   <= c_bits   + sum_dec;
                    c_errs   <= c_errs   + sum_err;
                    c_flips  <= c_flips  + sum_flips;
                    c_chbits <= c_chbits + {sum_sym, 1'b0};
                    c_cycles <= c_cycles + 64'd1;
                end
                if (stop_cmd || hit_bits || hit_errs) begin
                    running  <= 1'b0;
                    finished <= 1'b1;
                end
            end

            if (snap_cmd || (running && (stop_cmd || hit_bits || hit_errs))) begin
                s_bits <= c_bits; s_errs <= c_errs; s_flips <= c_flips;
                s_chbits <= c_chbits; s_cycles <= c_cycles;
            end
        end
    end

    // ---------------------------------------------------------------- readback
    always @(*) begin
        case (rd_addr)
            5'd1:  rd_data = {12'd0, K4, L8, 6'd0, finished, running};
            5'd2:  rd_data = thresh;
            5'd3:  rd_data = maxbits[31:0];
            5'd4:  rd_data = maxbits[63:32];
            5'd5:  rd_data = maxerrs;
            5'd6:  rd_data = seed;
            5'd8:  rd_data = s_bits[31:0];
            5'd9:  rd_data = s_bits[63:32];
            5'd10: rd_data = s_errs[31:0];
            5'd11: rd_data = s_errs[63:32];
            5'd12: rd_data = s_flips[31:0];
            5'd13: rd_data = s_flips[63:32];
            5'd14: rd_data = s_chbits[31:0];
            5'd15: rd_data = s_chbits[63:32];
            5'd16: rd_data = s_cycles[31:0];
            5'd17: rd_data = s_cycles[63:32];
            default: rd_data = 32'd0;
        endcase
    end

endmodule

`default_nettype wire
