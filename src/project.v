/*
 * Tiny Tapeout Viterbi Decoder
 * Parameterizable constraint length (K) and generator polynomials
 * Default: NASA standard K=7, G0=171, G1=133 (octal) - Rate 1/2
 * UART byte interface only
 */

`default_nettype none

module tt_um_ashvin_viterbi #(
    parameter K = 5,                    // Constraint length (K=5 for area efficiency)
    parameter [K-1:0] G0 = 5'b10011,    // Generator polynomial 0 (23 octal)
    parameter [K-1:0] G1 = 5'b11101,    // Generator polynomial 1 (35 octal)
    parameter MAX_FRAME = 32            // Maximum frame length
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

    // Derived parameters
    localparam M = K - 1;               // Memory length
    localparam NUM_STATES = 1 << M;     // Number of states (2^M)
    localparam PM_WIDTH = 8;            // Path metric width

    // Interface (UART byte mode only):
    // ui_in[0]   = byte_valid (input byte valid)
    // ui_in[3]   = start (begin decoding)
    // ui_in[4]   = read_ack (acknowledge output byte read)
    //
    // uo_out[0]  = byte_in_ready (ready to accept input byte)
    // uo_out[1]  = byte_out_valid (output byte ready)
    // uo_out[3]  = busy (decoding in progress)
    // uo_out[4]  = frame_done
    //
    // uio_in[7:0]  = input byte (4 symbols packed: sym0[1:0], sym1[3:2], etc.)
    // uio_out[7:0] = output byte (8 decoded bits packed)

    wire rst = ~rst_n;
    wire byte_valid = ui_in[0];
    wire start_cmd = ui_in[3];
    wire read_ack = ui_in[4];

    // State machine
    localparam [2:0] S_IDLE = 0, S_RECEIVE = 1, S_ACS = 2, S_FIND_BEST = 3, S_TRACE = 4, S_OUTPUT = 5;
    reg [2:0] state;

    // Symbol unpacker: 8-bit input -> 4 x 2-bit symbols
    reg [7:0] sym_byte_buf;
    reg [1:0] sym_idx;          // Which symbol in current byte (0-3)
    reg sym_byte_loaded;
    wire [1:0] current_input_sym = sym_byte_buf[sym_idx*2 +: 2];

    // Symbol buffer for frame
    reg [63:0] sym_buf;         // 32 symbols x 2 bits
    reg [5:0] sym_count;
    reg [5:0] frame_len;

    // Path metrics - dual bank for ping-pong
    // For K=7: 64 states x 8 bits = 512 bits per bank
    reg [PM_WIDTH-1:0] pm_bank0 [0:NUM_STATES-1];
    reg [PM_WIDTH-1:0] pm_bank1 [0:NUM_STATES-1];
    reg bank;

    // Survivor memory: stores decision bits for traceback
    // For each time step, store 1 bit per state (which predecessor)
    // 32 time steps x NUM_STATES bits
    reg [NUM_STATES-1:0] surv_mem [0:MAX_FRAME-1];

    // Output buffer
    reg [MAX_FRAME-1:0] out_buf;
    reg [5:0] out_idx;
    reg [5:0] out_len;
    reg frame_complete;

    // ACS processing
    reg [5:0] acs_t;            // Current time step
    reg [M-1:0] acs_state;      // Current state being processed (for sequential ACS)
    reg acs_done;
    reg [M-1:0] scan_state;     // State counter for finding best final state

    // Traceback
    reg [5:0] tb_t;
    reg [M-1:0] tb_state;

    // Bit packer: 8 decoded bits -> output byte
    reg [7:0] out_byte_buf;
    reg [2:0] out_bit_idx;
    reg out_byte_ready;

    // Expected symbol calculation for given state and input bit
    function [1:0] calc_expected_sym;
        input [M-1:0] st;
        input in_bit;
        reg [K-1:0] shift_reg;
        begin
            shift_reg = {st, in_bit};
            calc_expected_sym[1] = ^(shift_reg & G0);
            calc_expected_sym[0] = ^(shift_reg & G1);
        end
    endfunction

    // Hamming distance (2-bit symbols)
    function [1:0] hamming_dist;
        input [1:0] a, b;
        begin
            hamming_dist = (a[0] ^ b[0]) + (a[1] ^ b[1]);
        end
    endfunction

    // Get predecessor state given current state and decision bit
    // For state s, predecessors are: (s >> 1) and (s >> 1) | (1 << (M-1))
    // Decision bit 0 means predecessor = s >> 1
    // Decision bit 1 means predecessor = (s >> 1) | (1 << (M-1))
    function [M-1:0] get_predecessor;
        input [M-1:0] st;
        input decision;
        begin
            get_predecessor = {decision, st[M-1:1]};
        end
    endfunction

    // Current symbol from buffer for ACS
    wire [1:0] acs_sym = sym_buf[acs_t*2 +: 2];

    // ACS computation for current state
    wire [M-1:0] pred0 = {1'b0, acs_state[M-1:1]};  // Predecessor with input 0
    wire [M-1:0] pred1 = {1'b1, acs_state[M-1:1]};  // Predecessor with input 1
    wire input_bit = acs_state[0];  // Input bit that leads to this state

    wire [1:0] exp_sym0 = calc_expected_sym(pred0, input_bit);
    wire [1:0] exp_sym1 = calc_expected_sym(pred1, input_bit);
    wire [1:0] bm0 = hamming_dist(acs_sym, exp_sym0);
    wire [1:0] bm1 = hamming_dist(acs_sym, exp_sym1);

    wire [PM_WIDTH-1:0] pm_pred0 = bank ? pm_bank1[pred0] : pm_bank0[pred0];
    wire [PM_WIDTH-1:0] pm_pred1 = bank ? pm_bank1[pred1] : pm_bank0[pred1];
    wire [PM_WIDTH-1:0] metric0 = pm_pred0 + bm0;
    wire [PM_WIDTH-1:0] metric1 = pm_pred1 + bm1;
    wire select = (metric1 < metric0);  // 1 if pred1 is better
    wire [PM_WIDTH-1:0] new_pm = select ? metric1 : metric0;

    // Find best final state for traceback
    reg [M-1:0] best_state;
    reg [PM_WIDTH-1:0] best_pm;

    // Status signals
    wire byte_in_ready = (state == S_IDLE || state == S_RECEIVE) && !sym_byte_loaded;
    wire busy = (state == S_ACS) || (state == S_FIND_BEST) || (state == S_TRACE);

    assign uo_out[0] = byte_in_ready;
    assign uo_out[1] = out_byte_ready;
    assign uo_out[2] = 1'b0;  // Reserved
    assign uo_out[3] = busy;
    assign uo_out[4] = frame_complete;
    assign uo_out[7:5] = 3'b0;

    assign uio_out = out_byte_buf;
    assign uio_oe = 8'hFF;  // Always output in UART mode

    wire _unused = &{ena, ui_in[7:5], ui_in[2:1], 1'b0};

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            sym_count <= 0;
            frame_len <= 0;
            bank <= 0;
            acs_t <= 0;
            acs_state <= 0;
            acs_done <= 0;
            scan_state <= 0;
            tb_t <= 0;
            tb_state <= 0;
            out_idx <= 0;
            out_len <= 0;
            out_bit_idx <= 0;
            frame_complete <= 0;
            sym_buf <= 0;
            out_buf <= 0;
            sym_byte_loaded <= 0;
            sym_idx <= 0;
            out_byte_ready <= 0;
            out_byte_buf <= 0;
            best_state <= 0;
            best_pm <= {PM_WIDTH{1'b1}};

            // Initialize path metrics
            for (i = 0; i < NUM_STATES; i = i + 1) begin
                pm_bank0[i] <= (i == 0) ? 0 : {PM_WIDTH{1'b1}} >> 1;
                pm_bank1[i] <= {PM_WIDTH{1'b1}} >> 1;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    sym_count <= 0;
                    out_idx <= 0;
                    out_bit_idx <= 0;
                    frame_complete <= 0;
                    out_byte_ready <= 0;
                    bank <= 0;
                    best_pm <= {PM_WIDTH{1'b1}};

                    // Initialize path metrics
                    for (i = 0; i < NUM_STATES; i = i + 1) begin
                        pm_bank0[i] <= (i == 0) ? 0 : {PM_WIDTH{1'b1}} >> 1;
                    end

                    // Load input byte
                    if (byte_valid && !sym_byte_loaded) begin
                        sym_byte_buf <= uio_in;
                        sym_byte_loaded <= 1;
                        sym_idx <= 0;
                        state <= S_RECEIVE;
                    end
                end

                S_RECEIVE: begin
                    // Process symbols from loaded byte
                    if (sym_byte_loaded && sym_count < MAX_FRAME) begin
                        sym_buf[sym_count*2 +: 2] <= current_input_sym;
                        sym_count <= sym_count + 1;

                        if (sym_idx == 3) begin
                            // Finished this byte, wait for next
                            sym_byte_loaded <= 0;
                        end else begin
                            sym_idx <= sym_idx + 1;
                        end
                    end

                    // Load next byte
                    if (byte_valid && !sym_byte_loaded) begin
                        sym_byte_buf <= uio_in;
                        sym_byte_loaded <= 1;
                        sym_idx <= 0;
                    end

                    // Start decoding
                    if (start_cmd && sym_count > 0) begin
                        frame_len <= sym_count;
                        acs_t <= 0;
                        acs_state <= 0;
                        acs_done <= 0;
                        state <= S_ACS;
                    end
                end

                S_ACS: begin
                    if (!acs_done) begin
                        // Update survivor memory and path metric for current state
                        surv_mem[acs_t][acs_state] <= select;

                        if (bank == 0)
                            pm_bank1[acs_state] <= new_pm;
                        else
                            pm_bank0[acs_state] <= new_pm;

                        // Move to next state
                        if (acs_state == NUM_STATES - 1) begin
                            // Done with all states for this time step
                            acs_state <= 0;
                            bank <= ~bank;

                            if (acs_t == frame_len - 1) begin
                                acs_done <= 1;
                            end else begin
                                acs_t <= acs_t + 1;
                            end
                        end else begin
                            acs_state <= acs_state + 1;
                        end
                    end else begin
                        // Start scan to find best final state
                        scan_state <= 0;
                        best_state <= 0;
                        best_pm <= {PM_WIDTH{1'b1}};
                        state <= S_FIND_BEST;
                    end
                end

                S_FIND_BEST: begin
                    // Scan all states to find minimum path metric
                    if ((bank ? pm_bank1[scan_state] : pm_bank0[scan_state]) < best_pm) begin
                        best_pm <= bank ? pm_bank1[scan_state] : pm_bank0[scan_state];
                        best_state <= scan_state;
                    end

                    if (scan_state == NUM_STATES - 1) begin
                        // Done scanning, start traceback from best state
                        // Use scan_state if it's better than current best, else use best_state
                        if ((bank ? pm_bank1[scan_state] : pm_bank0[scan_state]) < best_pm) begin
                            tb_state <= scan_state;
                        end else begin
                            tb_state <= best_state;
                        end
                        tb_t <= frame_len - 1;
                        state <= S_TRACE;
                    end else begin
                        scan_state <= scan_state + 1;
                    end
                end

                S_TRACE: begin
                    // Decoded bit is the input that led to current state
                    // which is the LSB of current state
                    out_buf[tb_t] <= tb_state[0];

                    // Get predecessor state using survivor decision
                    tb_state <= get_predecessor(tb_state, surv_mem[tb_t][tb_state]);

                    if (tb_t == 0) begin
                        out_len <= frame_len;
                        state <= S_OUTPUT;
                    end else begin
                        tb_t <= tb_t - 1;
                    end
                end

                S_OUTPUT: begin
                    // Pack bits into output bytes
                    if (!out_byte_ready && out_idx < out_len) begin
                        out_byte_buf[out_bit_idx] <= out_buf[out_idx];
                        out_idx <= out_idx + 1;

                        if (out_bit_idx == 7) begin
                            out_byte_ready <= 1;
                            out_bit_idx <= 0;
                        end else begin
                            out_bit_idx <= out_bit_idx + 1;
                        end
                    end

                    // Handle last partial byte
                    if (out_idx >= out_len && !out_byte_ready && out_bit_idx != 0) begin
                        // Pad remaining bits with 0
                        out_byte_ready <= 1;
                        out_bit_idx <= 0;
                    end

                    // Output byte acknowledged
                    if (read_ack && out_byte_ready) begin
                        out_byte_ready <= 0;
                    end

                    // Check for completion
                    if (out_idx >= out_len && !out_byte_ready) begin
                        frame_complete <= 1;
                    end

                    // Return to idle on start
                    if (frame_complete && start_cmd) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
