//==============================================================================
// expected_bits: Computes expected convolutional code symbols
//==============================================================================
// Given predecessor state and input bit, computes the RATE-bit symbol that
// the convolutional encoder would output.
//
// Convention: bit 0 = newest input, bits [M:1] = state (oldest at MSB)
// Generator polynomials use direct octal notation where tap i maps to bit i
//   Example: G0_OCT='o23 means taps at bits 0,1,4 (octal 23 = binary 10011)
//
// For standard rate-1/2 K=5 code:
//   G0_OCT = 'o23 (0x13 = 0b10011)
//   G1_OCT = 'o35 (0x1D = 0b11101)
//
// For rate-1/3, also supply G2_OCT for the third generator polynomial.
//==============================================================================

module expected_bits #(
    parameter K = 5,
    parameter M = K - 1,
    parameter RATE = 2,
    parameter G0_OCT = 'o23,
    parameter G1_OCT = 'o35,
    parameter G2_OCT = 'o0
) (
    input [M-1:0] pred, // previous state, m bits
    input b,
    output reg [RATE-1:0] expected
);

  // Convention (matches C golden): bit 0 = newest input, higher bits = older state
  // Generator polynomials use direct octal notation where tap i maps to bit i
  localparam [K-1:0] G0_MASK = G0_OCT;
  localparam [K-1:0] G1_MASK = G1_OCT;
  localparam [K-1:0] G2_MASK = G2_OCT;
  reg [K-1:0] reg_vec;

  always @ (*) begin
    // Register: reg[0]=b (newest input at LSB), reg[K-1:1]=pred (state bits)
    // This matches the C golden: reg = (b & 1) | (pred << 1)
    reg_vec = {pred, b};
    // c0 = parity(reg & G0), c1 = parity(reg & G1)
    expected[1] = ^(reg_vec & G0_MASK);  // c0 = parity(reg & G0)
    expected[0] = ^(reg_vec & G1_MASK);  // c1 = parity(reg & G1)
  end

  // Third generator output for RATE==3
  generate
    if (RATE == 3) begin : gen_g2
      always @ (*) begin
        expected[2] = ^(reg_vec & G2_MASK);  // c2 = parity(reg & G2)
      end
    end
  endgenerate

endmodule
