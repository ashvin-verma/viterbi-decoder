module sym_unpacker_4x (
    input  wire        clk,
    input  wire        rst,

    input  wire        in_valid,
    output reg         in_ready,
    input  wire [7:0]  in_byte,

    output reg         rx_sym_valid,
    input  wire        rx_sym_ready,
    output reg  [1:0]  rx_sym
);
    // Unpack 4 symbols (2 bits each) from each input byte
    // Symbol 0 = bits [1:0], Symbol 1 = bits [3:2], 
    // Symbol 2 = bits [5:4], Symbol 3 = bits [7:6]
    
    reg [7:0] byte_buf;
    reg [1:0] sym_count;  // 0-3: which symbol we're outputting
    reg       has_data;

    always @(posedge clk) begin
        if (rst) begin
            in_ready <= 1'b1;
            rx_sym_valid <= 1'b0;
            rx_sym <= 2'b00;
            byte_buf <= 8'b0;
            sym_count <= 2'b00;
            has_data <= 1'b0;
        end else begin
            // Accept new byte when ready and no pending symbols
            if (in_valid && in_ready) begin
                byte_buf <= in_byte;
                sym_count <= 2'b00;
                has_data <= 1'b1;
                in_ready <= 1'b0;
                rx_sym_valid <= 1'b1;
                rx_sym <= in_byte[1:0];  // Output first symbol immediately
            end
            // Output remaining symbols
            else if (rx_sym_valid && rx_sym_ready && has_data) begin
                if (sym_count == 2'b11) begin
                    // Last symbol consumed, ready for next byte
                    rx_sym_valid <= 1'b0;
                    has_data <= 1'b0;
                    in_ready <= 1'b1;
                end else begin
                    // Output next symbol
                    sym_count <= sym_count + 1'b1;
                    case (sym_count + 1'b1)
                        2'b01: rx_sym <= byte_buf[3:2];
                        2'b10: rx_sym <= byte_buf[5:4];
                        2'b11: rx_sym <= byte_buf[7:6];
                        default: rx_sym <= 2'b00;
                    endcase
                end
            end
        end
    end
endmodule