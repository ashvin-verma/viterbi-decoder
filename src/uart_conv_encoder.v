// uart_conv_encoder.v
// UART-interfaced convolutional encoder
// Receives bytes via UART, unpacks to symbols, encodes, packs bits back to bytes

`timescale 1ns/1ps

module uart_conv_encoder #(
    parameter K = 3,
    parameter G0_OCT = 8'o7,
    parameter G1_OCT = 8'o5
)(
    input wire clk,
    input wire rst,
    
    // Input UART interface (byte stream)
    input wire in_valid,
    output wire in_ready,
    input wire [7:0] in_byte,
    
    // Output UART interface (byte stream)
    output wire out_valid,
    input wire out_ready,
    output wire [7:0] out_byte
);

    localparam M = K - 1;

    // Intermediate signals
    wire unpacker_valid;
    wire unpacker_ready;
    wire [1:0] unpacker_sym;
    
    wire encoder_valid;
    wire encoder_ready;
    wire [1:0] encoder_sym;
    
    wire packer_bit;
    
    // Symbol unpacker: converts input bytes to 2-bit symbols
    // Each byte contains 4 symbols (8 bits / 2 bits per symbol)
    sym_unpacker_4x unpacker (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_byte(in_byte),
        .rx_sym_valid(unpacker_valid),
        .rx_sym_ready(unpacker_ready),
        .rx_sym(unpacker_sym)
    );
    
    // For encoder: we need to extract individual bits from symbols
    // Each symbol is 2 bits, we encode them separately
    reg bit_select;  // 0 = LSB, 1 = MSB
    reg [1:0] sym_buf;
    reg sym_waiting;
    
    wire encoder_in_bit;
    wire encoder_in_valid;
    
    // State machine to convert symbols to bits
    assign unpacker_ready = !sym_waiting;
    assign encoder_in_valid = sym_waiting && encoder_ready;
    assign encoder_in_bit = bit_select ? sym_buf[1] : sym_buf[0];
    
    always @(posedge clk) begin
        if (rst) begin
            sym_waiting <= 1'b0;
            bit_select <= 1'b0;
            sym_buf <= 2'b00;
        end else begin
            if (unpacker_valid && unpacker_ready) begin
                // New symbol received
                sym_buf <= unpacker_sym;
                sym_waiting <= 1'b1;
                bit_select <= 1'b0;
            end else if (sym_waiting && encoder_ready && encoder_in_valid) begin
                if (!bit_select) begin
                    // First bit sent, prepare second
                    bit_select <= 1'b1;
                end else begin
                    // Second bit sent, ready for next symbol
                    sym_waiting <= 1'b0;
                    bit_select <= 1'b0;
                end
            end
        end
    end
    
    // Convolutional encoder: rate 1/2
    // Input: 1 bit, Output: 2 bits (symbols)
    wire seed_load = 1'b0;
    wire [M-1:0] seed_value = {M{1'b0}};
    
    conv_encoder_1_2 #(
        .K(K),
        .G0_OCT(G0_OCT),
        .G1_OCT(G1_OCT)
    ) encoder (
        .clk(clk),
        .rst(rst),
        .seed_load(seed_load),
        .seed_value(seed_value),
        .in_valid(encoder_in_valid),
        .in_bit(encoder_in_bit),
        .out_valid(encoder_valid),
        .out_sym(encoder_sym)
    );
    
    // The encoder outputs 2-bit symbols, but the bit packer expects single bits
    // We need to serialize the encoder output
    reg enc_sym_waiting;
    reg [1:0] enc_sym_buf;
    reg enc_bit_select;
    reg packer_bit_valid;
    
    assign encoder_ready = !enc_sym_waiting;
    assign packer_bit = enc_bit_select ? enc_sym_buf[1] : enc_sym_buf[0];
    
    always @(posedge clk) begin
        if (rst) begin
            enc_sym_waiting <= 1'b0;
            enc_bit_select <= 1'b0;
            enc_sym_buf <= 2'b00;
            packer_bit_valid <= 1'b0;
        end else begin
            if (encoder_valid && encoder_ready) begin
                // New encoded symbol received
                enc_sym_buf <= encoder_sym;
                enc_sym_waiting <= 1'b1;
                enc_bit_select <= 1'b0;
                packer_bit_valid <= 1'b0;
            end else if (enc_sym_waiting) begin
                // Try to send bit to packer
                if (!out_valid) begin
                    // Packer can accept, pulse valid
                    packer_bit_valid <= 1'b1;
                    if (!enc_bit_select) begin
                        // Move to second bit next cycle
                        enc_bit_select <= 1'b1;
                    end else begin
                        // Both bits sent, ready for next symbol
                        enc_sym_waiting <= 1'b0;
                        enc_bit_select <= 1'b0;
                    end
                end else begin
                    // Packer busy, hold state
                    packer_bit_valid <= 1'b0;
                end
            end else begin
                packer_bit_valid <= 1'b0;
            end
        end
    end
    
    // Bit packer: converts encoded bits to bytes
    // Accumulates 8 bits before outputting a byte
    bit_packer_8x packer (
        .clk(clk),
        .rst(rst),
        .dec_bit_valid(packer_bit_valid),
        .dec_bit(packer_bit),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_byte(out_byte)
    );

endmodule
