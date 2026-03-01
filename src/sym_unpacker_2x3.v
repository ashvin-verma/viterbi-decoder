module sym_unpacker_2x3 (
    input  wire        clk,
    input  wire        rst,

    input  wire        in_valid,
    output reg         in_ready,
    input  wire [7:0]  in_byte,

    output reg         rx_sym_valid,
    input  wire        rx_sym_ready,
    output reg  [2:0]  rx_sym
);
    // Unpack 2 symbols (3 bits each) from each input byte
    // Symbol 0 = bits [2:0], Symbol 1 = bits [5:3]
    // Bits [7:6] are unused

    reg [7:0] byte_buf;
    reg       sym_count;  // 0-1: which symbol we're outputting
    reg       has_data;

    always @(posedge clk) begin
        if (rst) begin
            in_ready <= 1'b1;
            rx_sym_valid <= 1'b0;
            rx_sym <= 3'b000;
            byte_buf <= 8'b0;
            sym_count <= 1'b0;
            has_data <= 1'b0;
        end else begin
            // Accept new byte when ready and no pending symbols
            if (in_valid && in_ready) begin
                byte_buf <= in_byte;
                sym_count <= 1'b0;
                has_data <= 1'b1;
                in_ready <= 1'b0;
                rx_sym_valid <= 1'b1;
                rx_sym <= in_byte[2:0];  // Output first symbol immediately
            end
            // Output remaining symbols
            else if (rx_sym_valid && rx_sym_ready && has_data) begin
                if (sym_count == 1'b1) begin
                    // Last symbol consumed, ready for next byte
                    rx_sym_valid <= 1'b0;
                    has_data <= 1'b0;
                    in_ready <= 1'b1;
                end else begin
                    // Output next symbol
                    sym_count <= 1'b1;
                    rx_sym <= byte_buf[5:3];
                end
            end
        end
    end
endmodule
