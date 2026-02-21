/*
 * gen_golden_vectors.c
 *
 * Generates golden test vectors as JSON for the Viterbi decoder.
 * Compile-time defines: -DK=5 -DG0_OCT=023 -DG1_OCT=035
 *
 * Build example:
 *   gcc -DK=5 -DG0_OCT=023 -DG1_OCT=035 -o gen_golden gen_golden_vectors.c
 *   ./gen_golden > golden_k5.json
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

/* ---------- compile-time parameters ---------- */

#ifndef K
#define K 5
#endif

#ifndef G0_OCT
#define G0_OCT 023
#endif

#ifndef G1_OCT
#define G1_OCT 035
#endif

#define M       (K - 1)
#define STATES  (1 << M)
#define MAX_FRAME 32          /* max symbols including tails */
#define MAX_DATA  (MAX_FRAME - M)

/* ================================================================
 * Core codec functions (copied from viterbi_golden.c to avoid
 * #include conflicts with its multiple main() definitions).
 * ================================================================ */

static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    x &= 0xFu;
    return (uint8_t)((0x6996u >> x) & 1u);
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

static inline uint32_t next_state(uint32_t curr_state, uint8_t b, int m) {
    uint32_t mask = (1u << m) - 1u;
    return ((curr_state << 1) | (b & 1u)) & mask;
}

static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b,
                                         uint32_t g0, uint32_t g1) {
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity_u32(reg & g0);
    uint8_t c1 = parity_u32(reg & g1);
    return (uint8_t)((c0 << 1) | c1);
}

static void conv_encode(const uint8_t *in_bits, int N,
                        uint8_t *out_syms, int *T_out) {
    const int m = K - 1;
    const uint32_t g0 = G0_OCT;
    const uint32_t g1 = G1_OCT;
    uint32_t state = 0;

    int t = 0;
    for (int i = 0; i < N; ++i) {
        uint32_t b = in_bits[i] & 1u;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    /* Tail: append m zeros to flush encoder to state 0 */
    for (int i = 0; i < m; ++i) {
        uint32_t b = 0;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    *T_out = t;
}

static int viterbi_decode(const uint8_t *rx_syms, int T, uint8_t *out_bits) {
    const int m = K - 1;
    const int S = 1 << m;
    const uint32_t g0 = G0_OCT;
    const uint32_t g1 = G1_OCT;

    int *pm_prev = (int *)malloc(S * sizeof(int));
    int *pm_curr = (int *)malloc(S * sizeof(int));
    if (!pm_prev || !pm_curr) { fprintf(stderr, "OOM pm\n"); exit(1); }

    uint8_t **surv = (uint8_t **)malloc(T * sizeof(uint8_t *));
    if (!surv) { fprintf(stderr, "OOM surv\n"); exit(1); }
    for (int t = 0; t < T; ++t) {
        surv[t] = (uint8_t *)malloc(S);
        if (!surv[t]) { fprintf(stderr, "OOM surv row\n"); exit(1); }
    }

    for (int s = 0; s < S; ++s)
        pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    /* Forward pass */
    for (int t = 0; t < T; ++t) {
        uint8_t r = rx_syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; ++s_next) {
            uint32_t p0 = (uint32_t)(s_next >> 1);
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m - 1)));
            uint8_t b_t = (uint8_t)(s_next & 1u);

            uint8_t e0 = conv_sym_from_pred(p0, b_t, g0, g1);
            uint8_t e1 = conv_sym_from_pred(p1, b_t, g0, g1);

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
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;
    }

    /* Choose end state */
    int s_best = 0;
    int bestm = pm_prev[0];
    for (int s = 1; s < S; ++s) {
        if (pm_prev[s] < bestm) { bestm = pm_prev[s]; s_best = s; }
    }

    /* Traceback */
    int N = T - m;
    int t = T - 1;
    int out_idx = N - 1;
    int s = s_best;

    while (t >= 0) {
        uint8_t take_p1 = surv[t][s];
        if (out_idx >= 0) out_bits[out_idx--] = take_p1;
        if (take_p1)
            s = (s >> 1) | (1u << (m - 1));
        else
            s = (s >> 1);
        --t;
    }

    for (int i = 0; i < T; ++i) free(surv[i]);
    free(surv);
    free(pm_prev);
    free(pm_curr);
    return N;
}

/* ================================================================
 * PRBS-7 generator: x^7 + x^6 + 1, seed=0x01
 * Taps at bits 6 and 5 (0-indexed).
 * Output = LSB of state each step.
 * ================================================================ */

static void prbs7_generate(uint8_t *out, int count) {
    uint32_t state = 0x01;
    for (int i = 0; i < count; ++i) {
        out[i] = (uint8_t)(state & 1u);
        uint32_t new_bit = ((state >> 6) ^ (state >> 5)) & 1u;
        state = ((state << 1) | new_bit) & 0x7Fu;
    }
}

/* ================================================================
 * Test vector structure and generation
 * ================================================================ */

typedef struct {
    const char *name;
    int         noisy;
    int         num_data_bits;
    uint8_t     bits[MAX_DATA];
    uint8_t     symbols[MAX_FRAME];
    int         num_symbols;
    uint8_t     decoded[MAX_DATA];
    int         num_decoded;
} test_vector_t;

/* Encode a clean vector: fill bits[], symbols[], decoded[] */
static void make_clean_vector(test_vector_t *v, const char *name,
                              const uint8_t *data, int N) {
    v->name = name;
    v->noisy = 0;
    v->num_data_bits = N;
    memcpy(v->bits, data, N);

    int T = 0;
    conv_encode(data, N, v->symbols, &T);
    v->num_symbols = T;

    v->num_decoded = viterbi_decode(v->symbols, T, v->decoded);
}

/* Encode, apply bit flips, then decode the noisy stream */
static void make_noisy_vector(test_vector_t *v, const char *name,
                              const uint8_t *data, int N,
                              const int *flip_sym_idx,
                              const int *flip_bit_pos,
                              int num_flips) {
    v->name = name;
    v->noisy = 1;
    v->num_data_bits = N;
    memcpy(v->bits, data, N);

    int T = 0;
    conv_encode(data, N, v->symbols, &T);
    v->num_symbols = T;

    /* Apply bit flips to symbol stream */
    for (int i = 0; i < num_flips; ++i) {
        int idx = flip_sym_idx[i];
        int bit = flip_bit_pos[i];
        if (idx < T) {
            v->symbols[idx] ^= (1u << bit);
        }
    }

    v->num_decoded = viterbi_decode(v->symbols, T, v->decoded);
}

/* ================================================================
 * JSON output helpers
 * ================================================================ */

static void print_uint8_array(const uint8_t *arr, int len) {
    printf("[");
    for (int i = 0; i < len; ++i) {
        printf("%d", arr[i] & 1);
        if (i < len - 1) printf(",");
    }
    printf("]");
}

static void print_sym_array(const uint8_t *arr, int len) {
    printf("[");
    for (int i = 0; i < len; ++i) {
        printf("%d", arr[i] & 3);
        if (i < len - 1) printf(",");
    }
    printf("]");
}

static void print_vector_json(const test_vector_t *v, int last) {
    printf("    {\n");
    printf("      \"name\": \"%s\",\n", v->name);
    printf("      \"noisy\": %s,\n", v->noisy ? "true" : "false");
    printf("      \"num_data_bits\": %d,\n", v->num_data_bits);

    printf("      \"bits\": ");
    print_uint8_array(v->bits, v->num_data_bits);
    printf(",\n");

    printf("      \"symbols\": ");
    print_sym_array(v->symbols, v->num_symbols);
    printf(",\n");

    printf("      \"decoded\": ");
    print_uint8_array(v->decoded, v->num_decoded);
    printf("\n");

    printf("    }%s\n", last ? "" : ",");
}

/* ================================================================
 * Main: generate all 25 test vectors and print JSON
 * ================================================================ */

#define NUM_TESTS 25

int main(void) {
    test_vector_t tests[NUM_TESTS];
    memset(tests, 0, sizeof(tests));

    int idx = 0;

    /* ----------------------------------------------------------
     * Category A: Constant
     * ---------------------------------------------------------- */

    /* 1. 8bit_all_zeros */
    {
        uint8_t data[8] = {0,0,0,0,0,0,0,0};
        make_clean_vector(&tests[idx++], "8bit_all_zeros", data, 8);
    }

    /* 2. 8bit_all_ones */
    {
        uint8_t data[8] = {1,1,1,1,1,1,1,1};
        make_clean_vector(&tests[idx++], "8bit_all_ones", data, 8);
    }

    /* 3. 16bit_all_zeros */
    {
        uint8_t data[16] = {0};
        make_clean_vector(&tests[idx++], "16bit_all_zeros", data, 16);
    }

    /* ----------------------------------------------------------
     * Category B: Alternating
     * ---------------------------------------------------------- */

    /* 4. 8bit_alt_10 */
    {
        uint8_t data[8] = {1,0,1,0,1,0,1,0};
        make_clean_vector(&tests[idx++], "8bit_alt_10", data, 8);
    }

    /* 5. 8bit_alt_01 */
    {
        uint8_t data[8] = {0,1,0,1,0,1,0,1};
        make_clean_vector(&tests[idx++], "8bit_alt_01", data, 8);
    }

    /* 6. 16bit_alt_10 */
    {
        uint8_t data[16] = {1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0};
        make_clean_vector(&tests[idx++], "16bit_alt_10", data, 16);
    }

    /* ----------------------------------------------------------
     * Category C: Single-bit isolation
     * ---------------------------------------------------------- */

    /* 7. single_1_start */
    {
        uint8_t data[8] = {1,0,0,0,0,0,0,0};
        make_clean_vector(&tests[idx++], "single_1_start", data, 8);
    }

    /* 8. single_1_end */
    {
        uint8_t data[8] = {0,0,0,0,0,0,0,1};
        make_clean_vector(&tests[idx++], "single_1_end", data, 8);
    }

    /* 9. single_0_in_ones */
    {
        uint8_t data[8] = {1,1,1,1,1,1,1,0};
        make_clean_vector(&tests[idx++], "single_0_in_ones", data, 8);
    }

    /* 10. single_0_mid */
    {
        uint8_t data[8] = {1,1,1,0,1,1,1,1};
        make_clean_vector(&tests[idx++], "single_0_mid", data, 8);
    }

    /* ----------------------------------------------------------
     * Category D: Burst & transition
     * ---------------------------------------------------------- */

    /* 11. burst_1100 */
    {
        uint8_t data[8] = {1,1,0,0,1,1,0,0};
        make_clean_vector(&tests[idx++], "burst_1100", data, 8);
    }

    /* 12. transition_0to1 */
    {
        uint8_t data[8] = {0,0,0,0,1,1,1,1};
        make_clean_vector(&tests[idx++], "transition_0to1", data, 8);
    }

    /* 13. transition_1to0 */
    {
        uint8_t data[8] = {1,1,1,1,0,0,0,0};
        make_clean_vector(&tests[idx++], "transition_1to0", data, 8);
    }

    /* 14. double_burst_16 */
    {
        uint8_t data[16] = {1,1,0,0,1,1,0,0,1,1,0,0,1,1,0,0};
        make_clean_vector(&tests[idx++], "double_burst_16", data, 16);
    }

    /* ----------------------------------------------------------
     * Category E: Structured
     * ---------------------------------------------------------- */

    /* 15. walking_ones */
    {
        uint8_t data[8] = {0,0,0,1,0,0,1,0};
        make_clean_vector(&tests[idx++], "walking_ones", data, 8);
    }

    /* 16. checkerboard_16 */
    {
        uint8_t data[16] = {1,1,0,0,1,1,0,0,1,1,0,0,1,1,0,0};
        make_clean_vector(&tests[idx++], "checkerboard_16", data, 16);
    }

    /* 17. ramp */
    {
        uint8_t data[8] = {0,0,0,1,1,0,1,1};
        make_clean_vector(&tests[idx++], "ramp", data, 8);
    }

    /* ----------------------------------------------------------
     * Category F: Pseudo-random
     * ---------------------------------------------------------- */

    /* 18. prbs7_8 */
    {
        uint8_t data[8];
        prbs7_generate(data, 8);
        make_clean_vector(&tests[idx++], "prbs7_8", data, 8);
    }

    /* 19. prbs7_16 */
    {
        uint8_t data[16];
        prbs7_generate(data, 16);
        make_clean_vector(&tests[idx++], "prbs7_16", data, 16);
    }

    /* 20. standard_test */
    {
        uint8_t data[8] = {1,0,1,1,0,1,0,0};
        make_clean_vector(&tests[idx++], "standard_test", data, 8);
    }

    /* ----------------------------------------------------------
     * Category G: Maximum frame
     * ---------------------------------------------------------- */

    /* 21. max_zeros: N = MAX_FRAME - M all-zero bits */
    {
        int N = MAX_DATA;
        uint8_t data[MAX_DATA];
        memset(data, 0, N);
        make_clean_vector(&tests[idx++], "max_zeros", data, N);
    }

    /* 22. max_prbs: N = MAX_FRAME - M bits from PRBS-7 */
    {
        int N = MAX_DATA;
        uint8_t data[MAX_DATA];
        prbs7_generate(data, N);
        make_clean_vector(&tests[idx++], "max_prbs", data, N);
    }

    /* ----------------------------------------------------------
     * Category H: Noisy
     * ---------------------------------------------------------- */

    /* 23. noisy_1flip: 10110100 encoded, flip bit 0 of symbol 2 */
    {
        uint8_t data[8] = {1,0,1,1,0,1,0,0};
        int flip_idx[] = {2};
        int flip_bit[] = {0};
        make_noisy_vector(&tests[idx++], "noisy_1flip", data, 8,
                          flip_idx, flip_bit, 1);
    }

    /* 24. noisy_2flip: 10110100 encoded, flip bit 0 of sym 2 and bit 1 of sym 5 */
    {
        uint8_t data[8] = {1,0,1,1,0,1,0,0};
        int flip_idx[] = {2, 5};
        int flip_bit[] = {0, 1};
        make_noisy_vector(&tests[idx++], "noisy_2flip", data, 8,
                          flip_idx, flip_bit, 2);
    }

    /* 25. noisy_16_1flip: first 16 bits of PRBS-7 encoded, flip bit 0 of symbol 4 */
    {
        uint8_t data[16];
        prbs7_generate(data, 16);
        int flip_idx[] = {4};
        int flip_bit[] = {0};
        make_noisy_vector(&tests[idx++], "noisy_16_1flip", data, 16,
                          flip_idx, flip_bit, 1);
    }

    /* ----------------------------------------------------------
     * Output JSON
     * ---------------------------------------------------------- */

    printf("{\n");
    printf("  \"k\": %d,\n", K);
    printf("  \"m\": %d,\n", M);
    printf("  \"max_frame\": %d,\n", MAX_FRAME);
    printf("  \"tests\": [\n");

    for (int i = 0; i < NUM_TESTS; ++i) {
        print_vector_json(&tests[i], (i == NUM_TESTS - 1));
    }

    printf("  ]\n");
    printf("}\n");

    return 0;
}
