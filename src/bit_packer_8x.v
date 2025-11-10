module bit_packer_8x (
    input wire clk,
    input wire rst,
    
    input wire dec_bit_valid,
    input wire dec_bit,
    
    output reg out_valid,
    input wire out_ready,
    output reg [7:0] out_byte
);

    // Internal registers
    reg [7:0] shift_reg;
    reg [2:0] bit_count;
    
    always @(posedge clk) begin
        if (rst) begin
            shift_reg <= 8'b0;
            bit_count <= 3'b0;
            out_valid <= 1'b0;
            out_byte <= 8'b0;
        end else begin
            // Default: clear valid if handshake completes
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
            end
            
            // Shift in new bits when valid
            if (dec_bit_valid && !out_valid) begin
                shift_reg <= {shift_reg[6:0], dec_bit};
                bit_count <= bit_count + 1'b1;
                
                // When 8 bits accumulated, output byte
                if (bit_count == 3'd7) begin
                    out_byte <= {shift_reg[6:0], dec_bit};
                    out_valid <= 1'b1;
                    bit_count <= 3'b0;
                end
            end
        end
    end

endmodule