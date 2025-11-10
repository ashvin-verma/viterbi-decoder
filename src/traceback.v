module traceback #(
    parameter K = 7,          // Constraint length
    parameter M = K - 1,      // Number of bits in state
    parameter D = 40          // Traceback depth
)(
    input wire clk,
    input wire rst,
    
    // Write pointer from survivor memory (current time index in circular buffer)
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

    // State machine states
    localparam IDLE      = 2'b00;
    localparam INIT      = 2'b01;
    localparam TRACEBACK = 2'b10;
    localparam OUTPUT    = 2'b11;
    
    reg [1:0] state;
    reg [$clog2(D)-1:0] tb_count;
    reg [M-1:0] current_state;
    reg traceback_active;  // Flag to prevent overlapping tracebacks
    reg decoded_bit_reg;   // Store the decoded bit
    reg [$clog2(D)-1:0] wr_ptr_prev;  // Track wr_ptr changes
    reg [$clog2(D)-1:0] warmup_count; // Count symbols until D reached
    reg streaming_enabled;  // Enable streaming after warmup
    
    // Detect wr_ptr advancement (symbol write completed)
    wire wr_ptr_advanced = (wr_ptr != wr_ptr_prev);
    wire should_traceback = wr_ptr_advanced && streaming_enabled && !traceback_active;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tb_count <= 0;
            current_state <= 0;
            tb_time <= 0;
            tb_state <= 0;
            dec_bit_valid <= 0;
            dec_bit <= 0;
            traceback_active <= 0;
            decoded_bit_reg <= 0;
            wr_ptr_prev <= 0;
            warmup_count <= 0;
            streaming_enabled <= 0;
        end else begin
            // Track wr_ptr changes for warmup counting
            if (wr_ptr_advanced) begin
                wr_ptr_prev <= wr_ptr;
                if (!streaming_enabled) begin
                    warmup_count <= warmup_count + 1;
                    // Enable streaming after D symbols have been written
                    if (warmup_count >= D - 1) begin
                        streaming_enabled <= 1;
                    end
                end
            end
            
            case (state)
                IDLE: begin
                    dec_bit_valid <= 0;
                    // Streaming mode: trigger on every wr_ptr advance after warmup
                    if (should_traceback) begin
                        state <= INIT;
                        tb_count <= 0;
                        traceback_active <= 1;
                        // Start at end time and end state
                        // wr_ptr points to where NEXT write will go, so last written is wr_ptr-1
                        current_state <= force_state0 ? {M{1'b0}} : s_end;
                        tb_time <= (wr_ptr == 0) ? (D-1) : (wr_ptr - 1);
                        tb_state <= force_state0 ? {M{1'b0}} : s_end;
                    end
                end
                
                INIT: begin
                    // Wait one cycle for memory read to complete
                    // tb_time and tb_state are already set up
                    // On the NEXT cycle, tb_surv_bit will be valid with mem[tb_time][tb_state]
                    state <= TRACEBACK;
                    dec_bit_valid <= 0;
                    tb_count <= 0;
                end
                
                TRACEBACK: begin
                    // On FIRST cycle (tb_count==0), capture the bit - this is the decoded output
                    if (tb_count == 0) begin
                        decoded_bit_reg <= tb_surv_bit;
                    end
                    
                    // Update state based on the survivor bit we just read
                    if (tb_surv_bit) begin
                        current_state <= (current_state >> 1) | (1 << (M-1));
                        tb_state <= (current_state >> 1) | (1 << (M-1));
                    end else begin
                        current_state <= current_state >> 1;
                        tb_state <= current_state >> 1;
                    end
                    
                    // Move to previous time (but NOT on first cycle - we just read the current time!)
                    if (tb_count > 0) begin
                        tb_time <= (tb_time == 0) ? (D-1) : (tb_time - 1);
                    end
                    
                    tb_count <= tb_count + 1;
                    
                    // After D iterations, output the bit we saved
                    if (tb_count == D - 1) begin
                        state <= OUTPUT;
                    end
                end
                
                OUTPUT: begin
                    // Output the decoded bit from the FIRST traceback step
                    dec_bit <= decoded_bit_reg;
                    dec_bit_valid <= 1'b1;
                    traceback_active <= 0;  // Allow next traceback to start
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule