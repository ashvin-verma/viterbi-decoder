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

    // Simplified streaming design:
    // After warmup (D symbols), continuously run traceback
    // Each traceback takes D cycles, produces 1 bit
    // Need to track: when did we last START a traceback?
    
    reg [$clog2(D)-1:0] wr_ptr_prev;
    reg [$clog2(D)-1:0] warmup_count;
    reg streaming_mode;
    
    reg [$clog2(D)-1:0] tb_step;  // Which step (0 to D-1) in current traceback
    reg [M-1:0] current_state;
    reg tb_active;
    reg pending_start;  // New traceback needs to start
    
    wire wr_ptr_advanced = (wr_ptr != wr_ptr_prev) && !rst;
    
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr_prev <= 0;
            warmup_count <= 0;
            streaming_mode <= 0;
            tb_step <= 0;
            current_state <= 0;
            tb_active <= 0;
            pending_start <= 0;
            tb_time <= 0;
            tb_state <= 0;
            dec_bit_valid <= 0;
            dec_bit <= 0;
        end else begin
            dec_bit_valid <= 0;  // Default
            
            // Detect wr_ptr changes
            if (wr_ptr_advanced) begin
                wr_ptr_prev <= wr_ptr;
                
                // Warmup counting
                if (!streaming_mode) begin
                    warmup_count <= warmup_count + 1;
                    if (warmup_count >= D - 1) begin
                        streaming_mode <= 1;
                        pending_start <= 1;  // Start first traceback
                    end
                end else begin
                    // In streaming mode, request new traceback
                    pending_start <= 1;
                end
            end
            
            // Traceback state machine
            if (!tb_active && pending_start && streaming_mode) begin
                // Start new traceback
                tb_active <= 1;
                pending_start <= 0;
                tb_step <= 0;
                current_state <= force_state0 ? {M{1'b0}} : s_end;
                tb_time <= (wr_ptr_prev == 0) ? (D-1) : (wr_ptr_prev - 1);
                tb_state <= force_state0 ? {M{1'b0}} : s_end;
            end else if (tb_active) begin
                // Continue traceback
                if (tb_step == 0) begin
                    // First cycle: just read the bit (tb_surv_bit valid next cycle)
                    // Don't move yet
                    tb_step <= tb_step + 1;
                end else if (tb_step < D) begin
                    // Use the survivor bit from PREVIOUS cycle
                    if (tb_surv_bit) begin
                        current_state <= (current_state >> 1) | (1 << (M-1));
                    end else begin
                        current_state <= current_state >> 1;
                    end
                    
                    // Set up next read
                    if (tb_surv_bit) begin
                        tb_state <= (current_state >> 1) | (1 << (M-1));
                    end else begin
                        tb_state <= current_state >> 1;
                    end
                    tb_time <= (tb_time == 0) ? (D-1) : (tb_time - 1);
                    
                    tb_step <= tb_step + 1;
                    
                    // Last step: output the bit
                    if (tb_step == D - 1) begin
                        dec_bit <= current_state[0];  // LSB is info bit
                        dec_bit_valid <= 1;
                        tb_active <= 0;
                    end
                end
            end
        end
    end

endmodule
                end
            end
        end
    end

endmodule