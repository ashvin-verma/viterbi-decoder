// Test traceback with exact same parameters as testbench
// Generate input pattern, encode, decode, show what outputs should be

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define K 3
#define M_PARAM (K-1)
#define S_PARAM (1<<M_PARAM)
#define D_PARAM 6
#define N_BITS 48
#define T_SYMS 50

#define G0 05  // octal
#define G1 07  // octal

static inline int parity_u32(uint32_t x) {
    x ^= x >> 16; x ^= x >> 8; x ^= x >> 4; x ^= x >> 2; x ^= x >> 1;
    return (int)(x & 1u);
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t diff = (a ^ b) & 0x3u;
    return parity_u32(diff & 1u) + parity_u32(diff & 2u);
}

static inline uint32_t next_state(uint32_t curr, uint8_t b, int m){
    return ((curr << 1) | (b & 1u)) & ((1u << m) - 1u);
}

static inline uint8_t conv_sym(uint32_t p, uint32_t b, uint32_t g0, uint32_t g1){
    uint32_t reg = (b & 1u) | (p << 1);
    return (uint8_t)((parity_u32(reg & g0) << 1) | parity_u32(reg & g1));
}

void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out) {
    int m = M_PARAM;    uint32_t state = 0;
    int t = 0;
    for (int i = 0; i < N; i++) {
        out_syms[t++] = conv_sym(state, in_bits[i], G0, G1);
        state = next_state(state, in_bits[i], m);
    }
    while (state != 0) {
        out_syms[t++] = conv_sym(state, 0, G0, G1);
        state = next_state(state, 0, m);
    }
    *T_out = t;
}

void viterbi_decode(const uint8_t *rx_syms, int T, uint8_t **surv_out, int *Nd_out) {
    int m = M_PARAM;
    int S = S_PARAM;
    int D = D_PARAM;
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    for (int t = 0; t < T; t++) surv[t] = (uint8_t*)malloc(S);
    
    for (int s = 0; s < S; s++) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    
    for (int t = 0; t < T; t++) {
        uint8_t r = rx_syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; s_next++) {
            uint32_t p0 = (uint32_t)(s_next >> 1);
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m - 1)));
            uint8_t b_t = (uint8_t)(s_next & 1u);
            
            uint8_t e0 = conv_sym(p0, b_t, G0, G1);
            uint8_t e1 = conv_sym(p1, b_t, G0, G1);
            
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
    
    // Traceback from state 0 at end
    uint8_t *u_hat = (uint8_t*)calloc(T, 1);
    uint32_t s = 0;
    int Nd = 0;
    
    printf("\nTraceback sequence (backwards from t=%d):\n", T-1);
    for (int t = T - 1; t >= D; t--) {
        uint8_t take_p1 = surv[t][s];
        u_hat[Nd++] = take_p1;
        printf("t=%2d s=%d surv=%d -> decoded_bit[%2d]=%d\n", t, s, take_p1, Nd-1, take_p1);
        
        if (take_p1) {
            s = (s >> 1) | (1u << (m - 1));
        } else {
            s = s >> 1;
        }
    }
    
    printf("\nDecoded %d bits (expected %d info bits)\n", Nd, N_BITS);
    printf("Decoded sequence: ");
    for (int i = Nd-1; i >= 0; i--) printf("%d", u_hat[i]);
    printf(" (reversed, oldest first)\n");
    
    *surv_out = surv[0];  // just return pointer to first row (we'll print all)
    *Nd_out = Nd;
    
    // Print survivor memory
    printf("\nSurvivor memory (all states, all times):\n");
    for (int t = 0; t < T; t++) {
        printf("t=%2d: ", t);
        for (int s = S-1; s >= 0; s--) printf("%d", surv[t][s]);
        printf("\n");
    }
    
    free(u_hat);
    for (int t = 0; t < T; t++) free(surv[t]);
    free(surv);
    free(pm_prev);
    free(pm_curr);
}

int main() {
    int N = N_BITS;
    int T = T_SYMS;
    int D = D_PARAM;
    
    // Generate input with testbench pattern
    uint8_t *input_bits = (uint8_t*)calloc(N, 1);
    printf("Input sequence (N=%d):\n", N);
    for (int i = 0; i < N; i++) {
        input_bits[i] = (i % 3 == 1) ? 1 : 0;
        if (i < 20) printf("%d", input_bits[i]);
    }
    printf("...\n\n");
    
    // Encode
    uint8_t *syms = (uint8_t*)calloc(T, 1);
    int T_actual;
    conv_encode(input_bits, N, syms, &T_actual);
    printf("Encoded to T=%d symbols (expected %d)\n", T_actual, T);
    
    // Decode
    uint8_t *surv_dummy;
    int Nd;
    viterbi_decode(syms, T, &surv_dummy, &Nd);
    
    printf("\nExpected outputs in testbench (with D-1 offset):\n");
    printf("Testbench expects decoded_bit[i] to match input_bit[i+D-1]\n");
    printf("With D=%d, expected_idx maps to input index:\n", D);
    for (int i = 0; i < 10; i++) {
        int input_idx = i + D - 1;
        printf("  decoded[%d] should match input[%d] = %d\n", i, input_idx, input_bits[input_idx]);
    }
    
    free(input_bits);
    free(syms);
    
    return 0;
}
