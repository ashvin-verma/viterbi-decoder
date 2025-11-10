#define K 3
#define D_TB 6
#define G0_OCT 05
#define G1_OCT 07

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16; x ^= x >> 8; x ^= x >> 4; x &= 0xFu;
    return (uint8_t)((0x6996u >> x) & 1u);
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

static inline uint32_t next_state(uint32_t curr_state, uint8_t b, int m){
    return ((curr_state << 1) | (b & 1u)) & ((1u << m) - 1u);
}

static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b, uint32_t g0, uint32_t g1){
    uint32_t reg = (b & 1u) | (p << 1);
    return (uint8_t)((parity_u32(reg & g0) << 1) | parity_u32(reg & g1));
}

void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out) {
    const int m = K - 1;
    uint32_t state = 0;
    int t = 0;
    for (int i = 0; i < N; ++i) {
        out_syms[t++] = conv_sym_from_pred(state, in_bits[i] & 1u, G0_OCT, G1_OCT);
        state = next_state(state, in_bits[i], m);
    }
    for (int i = 0; i < m; ++i) {
        out_syms[t++] = conv_sym_from_pred(state, 0, G0_OCT, G1_OCT);
        state = next_state(state, 0, m);
    }
    *T_out = t;
}

int main(void){
    const int m = K-1;
    const int S = 1<<m;
    const int N = 48;
    
    uint8_t *u = malloc(N);
    for(int i=0; i<N; i++) u[i] = (i % 3 == 1) ? 1 : 0;

    int T = N + m;
    uint8_t *syms = malloc(T);
    conv_encode(u, N, syms, &T);

    // Viterbi forward pass - compute survivor memory
    int *pm_prev = malloc(S * sizeof(int));
    int *pm_curr = malloc(S * sizeof(int));
    uint8_t **surv = malloc(T * sizeof(uint8_t*));
    for (int t = 0; t < T; ++t) surv[t] = malloc(S);
    for (int s = 0; s < S; ++s) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    for (int t = 0; t < T; ++t) {
        uint8_t r = syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; ++s_next) {
            uint32_t p0 = s_next >> 1;
            uint32_t p1 = (s_next >> 1) | (1u << (m - 1));
            uint8_t b_t = s_next & 1u;
            uint8_t e0 = conv_sym_from_pred(p0, b_t, G0_OCT, G1_OCT);
            uint8_t e1 = conv_sym_from_pred(p1, b_t, G0_OCT, G1_OCT);
            int m0 = pm_prev[p0] + ham2(r, e0);
            int m1 = pm_prev[p1] + ham2(r, e1);
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

    // Dump survivor memory in testbench format
    printf("// Survivor memory for K=%d, N=%d, T=%d\n", K, N, T);
    printf("// Pattern: bit_hist[t] = (t %% 3 == 1)\n\n");
    
    for(int t=0; t<T; t++) {
        printf("t=%2d surv_row=4'b", t);
        for(int s=S-1; s>=0; s--) printf("%d", surv[t][s]);
        printf("\n");
    }

    for (int t = 0; t < T; ++t) free(surv[t]);
    free(surv); free(pm_prev); free(pm_curr); free(syms); free(u);
    return 0;
}
