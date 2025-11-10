module traceback #(
    parameter M = 6,          // Number of bits in state
    parameter D = 40          // Traceback depth
)(
    input wire clk,
    input wire rst,
    
    // Write pointer from survivor memory
    input wire [$clog2(D)-1:0] wr_ptr,
    
    // End state inputs
    input wire [M-1:0] s_end,
    input wire force_state0,
    
    // Survivor read interface
    output reg [$clog2(D)-1:0] tb_time,
    output reg [M-1:0] tb_state,
    input wire tb_surv_bit,
    
    // Decoded output stream
    output reg dec_bit_valid,
    output reg dec_bit
);
// Traceback counter and state tracking
always @(posedge clk) begin
    if (rst) begin
        tb_count <= 0;
        current_state <= 0;
        tb_time <= 0;
        tb_state <= 0;
        dec_bit_valid <= 0;
        dec_bit <= 0;
    end else begin
        case (state)
            IDLE: begin
                tb_count <= 0;
                dec_bit_valid <= 0;
                if (force_state0) begin
                    // Initialize traceback from end state
                    current_state <= s_end;
                    tb_time <= wr_ptr;
                    tb_state <= s_end;
                end
            end
            
            TRACEBACK: begin
                // Read survivor bit at current (time, state)
                tb_time <= (tb_time == 0) ? (D-1) : (tb_time - 1);
                tb_state <= current_state;
                
                // Update state based on survivor bit from previous cycle
                if (tb_count > 0) begin
                    // Shift current_state right by 1 and insert survivor bit at MSB
                    current_state <= {tb_surv_bit, current_state[M-1:1]};
                end
                
                tb_count <= tb_count + 1;
            end
            
            DECODE: begin
                // Output the decoded bit (survivor bit from last traceback step)
                dec_bit <= tb_surv_bit;
                dec_bit_valid <= 1'b1;
            end
        endcase
    end
end
    // Internal state machine
    localparam IDLE      = 2'b00;
    localparam TRACEBACK = 2'b01;
    localparam DECODE    = 2'b10;
    
    reg [1:0] state, next_state;
    
    // Traceback counter
    reg [$clog2(D)-1:0] tb_count;
    
    // Current state being traced
    reg [M-1:0] current_state;
    
    // State machine
    // Traceback counter and state tracking
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tb_count <= 0;
            current_state <= 0;
            tb_time <= 0;
            tb_state <= 0;
            dec_bit_valid <= 0;
            dec_bit <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tb_count <= 0;
                    dec_bit_valid <= 0;
                    if (force_state0) begin
                        state <= TRACEBACK;
                        // Initialize traceback from end state
                        current_state <= s_end;
                        tb_time <= wr_ptr;
                        tb_state <= s_end;
                    end
                end
                
                TRACEBACK: begin
                    // Read survivor bit at current (time, state)
                    tb_time <= (tb_time == 0) ? (D-1) : (tb_time - 1);
                    tb_state <= current_state;
                    
                    // Update state based on survivor bit from previous cycle
                    if (tb_count > 0) begin
                        // Shift current_state right by 1 and insert survivor bit at MSB
                        current_state <= {tb_surv_bit, current_state[M-1:1]};
                    end
                    
                    tb_count <= tb_count + 1;
                    
                    if (tb_count == D-1) begin
                        state <= DECODE;
                    end
                end
                
                DECODE: begin
                    // Output the decoded bit (survivor bit from last traceback step)
                    dec_bit <= tb_surv_bit;
                    dec_bit_valid <= 1'b1;
                    
                    if (dec_bit_valid) begin
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
        
    // Next state logic
    always @(*) begin
        case (state)
            IDLE: begin
                if (force_state0) begin
                    next_state = TRACEBACK;
                end
            end
            TRACEBACK: begin
                if (tb_count == D-1) begin
                    next_state = DECODE;
                end
            end
            DECODE: begin
                if (dec_bit_valid) begin
                    next_state = IDLE;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule