// Streaming Traceback Module - Produces 1 bit per symbol after warmup
// Continuously runs traceback in background

module traceback #(
    parameter K = 7,
    parameter M = K - 1,
    parameter D = 40
)(
    input wire clk,
    input wire rst,
    
    input wire [$clog2(D)-1:0] wr_ptr,
    input wire [M-1:0] s_end,
    input wire force_state0,
    
    output reg [$clog2(D)-1:0] tb_time,
    output reg [M-1:0] tb_state,
    input wire tb_surv_bit,
    
    output reg dec_bit_valid,
    output reg dec_bit
);

    // Streaming traceback: maintain a continuous pipeline
    // - Every time wr_ptr advances, we start a new D-step traceback
    // - Multiple tracebacks can overlap (pipelined)
    // - Output appears D cycles after trigger
    
    reg [$clog2(D)-1:0] wr_ptr_prev;
    reg [$clog2(D)-1:0] warmup_count;
    reg streaming_active;
    
    // Traceback state for current operation
    reg [$clog2(D)-1:0] tb_depth;  // How many steps into current traceback
    reg [M-1:0] trace_state;
    reg tb_running;
    
    // Pipeline: track the bit that will be output D cycles from now
    reg output_bit_pipeline [0:D-1];
    reg valid_pipeline [0:D-1];
    integer pipe_idx;
    
    wire wr_ptr_changed = (wr_ptr != wr_ptr_prev);
    wire should_start_trace = streaming_active && wr_ptr_changed;
    
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr_prev <= 0;
            warmup_count <= 0;
            streaming_active <= 0;
            tb_depth <= 0;
            trace_state <= 0;
            tb_running <= 0;
            tb_time <= 0;
            tb_state <= 0;
            dec_bit_valid <= 0;
            dec_bit <= 0;
            
            for (pipe_idx = 0; pipe_idx < D; pipe_idx = pipe_idx + 1) begin
                output_bit_pipeline[pipe_idx] <= 0;
                valid_pipeline[pipe_idx] <= 0;
            end
        end else begin
            // Warmup phase: wait for D symbols
            if (!streaming_active) begin
                if (wr_ptr_changed) begin
                    wr_ptr_prev <= wr_ptr;
                    warmup_count <= warmup_count + 1;
                    if (warmup_count >= D - 1) begin
                        streaming_active <= 1;
                    end
                end
            end else begin
                // Streaming mode
                if (wr_ptr_changed) begin
                    wr_ptr_prev <= wr_ptr;
                    // Start new traceback
                    tb_running <= 1;
                    tb_depth <= 0;
                    trace_state <= force_state0 ? {M{1'b0}} : s_end;
                    tb_time <= (wr_ptr == 0) ? (D-1) : (wr_ptr - 1);
                    tb_state <= force_state0 ? {M{1'b0}} : s_end;
                end else if (tb_running) begin
                    // Continue traceback
                    if (tb_depth == 0) begin
                        // First step: capture the output bit
                        output_bit_pipeline[0] <= trace_state[0];  // LSB is the info bit
                        valid_pipeline[0] <= 1;
                    end
                    
                    // Update state for next step
                    if (tb_surv_bit) begin
                        trace_state <= (trace_state >> 1) | (1 << (M-1));
                        tb_state <= (trace_state >> 1) | (1 << (M-1));
                    end else begin
                        trace_state <= trace_state >> 1;
                        tb_state <= trace_state >> 1;
                    end
                    
                    // Move backward in time
                    if (tb_depth > 0) begin
                        tb_time <= (tb_time == 0) ? (D-1) : (tb_time - 1);
                    end
                    
                    tb_depth <= tb_depth + 1;
                    
                    if (tb_depth >= D - 1) begin
                        tb_running <= 0;
                    end
                end
                
                // Shift pipeline every cycle
                dec_bit <= output_bit_pipeline[D-1];
                dec_bit_valid <= valid_pipeline[D-1];
                
                for (pipe_idx = D-1; pipe_idx > 0; pipe_idx = pipe_idx - 1) begin
                    output_bit_pipeline[pipe_idx] <= output_bit_pipeline[pipe_idx-1];
                    valid_pipeline[pipe_idx] <= valid_pipeline[pipe_idx-1];
                end
                output_bit_pipeline[0] <= 0;
                valid_pipeline[0] <= 0;
            end
        end
    end

endmodule
