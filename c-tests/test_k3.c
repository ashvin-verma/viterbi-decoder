#define K 3
#define D_TB 6
#define G0_OCT 05
#define G1_OCT 07

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <math.h>

static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16; x ^= x >> 8; x ^= x >> 4; x &= 0xFu;
    return (uint8_t)((0x6996u >> x) & 1u);
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

static inline uint32_t next_state(uint32_t curr_state, uint8_t b, int m){
    uint32_t mask = (1u << m) - 1u;
    return ((curr_state << 1) | (b & 1u)) & mask;
}

static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b, uint32_t g0, uint32_t g1){
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity_u32(reg & g0);
    uint8_t c1 = parity_u32(reg & g1);
    return (uint8_t)((c0 << 1) | c1);
}

void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out) {
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
    for (int i = 0; i < m; ++i) {
        uint32_t b = 0;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    *T_out = t;
}

int main(void){
    srand(1);
    const int m = K-1;
    const int S = 1<<m;
    const int N = 48;
    
    uint8_t *u = malloc(N);
    for(int i=0; i<N; i++) u[i] = (i % 3 == 1) ? 1 : 0;

    int T = N + m;
    uint8_t *syms = (uint8_t*)malloc(T);
    conv_encode(u, N, syms, &T);

    printf("K=%d m=%d S=%d T=%d G0=%o G1=%o\n", K, m, S, T, G0_OCT, G1_OCT);
    printf("Input bits:\n");
    for(int i=0;i<N;i++) printf("%d", u[i]); printf("\n\n");
    
    printf("Encoded symbols (c0c1):\n");
    for(int t=0;t<T;t++) printf("%d%d ", (syms[t]>>1)&1, syms[t]&1);
    printf("\n\n");

    // Viterbi decode
    const uint32_t g0 = G0_OCT, g1 = G1_OCT;
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    for (int t = 0; t < T; ++t) surv[t] = (uint8_t*)malloc(S);
    for (int s = 0; s < S; ++s) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    for (int t = 0; t < T; ++t) {
        uint8_t r = syms[t] & 0x3u;
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

    int s_best = 0, bestm = pm_prev[0];
    for (int s = 1; s < S; ++s) if (pm_prev[s] < bestm) { bestm = pm_prev[s]; s_best = s; }

    uint8_t *u_hat = (uint8_t*)malloc(N);
    int t = T - 1, out_idx = N - 1, s = s_best;
    
    printf("Traceback: s_end=%d\n", s_best);
    printf("Decoded bits (from traceback):\n");
    
    while (t >= 0) {
        uint8_t take_p1 = surv[t][s];
        if (out_idx >= 0) {
            u_hat[out_idx] = take_p1;
            printf("t=%2d s=%d surv_bit=%d -> decoded_bit[%2d]=%d\n", t, s, take_p1, out_idx, take_p1);
            out_idx--;
        }
        if (take_p1) s = (s >> 1) | (1u << (m - 1));
        else s = (s >> 1);
        t--;
    }
    
    printf("\nComparison:\n");
    int errors = 0;
    for(int i=0; i<N; i++) {
        if(u[i] != u_hat[i]) {
            printf("idx %d: expected %d got %d\n", i, u[i], u_hat[i]);
            errors++;
        }
    }
    printf("Errors: %d/%d\n", errors, N);

    for (int i = 0; i < T; ++i) free(surv[i]);
    free(surv); free(pm_prev); free(pm_curr); free(u_hat); free(syms); free(u);
    return 0;
}

// Add function to dump survivor memory for hardware testbench
void dump_survivor_mem_for_tb() {
    printf("\n\n// Survivor memory for testbench (time x state):\n");
    for(int t=0; t<T; t++) {
        printf("// t=%2d: ", t);
        for(int s=0; s<S; s++) {
            printf("%d", surv[t][s]);
        }
        printf("\n");
    }
}
