/*
 * Tiny Tapeout Viterbi Decoder Wrapper
 * Wraps viterbi_universal with serial I/O interface
 * K=3, G0=7 (111), G1=5 (101) - Rate 1/2 convolutional code
 */

`default_nettype none

module tt_um_ashvin_viterbi #(
    parameter K = 3,
    parameter [K-1:0] G0 = 3'b111,
    parameter [K-1:0] G1 = 3'b101,
    parameter MAX_FRAME = 64
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

    // Interface:
    // ui_in[0]   = rx_valid (symbol input valid)
    // ui_in[2:1] = rx_sym (2-bit received symbol)
    // ui_in[3]   = start (begin decoding buffered frame)
    // ui_in[4]   = read_ack (acknowledge output bit read)
    //
    // uo_out[0]  = rx_ready (ready for symbol input)
    // uo_out[1]  = out_valid (decoded bit available)
    // uo_out[2]  = out_bit (decoded bit value)
    // uo_out[3]  = busy (decoder processing)
    // uo_out[4]  = frame_done (all bits output)

    wire rst = ~rst_n;

    // Input signals
    wire rx_valid = ui_in[0];
    wire [1:0] rx_sym = ui_in[2:1];
    wire start_decode = ui_in[3];
    wire read_ack = ui_in[4];

    // State machine for I/O
    localparam S_IDLE = 0, S_RECEIVE = 1, S_DECODE = 2, S_OUTPUT = 3;
    reg [1:0] io_state;

    // Symbol input buffer
    reg [1:0] syms_buf [0:MAX_FRAME-1];
    reg [6:0] sym_count;

    // Decoder interface signals
    reg dec_start;
    wire dec_done;
    wire [7:0] dec_out_len;
    wire dec_bits_out [0:255];

    // Create unpacked array for decoder input
    wire [1:0] syms_in [0:255];
    genvar gi;
    generate
        for (gi = 0; gi < MAX_FRAME; gi = gi + 1) begin : gen_syms
            assign syms_in[gi] = syms_buf[gi];
        end
        for (gi = MAX_FRAME; gi < 256; gi = gi + 1) begin : gen_syms_zero
            assign syms_in[gi] = 2'b00;
        end
    endgenerate

    // Instantiate the working decoder
    viterbi_universal #(
        .K(K),
        .G0(G0),
        .G1(G1)
    ) decoder (
        .clk(clk),
        .rst(rst),
        .start(dec_start),
        .frame_len({1'b0, sym_count}),
        .syms_in(syms_in),
        .done(dec_done),
        .out_len(dec_out_len),
        .bits_out(dec_bits_out)
    );

    // Output state
    reg [6:0] out_idx;
    reg [6:0] out_len;
    reg frame_complete;

    // Status signals
    wire rx_ready = (io_state == S_IDLE) || (io_state == S_RECEIVE);
    wire out_valid = (io_state == S_OUTPUT) && (out_idx < out_len);
    wire out_bit = out_valid ? dec_bits_out[out_idx] : 1'b0;
    wire busy = (io_state == S_DECODE);

    assign uo_out[0] = rx_ready;
    assign uo_out[1] = out_valid;
    assign uo_out[2] = out_bit;
    assign uo_out[3] = busy;
    assign uo_out[4] = frame_complete;
    assign uo_out[7:5] = 3'b0;

    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;

    wire _unused = &{ena, uio_in, 1'b0};

    always @(posedge clk) begin
        if (rst) begin
            io_state <= S_IDLE;
            sym_count <= 0;
            dec_start <= 0;
            out_idx <= 0;
            out_len <= 0;
            frame_complete <= 0;
        end else begin
            dec_start <= 0;  // Default: pulse only

            case (io_state)
                S_IDLE: begin
                    sym_count <= 0;
                    out_idx <= 0;
                    frame_complete <= 0;
                    if (rx_valid) begin
                        syms_buf[0] <= rx_sym;
                        sym_count <= 1;
                        io_state <= S_RECEIVE;
                    end
                end

                S_RECEIVE: begin
                    if (rx_valid && sym_count < MAX_FRAME) begin
                        syms_buf[sym_count] <= rx_sym;
                        sym_count <= sym_count + 1;
                    end
                    if (start_decode && sym_count > 0) begin
                        dec_start <= 1;
                        io_state <= S_DECODE;
                    end
                end

                S_DECODE: begin
                    if (dec_done) begin
                        out_len <= dec_out_len[6:0];
                        out_idx <= 0;
                        io_state <= S_OUTPUT;
                    end
                end

                S_OUTPUT: begin
                    if (read_ack && out_idx < out_len) begin
                        out_idx <= out_idx + 1;
                    end
                    if (out_idx >= out_len) begin
                        frame_complete <= 1;
                    end
                    // Return to idle when user acknowledges completion
                    if (frame_complete && start_decode) begin
                        io_state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
