//==============================================================================
// expected_bits: Computes expected convolutional code symbols
//==============================================================================
// Given predecessor state and input bit, computes the 2-bit symbol that
// the convolutional encoder would output.
//
// Convention: bit 0 = newest input, bits [M:1] = state (oldest at MSB)
// Generator polynomials use direct octal notation where tap i maps to bit i
//   Example: G0_OCT='o23 means taps at bits 0,1,4 (octal 23 = binary 10011)
//
// For standard rate-1/2 K=5 code:
//   G0_OCT = 'o23 (0x13 = 0b10011)
//   G1_OCT = 'o35 (0x1D = 0b11101)
//==============================================================================

module expected_bits #(
    parameter K = 5,
    parameter M = K - 1,
    parameter G0_OCT = 'o23,
    parameter G1_OCT = 'o35
) (
    input [M-1:0] pred, // previous state, m bits
    input b,
    output reg [1:0] expected
);

  // Convention: bit 0 = newest input, higher bits = older state
  // Generator polynomials can be used directly in octal notation
  localparam [K-1:0] G0_MASK = G0_OCT;
  localparam [K-1:0] G1_MASK = G1_OCT;
  reg [K-1:0] reg_vec;

  always @ (*) begin
    // GOLDEN MODEL CONVENTION: Register = {predecessor, input_bit}
    // Register bits: [K-1:1]=pred, [0]=b (LSB)
    // This matches C model: reg = (b & 1u) | (p << 1)
    reg_vec = {pred, b};
    // C model: c0 = parity(reg & g0), c1 = parity(reg & g1)
    // Returns: (c0 << 1) | c1, so expected[1]=c0, expected[0]=c1
    expected[1] = ^(reg_vec & G0_MASK);  // c0 = parity(reg & G0)
    expected[0] = ^(reg_vec & G1_MASK);  // c1 = parity(reg & G1)
  end

endmodule