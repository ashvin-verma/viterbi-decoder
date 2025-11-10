#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef K
#define K 3
#endif

#ifndef G0_OCT
#define G0_OCT 007
#endif

#ifndef G1_OCT
#define G1_OCT 005
#endif

// Parity function using lookup table
static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    x &= 0xFu;
    return (uint8_t)((0x6996u >> x) & 1u);
}

// Next state: shift left and insert new bit at LSB
static inline uint32_t next_state(uint32_t curr_state, uint8_t b, int m) {
    uint32_t mask = (1u << m) - 1u;
    return ((curr_state << 1) | (b & 1u)) & mask;
}

// Compute symbol from predecessor state
static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b,
                                         uint32_t g0, uint32_t g1) {
    // Register: bit 0 = newest input b, bits [K-1:1] = shifted predecessor state
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity_u32(reg & g0);
    uint8_t c1 = parity_u32(reg & g1);
    return (uint8_t)((c0 << 1) | c1);  // Pack as {y0, y1}
}

// Encode information bits, optionally adding tail bits to return to state 0
void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out, int add_tail) {
    const int m = K - 1;
    const uint32_t g0 = G0_OCT;
    const uint32_t g1 = G1_OCT;
    uint32_t state = 0;  // Initial state

    int t = 0;
    // Encode information bits
    for (int i = 0; i < N; ++i) {
        uint32_t b = in_bits[i] & 1u;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    
    // Optionally add tail bits (m zeros) to force state back to 0
    if (add_tail) {
        for (int i = 0; i < m; ++i) {
            uint32_t b = 0;
            out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
            state = next_state(state, b, m);
        }
    }
    
    *T_out = t;
}

// Generate test vectors for Verilog testbench
void generate_test_vectors(const char *filename, int num_bits, int add_tail) {
    uint8_t *in_bits = (uint8_t*)malloc(num_bits);
    uint8_t *out_syms = (uint8_t*)malloc((num_bits + K) * 2);  // Extra space for tail
    
    // Generate random input bits
    for (int i = 0; i < num_bits; i++) {
        in_bits[i] = rand() & 1;
    }
    
    // Encode
    int T;
    conv_encode(in_bits, num_bits, out_syms, &T, add_tail);
    
    // Write to file
    FILE *fp = fopen(filename, "w");
    if (!fp) {
        fprintf(stderr, "Cannot open %s\n", filename);
        exit(1);
    }
    
    fprintf(fp, "// Test vectors for convolutional encoder\n");
    fprintf(fp, "// K=%d, G0=%o, G1=%o\n", K, G0_OCT, G1_OCT);
    fprintf(fp, "// Input bits: %d, Output symbols: %d\n\n", num_bits, T);
    
    // Write input bits
    fprintf(fp, "// Input bits (binary):\n");
    for (int i = 0; i < num_bits; i++) {
        if (i % 32 == 0) fprintf(fp, "// ");
        fprintf(fp, "%d", in_bits[i]);
        if ((i + 1) % 32 == 0) fprintf(fp, "\n");
    }
    if (num_bits % 32 != 0) fprintf(fp, "\n");
    
    // Write expected output symbols
    fprintf(fp, "\n// Expected output symbols (2-bit):\n");
    for (int i = 0; i < T; i++) {
        if (i % 16 == 0) fprintf(fp, "// ");
        fprintf(fp, "%02x ", out_syms[i]);
        if ((i + 1) % 16 == 0) fprintf(fp, "\n");
    }
    if (T % 16 != 0) fprintf(fp, "\n");
    
    // Write as Verilog memory initialization
    fprintf(fp, "\n// Input bits for testbench:\n");
    for (int i = 0; i < num_bits; i++) {
        fprintf(fp, "in_bits[%d] = 1'b%d;\n", i, in_bits[i]);
    }
    
    fprintf(fp, "\n// Expected symbols for testbench:\n");
    for (int i = 0; i < T; i++) {
        fprintf(fp, "expected_syms[%d] = 2'b%d%d;\n", i, 
                (out_syms[i] >> 1) & 1, out_syms[i] & 1);
    }
    
    fclose(fp);
    free(in_bits);
    free(out_syms);
    
    printf("Generated test vectors in %s\n", filename);
    printf("  Input bits: %d\n", num_bits);
    printf("  Output symbols: %d\n", T);
}

// Verify encoding against expected behavior
int verify_encoding(const uint8_t *in_bits, int N, const uint8_t *expected_syms, int add_tail) {
    uint8_t *out_syms = (uint8_t*)malloc((N + K) * 2);
    int T;
    
    conv_encode(in_bits, N, out_syms, &T, add_tail);
    
    int errors = 0;
    int expected_T = add_tail ? (N + K - 1) : N;
    
    if (T != expected_T) {
        printf("ERROR: Symbol count mismatch. Expected %d, got %d\n", expected_T, T);
        errors++;
    }
    
    for (int i = 0; i < T; i++) {
        if (out_syms[i] != expected_syms[i]) {
            printf("ERROR at symbol %d: Expected %02x, got %02x\n", 
                   i, expected_syms[i], out_syms[i]);
            errors++;
        }
    }
    
    free(out_syms);
    return errors;
}

int main(int argc, char *argv[]) {
    int seed = 12345;
    int num_bits = 100;
    int add_tail = 1;
    const char *outfile = "encoder_test_vectors.txt";
    
    if (argc > 1) seed = atoi(argv[1]);
    if (argc > 2) num_bits = atoi(argv[2]);
    if (argc > 3) add_tail = atoi(argv[3]);
    if (argc > 4) outfile = argv[4];
    
    srand(seed);
    
    printf("Convolutional Encoder Test Vector Generator\n");
    printf("K=%d, G0=%o, G1=%o\n", K, G0_OCT, G1_OCT);
    printf("Seed: %d, Bits: %d, Add tail: %d\n\n", seed, num_bits, add_tail);
    
    // Basic sanity tests
    printf("Running basic sanity tests...\n");
    
    // Test 1: All zeros
    {
        uint8_t in[10] = {0};
        uint8_t out[12];
        int T;
        conv_encode(in, 10, out, &T, 1);
        printf("  All zeros: %d symbols generated\n", T);
        int all_zero = 1;
        for (int i = 0; i < T; i++) {
            if (out[i] != 0) all_zero = 0;
        }
        printf("    Output all zeros: %s\n", all_zero ? "PASS" : "FAIL");
    }
    
    // Test 2: All ones
    {
        uint8_t in[10];
        for (int i = 0; i < 10; i++) in[i] = 1;
        uint8_t out[12];
        int T;
        conv_encode(in, 10, out, &T, 1);
        printf("  All ones: %d symbols generated\n", T);
    }
    
    // Test 3: Alternating pattern
    {
        uint8_t in[10];
        for (int i = 0; i < 10; i++) in[i] = i & 1;
        uint8_t out[12];
        int T;
        conv_encode(in, 10, out, &T, 1);
        printf("  Alternating: %d symbols generated\n", T);
    }
    
    printf("\n");
    
    // Generate main test vectors
    generate_test_vectors(outfile, num_bits, add_tail);
    
    return 0;
}
