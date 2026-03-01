//==============================================================================
// conv_encoder: Parameterized rate-1/2 convolutional encoder for loopback test
//==============================================================================
// Accepts one information bit per clock (valid/ready handshake) and outputs
// one RATE-bit coded symbol per input bit.  Supports tail termination by
// feeding M=K-1 zero bits after the message to flush the shift register.
//
// Generator polynomials use direct octal notation (same convention as the
// decoder): tap i maps to bit i of the K-bit register vector.
//
// Register convention: reg_vec = {state, in_bit}
//   - state[M-1] is the oldest bit (MSB)
//   - in_bit is the newest bit (LSB, position 0)
//
// Default polynomials match the K=5 code used by the decoder:
//   G0_OCT = 'o23  (0x13 = 0b10011)
//   G1_OCT = 'o35  (0x1D = 0b11101)
//==============================================================================

`default_nettype none

module conv_encoder #(
    parameter K      = 5,
    parameter G0_OCT = 'o23,
    parameter G1_OCT = 'o35
) (
    input  wire        clk,
    input  wire        rst,

    // Input: one info bit per clock
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_bit,

    // Output: one 2-bit coded symbol per accepted input bit
    output reg         out_valid,
    output reg  [1:0]  out_sym
);

    localparam M = K - 1;  // number of memory elements (shift-register width)

    // Generator masks (K bits wide)
    localparam [K-1:0] G0_MASK = G0_OCT;
    localparam [K-1:0] G1_MASK = G1_OCT;

    // Shift register holding the encoder state (M bits)
    reg [M-1:0] state;

    // The encoder is always ready to accept a new bit (purely combinational
    // output with one-cycle latency registered below).
    assign in_ready = 1'b1;

    // K-bit register vector: {state, in_bit}
    wire [K-1:0] reg_vec = {state, in_bit};

    always @(posedge clk) begin
        if (rst) begin
            state     <= {M{1'b0}};
            out_valid <= 1'b0;
            out_sym   <= 2'b00;
        end else begin
            if (in_valid) begin
                // Compute coded symbol via parity of masked register
                out_sym[1] <= ^(reg_vec & G0_MASK);  // G0 output
                out_sym[0] <= ^(reg_vec & G1_MASK);  // G1 output
                out_valid  <= 1'b1;

                // Shift new bit into state register (oldest bit discarded)
                state <= {state[M-2:0], in_bit};
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
