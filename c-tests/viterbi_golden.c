#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#ifndef K
#define K 5           
#endif
    // constraint length

#ifndef D_TB
#define D_TB 16           
#endif
    // traceback depth

#ifndef G0_OCT
#define G0_OCT 023
#endif

#ifndef G1_OCT
#define G1_OCT 035
#endif

static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16; // xor-reduce to 16 bits
    x ^= x >> 8; // xor-reduce to 8 bits
    x ^= x >> 4; // xor-reduce to 4 bits
    x &= 0xFu; // keep only lower 4 bits
    return (uint8_t)((0x6996u >> x) & 1u); // lookup parity from precomputed LUT
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

static inline uint8_t encode_symbol(uint8_t state, uint8_t input_bit) {
    uint8_t shift_reg = (state << 1) | (input_bit & 0x1u);
    uint8_t out0 = parity_u32(shift_reg & G0_OCT);
    uint8_t out1 = parity_u32(shift_reg & G1_OCT);
    return (out0 << 1) | out1;
}

static uint32_t oct_to_mask(int oct, int Kbits) {
    uint32_t mask = 0;
    int v = oct;
    int bitpos = 0;
    while (v > 0) {
        int tri = v & 7; // select lowest 3 bits
        for (int i = 0; i < 3; ++i) {
            if (tri & (1 << i)) {
                int pos = bitpos + i;
                if (pos < Kbits) mask |= (1u << pos);
            }
        }
        v >>= 3;
        bitpos += 3;
    }
    return mask;
}

static inline uint32_t next_state(uint32_t curr_state, uint8_t input_bit, int mem_bits) { 
    return (curr_state >> 1) | ((input_bit & 0x1u) << (mem_bits - 1));
}

static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b, uint32_t g0_mask, uint32_t g1_mask) {
    // Register bits: bit0 = current input b, bits[1..m] = previous m bits = p
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity_u32(reg & g0_mask);
    uint8_t c1 = parity_u32(reg & g1_mask);
    return (uint8_t)((c0 << 1) | c1); // [c0 c1] packed in 2 LSBs
}


void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out) {
    const int m = K - 1;
    const uint32_t g0 = oct_to_mask(G0_OCT, K);
    const uint32_t g1 = oct_to_mask(G1_OCT, K);
    uint32_t state = 0; // holds previous m bits

    int t = 0;
    for (int i = 0; i < N; ++i) {
        uint32_t b = in_bits[i] & 1u;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    // Tail: append m zeros to force state->0
    for (int i = 0; i < m; ++i) {
        uint32_t b = 0;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    *T_out = t;
}

// Hard-decision Viterbi (traceback). rx_syms length T (2-bit symbols). Returns number of decoded bits (N=T-m).
int viterbi_decode(const uint8_t *rx_syms, int T, uint8_t *out_bits) {
    const int m = K - 1;
    const int S = 1 << m; // states
    const uint32_t g0 = oct_to_mask(G0_OCT, K);
    const uint32_t g1 = oct_to_mask(G1_OCT, K);

    // Path metrics
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    if (!pm_prev || !pm_curr) { fprintf(stderr, "OOM pm\n"); exit(1); }

    // Survivor bits: store winner (0: pred=p0, 1: pred=p1) for each (t, state)
    // Simple byte storage for clarity; bit-pack later if you need speed.
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    if (!surv) { fprintf(stderr, "OOM surv\n"); exit(1); }
    for (int t = 0; t < T; ++t) {
        surv[t] = (uint8_t*)malloc(S);
        if (!surv[t]) { fprintf(stderr, "OOM surv row\n"); exit(1); }
    }

    // Init metrics (start in state 0)
    for (int s = 0; s < S; ++s) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    // Forward pass
    for (int t = 0; t < T; ++t) {
        uint8_t r = rx_syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; ++s_next) {
            // Two predecessors that can go into s_next:
            uint32_t p0 = (uint32_t)(s_next >> 1);                    // came from input b=0
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m - 1))); // came from input b=1

            int bm0 = ham2(r, conv_sym_from_pred(p0, 0, g0, g1));
            int bm1 = ham2(r, conv_sym_from_pred(p1, 1, g0, g1));

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
        // swap
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;
    }

    // Choose end state: if tail-terminated, best is state 0; otherwise pick argmin
    int s_best = 0;
    int bestm = pm_prev[0];
    for (int s = 1; s < S; ++s) {
        if (pm_prev[s] < bestm) { bestm = pm_prev[s]; s_best = s; }
    }

    // Traceback
    // The input length N = T - m (tail bits), output out_bits[0..N-1]
    int N = T - m;
    int t = T - 1;
    int out_idx = N - 1;
    int s = s_best;
    while (t >= 0) {
        uint8_t b = surv[t][s];            // winner bit IS the decoded input at time t
        if (out_idx >= 0) out_bits[out_idx--] = b;
        // predecessor state from s and b:
        if (b == 0) s = s >> 1;
        else        s = (s >> 1) | (1u << (m - 1));
        --t;
    }

    // Cleanup
    for (int i = 0; i < T; ++i) free(surv[i]);
    free(surv);
    free(pm_prev);
    free(pm_curr);
    return N;
}

#define TEST_MAIN

#ifdef TEST_MAIN
// Quick sanity: random roundtrip
int main(void) {
    const int N = 1000; // info bits
    uint8_t *u = (uint8_t*)malloc(N);
    for (int i = 0; i < N; ++i) u[i] = rand() & 1;

    // Encode
    int T = N + (K - 1);
    uint8_t *syms = (uint8_t*)malloc(T);
    conv_encode(u, N, syms, &T);

    // introduce a few hard errors to see correction
    for (int i = 0; i < T; ++i) {
        if ((rand() % 100) < 5) { // 5% symbol flips (randomly flip one coded bit)
            syms[i] ^= (1u << (rand() & 1));
        }
    }

    // Decode
    uint8_t *u_hat = (uint8_t*)malloc(N);
    int Nd = viterbi_decode(syms, T, u_hat);

    int err = 0;
    for (int i = 0; i < N && i < Nd; ++i) if ((u[i] & 1) != (u_hat[i] & 1)) ++err;

    printf("K=%d D=%d  N=%d  T=%d  decoded=%d  bit_errors=%d\n", K, D_TB, N, T, Nd, err);

    free(u); free(syms); free(u_hat);
    return 0;
}
#endif
