/*
 * Comprehensive K=3 Viterbi Decoder Test
 * Generates test vectors and validates against golden model
 * Outputs vectors for Verilog testbench validation
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

// K=3 parameters
#define K 3
#define M (K - 1)
#define S (1 << M)
#define G0_OCT 07
#define G1_OCT 05

// Parity function
static inline uint8_t parity(uint32_t x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    x &= 0xFu;
    return (uint8_t)((0x6996u >> x) & 1u);
}

// Hamming distance for 2-bit symbols
static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

// Encode one symbol: state is M bits, bit is input
// Returns 2-bit symbol, updates state
uint8_t encode_sym(uint8_t *state, uint8_t bit) {
    uint8_t r = (*state << 1) | (bit & 1);
    uint8_t c0 = parity(r & G0_OCT);
    uint8_t c1 = parity(r & G1_OCT);
    *state = ((*state << 1) | (bit & 1)) & ((1 << M) - 1);
    return (c0 << 1) | c1;
}

// Encode a sequence of bits
void encode(const uint8_t *bits, int n, uint8_t *syms) {
    uint8_t state = 0;
    for (int i = 0; i < n; i++) {
        syms[i] = encode_sym(&state, bits[i]);
    }
}

// Viterbi decoder (full traceback)
int viterbi_decode(const uint8_t *rx_syms, int T, uint8_t *out_bits) {
    int pm_prev[S], pm_curr[S];
    uint8_t **surv = malloc(T * sizeof(uint8_t *));
    for (int t = 0; t < T; t++) {
        surv[t] = malloc(S);
    }

    // Initialize - start in state 0
    for (int s = 0; s < S; s++) {
        pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    }

    // Forward pass (ACS)
    for (int t = 0; t < T; t++) {
        uint8_t r = rx_syms[t] & 0x3;

        for (int s_next = 0; s_next < S; s_next++) {
            // Predecessor states: for K=3, predecessors are s_next>>1 and (s_next>>1)|(1<<(M-1))
            int p0 = s_next >> 1;
            int p1 = (s_next >> 1) | (1 << (M - 1));

            // Input bit that leads to s_next
            int b = s_next & 1;

            // Expected symbols from each predecessor
            uint8_t r0 = (p0 << 1) | b;
            uint8_t r1 = (p1 << 1) | b;
            uint8_t e0 = (parity(r0 & G0_OCT) << 1) | parity(r0 & G1_OCT);
            uint8_t e1 = (parity(r1 & G0_OCT) << 1) | parity(r1 & G1_OCT);

            int bm0 = ham2(r, e0);
            int bm1 = ham2(r, e1);

            int m0 = pm_prev[p0] + bm0;
            int m1 = pm_prev[p1] + bm1;

            if (m1 < m0) {
                pm_curr[s_next] = m1;
                surv[t][s_next] = 1;
            } else {
                pm_curr[s_next] = m0;
                surv[t][s_next] = 0;
            }
        }

        // Swap
        for (int s = 0; s < S; s++) {
            pm_prev[s] = pm_curr[s];
        }
    }

    // Find best end state
    int best = 0;
    int best_pm = pm_prev[0];
    for (int s = 1; s < S; s++) {
        if (pm_prev[s] < best_pm) {
            best_pm = pm_prev[s];
            best = s;
        }
    }

    // Traceback
    int s = best;
    for (int t = T - 1; t >= 0; t--) {
        out_bits[t] = s & 1;  // LSB of current state is decoded bit
        if (surv[t][s]) {
            s = (s >> 1) | (1 << (M - 1));
        } else {
            s = s >> 1;
        }
    }

    // Cleanup
    for (int t = 0; t < T; t++) {
        free(surv[t]);
    }
    free(surv);

    return T;
}

// Print bits
void print_bits(const char *label, const uint8_t *bits, int n) {
    printf("%s: ", label);
    for (int i = 0; i < n; i++) {
        printf("%d", bits[i] & 1);
    }
    printf("\n");
}

// Print symbols as hex
void print_syms(const char *label, const uint8_t *syms, int n) {
    printf("%s: ", label);
    for (int i = 0; i < n; i++) {
        printf("%d ", syms[i]);
    }
    printf("\n");
}

// Test a pattern, return error count
int test_pattern(const char *name, const uint8_t *bits, int n) {
    uint8_t *syms = malloc(n);
    uint8_t *decoded = malloc(n);

    encode(bits, n, syms);
    viterbi_decode(syms, n, decoded);

    int errors = 0;
    for (int i = 0; i < n; i++) {
        if ((bits[i] & 1) != (decoded[i] & 1)) {
            errors++;
        }
    }

    printf("\n=== Test: %s ===\n", name);
    print_bits("Input ", bits, n);
    print_syms("Symbols", syms, n);
    print_bits("Decoded", decoded, n);
    printf("Errors: %d/%d\n", errors, n);

    // Output Verilog-readable format
    printf("// Verilog test vector for %s\n", name);
    printf("// input_bits = %d'b", n);
    for (int i = 0; i < n; i++) printf("%d", bits[i] & 1);
    printf(";\n");
    printf("// symbols: ");
    for (int i = 0; i < n; i++) printf("%d,", syms[i]);
    printf("\n");

    free(syms);
    free(decoded);

    return errors;
}

int main(void) {
    int total_errors = 0;
    int test_count = 0;

    printf("============================================\n");
    printf("  K=3 Viterbi Decoder Comprehensive Test\n");
    printf("  G0=7 (111), G1=5 (101)\n");
    printf("============================================\n");

    // Test 1: All zeros (8-bit)
    {
        uint8_t bits[] = {0,0,0,0,0,0,0,0};
        total_errors += test_pattern("All Zeros (8-bit)", bits, 8);
        test_count++;
    }

    // Test 2: All ones (8-bit)
    {
        uint8_t bits[] = {1,1,1,1,1,1,1,1};
        total_errors += test_pattern("All Ones (8-bit)", bits, 8);
        test_count++;
    }

    // Test 3: Alternating 10 (8-bit)
    {
        uint8_t bits[] = {1,0,1,0,1,0,1,0};
        total_errors += test_pattern("Alternating 10 (8-bit)", bits, 8);
        test_count++;
    }

    // Test 4: Alternating 01 (8-bit)
    {
        uint8_t bits[] = {0,1,0,1,0,1,0,1};
        total_errors += test_pattern("Alternating 01 (8-bit)", bits, 8);
        test_count++;
    }

    // Test 5: Single 1 at start
    {
        uint8_t bits[] = {1,0,0,0,0,0,0,0};
        total_errors += test_pattern("Single 1 at start", bits, 8);
        test_count++;
    }

    // Test 6: Single 1 at end
    {
        uint8_t bits[] = {0,0,0,0,0,0,0,1};
        total_errors += test_pattern("Single 1 at end", bits, 8);
        test_count++;
    }

    // Test 7: Pattern from testbench (10110100)
    {
        uint8_t bits[] = {1,0,1,1,0,1,0,0};
        total_errors += test_pattern("Pattern 10110100", bits, 8);
        test_count++;
    }

    // Test 8: 16-bit mixed pattern
    {
        uint8_t bits[] = {1,0,1,0,1,1,0,0,1,1,1,0,0,0,1,0};
        total_errors += test_pattern("16-bit mixed", bits, 16);
        test_count++;
    }

    // Test 9: 32-bit pattern (full frame)
    {
        uint8_t bits[32];
        // Pattern: repeating 10110100
        for (int i = 0; i < 32; i++) {
            int idx = i % 8;
            uint8_t p[] = {1,0,1,1,0,1,0,0};
            bits[i] = p[idx];
        }
        total_errors += test_pattern("32-bit repeating pattern", bits, 32);
        test_count++;
    }

    // Test 10: 32-bit all zeros
    {
        uint8_t bits[32] = {0};
        total_errors += test_pattern("32-bit all zeros", bits, 32);
        test_count++;
    }

    // Test 11: 32-bit all ones
    {
        uint8_t bits[32];
        for (int i = 0; i < 32; i++) bits[i] = 1;
        total_errors += test_pattern("32-bit all ones", bits, 32);
        test_count++;
    }

    // Test 12: PRBS-like pattern
    {
        uint8_t bits[32];
        uint8_t lfsr = 0x7;
        for (int i = 0; i < 32; i++) {
            bits[i] = lfsr & 1;
            uint8_t newbit = ((lfsr >> 2) ^ (lfsr >> 1)) & 1;
            lfsr = ((lfsr << 1) | newbit) & 0x7;
        }
        total_errors += test_pattern("32-bit PRBS", bits, 32);
        test_count++;
    }

    // Test 13: Single bit transitions
    {
        uint8_t bits[] = {0,0,0,1,1,1,0,0};
        total_errors += test_pattern("Single transition 0->1->0", bits, 8);
        test_count++;
    }

    // Test 14: Burst pattern
    {
        uint8_t bits[] = {1,1,0,0,1,1,0,0};
        total_errors += test_pattern("Burst 1100", bits, 8);
        test_count++;
    }

    // Test 15: Random-like 16-bit
    {
        uint8_t bits[] = {0,1,1,0,0,0,1,1,1,0,1,0,0,1,1,0};
        total_errors += test_pattern("Random 16-bit", bits, 16);
        test_count++;
    }

    printf("\n============================================\n");
    printf("  SUMMARY: %d/%d tests passed\n", test_count - (total_errors > 0 ? 1 : 0), test_count);
    printf("  Total bit errors: %d\n", total_errors);
    if (total_errors == 0) {
        printf("  *** ALL TESTS PASSED ***\n");
    } else {
        printf("  *** SOME TESTS FAILED ***\n");
    }
    printf("============================================\n");

    return (total_errors > 0) ? 1 : 0;
}
