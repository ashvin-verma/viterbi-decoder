// conv_encoder_1_2.v
// Parameterizable rate-1/2 convolutional encoder (1 input bit → 2 coded bits per clk)
// Verilog-2001 compatible version
// Conventions:
//   - Constraint length K (memory M = K-1; states S = 2^M).
//   - Generator polynomials given in OCTAL (classic), LSB = D^0 (newest bit).
//   - Register vector used for parity = {in_bit, state[M-1:0]} so bit0 taps the CURRENT input.
//   - Outputs packed as out_sym = {c0, c1}, where c0 uses G0, c1 uses G1.
// Notes:
//   - Tail-termination: drive K-1 zeros after the frame.
//   - Tail-biting: assert seed_load with seed = last M info bits before starting.
//   - out_valid is 1-cycle aligned to in_valid; one symbol per in_valid=1 cycle.

module conv_encoder_1_2 #(
  parameter K  = 4,                      // constraint length (>=2)
  parameter M  = (K-1),
  parameter G0_OCT = 8'o17,              // e.g., K=4: (17,13)_8 is classic
  parameter G1_OCT = 8'o13
)(
  input  wire        clk,
  input  wire        rst,                // synchronous reset

  // Configuration for (re)seeding the shift register (for tail-biting or frame start)
  input  wire        seed_load,          // when 1, load seed_value on this clk
  input  wire [M-1:0] seed_value,        // new state contents (older→MSB)

  // Streaming input: one info bit per cycle when in_valid=1
  input  wire        in_valid,
  input  wire        in_bit,             // information bit at this cycle

  // Streaming output: one coded symbol per in_valid=1 cycle
  output reg         out_valid,
  output reg  [1:0]  out_sym             // {c0, c1} with c0 from G0, c1 from G1
);

  // ------------------------------
  // Octal → K-bit tap masks
  // LSB (bit 0) corresponds to D^0 = CURRENT input bit.
  // Convert at elaboration time using parameters
  // ------------------------------
  function [K-1:0] oct2mask;
    input [31:0] oct;  // Accept 32-bit value
    integer pos, v, digit;
    reg [K-1:0] mask;
    begin
      mask = {K{1'b0}};
      pos = 0;
      v = oct;
      while (v != 0) begin
        digit = v & 7;  // 3'b111
        if (((digit & 1) != 0) && (pos+0 < K)) mask[pos+0] = 1'b1;
        if (((digit & 2) != 0) && (pos+1 < K)) mask[pos+1] = 1'b1;
        if (((digit & 4) != 0) && (pos+2 < K)) mask[pos+2] = 1'b1;
        v = v >> 3;
        pos = pos + 3;
      end
      oct2mask = mask;
    end
  endfunction

  // Pre-compute generator masks
  wire [K-1:0] G0_MASK;
  wire [K-1:0] G1_MASK;
  assign G0_MASK = oct2mask({24'b0, G0_OCT});
  assign G1_MASK = oct2mask({24'b0, G1_OCT});

  // ------------------------------
  // State register (memory) and parity compute
  // state[M-1] = oldest; state[0] = newest *previous* bit
  // GOLDEN MODEL CONVENTION: reg_vec = {state, in_bit}
  // Register bits: [K-1:1]=state, [0]=in_bit (LSB)
  // ------------------------------
  reg [M-1:0] state;

  // Combinational parity for current input + current state image
  wire [K-1:0] reg_vec;
  wire c0, c1;

  assign reg_vec = {state, in_bit};           // width K - GOLDEN MODEL ORDER
  assign c0 = ^(reg_vec & G0_MASK);           // reduction XOR → parity
  assign c1 = ^(reg_vec & G1_MASK);

  // ------------------------------
  // Sequential update & output staging
  // out_valid mirrors in_valid (1-cycle timing alignment with outputs)
  // Shift direction: next_state = (state << 1) | in_bit - LSB INSERTION
  // ------------------------------
  always @(posedge clk) begin
    if (rst) begin
      state     <= {M{1'b0}};
      out_valid <= 1'b0;
      out_sym   <= 2'b00;
    end else begin
      // Optional reseed (tail-biting / frame init)
      if (seed_load) begin
        state <= seed_value;
      end else if (in_valid) begin
        // Update state: LSB insertion to match golden model
        // next = (state << 1) | in_bit
        state <= {state[M-2:0], in_bit};
      end

      // Emit symbol when input is valid
      out_valid <= in_valid;
      if (in_valid) begin
        out_sym <= {c0, c1};               // pack as {c0,c1}
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Examples:
//   // K=3, (7,5)_8  → classic K=3, r=1/2
//   conv_encoder_1_2 #(.K(3), .G0_OCT(8'o7),  .G1_OCT(8'o5)) enc_K3 (.*);
//
//   // K=4, (17,13)_8 → classic K=4, r=1/2
//   conv_encoder_1_2 #(.K(4), .G0_OCT(8'o17), .G1_OCT(8'o13)) enc_K4 (.*);
// -----------------------------------------------------------------------------
