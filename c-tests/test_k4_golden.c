// Golden model for K=4, G0=17, G1=13 (octal)
// Test Viterbi encoder/decoder

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define K 4
#define M (K-1)
#define S (1<<M)
#define D 6
#define N 48
#define T 50

#define G0 017  // octal
#define G1 013  // octal

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

void conv_encode(const uint8_t *in_bits, int n_bits, uint8_t *out_syms, int *T_out) {
    int m = M;
    uint32_t state = 0;
    int t = 0;
    
    printf("Encoding %d bits with K=%d, M=%d, G0=%03o, G1=%03o\n", n_bits, K, M, G0, G1);
    
    for (int i = 0; i < n_bits; i++) {
        out_syms[t++] = conv_sym(state, in_bits[i], G0, G1);
        if (i < 10) printf("  i=%2d: bit=%d, state=%d, sym=%d\n", i, in_bits[i], state, out_syms[t-1]);
        state = next_state(state, in_bits[i], m);
    }
    
    // Tail bits to return to state 0
    printf("  ... (middle bits omitted) ...\n");
    printf("Tail bits:\n");
    while (state != 0) {
        out_syms[t] = conv_sym(state, 0, G0, G1);
        printf("  t=%2d: state=%d, sym=%d\n", t, state, out_syms[t]);
        state = next_state(state, 0, m);
        t++;
    }
    
    *T_out = t;
}

void viterbi_forward(const uint8_t *rx_syms, int t_syms, uint8_t **surv) {
    int m = M;
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    
    for (int s = 0; s < S; s++) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    
    printf("\nViterbi Forward Pass:\n");
    
    for (int t = 0; t < t_syms; t++) {
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
        
        // Print survivor memory for this time step
        if (t < 10 || t >= t_syms - 5) {
            printf("  t=%2d: surv=", t);
            for (int s = S-1; s >= 0; s--) printf("%d", surv[t][s]);
            printf("\n");
        } else if (t == 10) {
            printf("  ... (middle omitted) ...\n");
        }
        
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;
    }
    
    free(pm_prev);
    free(pm_curr);
}

void traceback_and_decode(uint8_t **surv, int t_syms, int d_depth, uint8_t *decoded, int *nd_out) {
    uint32_t s = 0;  // end state
    int m = M;
    int nd = 0;
    
    printf("\nTraceback from t=%d back %d steps:\n", t_syms-1, t_syms-d_depth);
    
    for (int t = t_syms - 1; t >= d_depth; t--) {
        uint8_t surv_bit = surv[t][s];
        decoded[nd] = surv_bit;
        
        if (nd < 10 || nd >= (t_syms - d_depth) - 5) {
            printf("  t=%2d s=%d surv=%d -> decoded[%2d]=%d", t, s, surv_bit, nd, surv_bit);
            
            // Compute next state
            uint32_t s_next;
            if (surv_bit) {
                s_next = (s >> 1) | (1u << (m - 1));
            } else {
                s_next = s >> 1;
            }
            printf(" (next_s=%d)\n", s_next);
            s = s_next;
        } else if (nd == 10) {
            printf("  ... (middle omitted) ...\n");
            // Still compute state
            if (surv_bit) {
                s = (s >> 1) | (1u << (m - 1));
            } else {
                s = s >> 1;
            }
        } else {
            // Compute state
            if (surv_bit) {
                s = (s >> 1) | (1u << (m - 1));
            } else {
                s = s >> 1;
            }
        }
        nd++;
    }
    
    *nd_out = nd;
}

int main() {
    // Generate input sequence - simple pattern
    uint8_t *input_bits = (uint8_t*)calloc(N, 1);
    
    printf("=== VITERBI DECODER TEST: K=%d, M=%d, S=%d, D=%d ===\n", K, M, S, D);
    printf("Generator polynomials: G0=%03o, G1=%03o (octal)\n\n", G0, G1);
    
    printf("Input sequence (N=%d bits):\n", N);
    for (int i = 0; i < N; i++) {
        input_bits[i] = (i % 3 == 1) ? 1 : 0;
        if (i < 20 || i >= N - 5) {
            printf("%d", input_bits[i]);
            if ((i+1) % 10 == 0) printf(" ");
        } else if (i == 20) {
            printf("...");
        }
    }
    printf("\n\n");
    
    // Encode
    uint8_t *syms = (uint8_t*)calloc(T, 1);
    int T_actual;
    conv_encode(input_bits, N, syms, &T_actual);
    
    printf("\nTotal symbols: %d\n", T_actual);
    
    // Run Viterbi forward pass
    uint8_t **surv = (uint8_t**)malloc(T_actual * sizeof(uint8_t*));
    for (int t = 0; t < T_actual; t++) surv[t] = (uint8_t*)malloc(S);
    viterbi_forward(syms, T_actual, surv);
    
    // Traceback
    uint8_t *decoded = (uint8_t*)calloc(N, 1);
    int nd;
    traceback_and_decode(surv, T_actual, D, decoded, &nd);
    
    printf("\nTotal decoded: %d bits\n", nd);
    
    // Compare with input
    printf("\nVerification (comparing with original input):\n");
    int errors = 0;
    for (int i = 0; i < nd && (N - 1 - i) >= 0; i++) {
        int input_idx = N - 1 - i;  // Reverse order
        if (decoded[i] != input_bits[input_idx]) {
            errors++;
            if (errors <= 10) {
                printf("  ERROR at decoded[%d]: got %d, expected input[%d]=%d\n", 
                       i, decoded[i], input_idx, input_bits[input_idx]);
            }
        }
    }
    
    if (errors == 0) {
        printf("  ✓ PERFECT DECODE - 0 errors!\n");
    } else {
        printf("  ✗ FAILED - %d errors / %d bits (%.1f%% accuracy)\n", 
               errors, nd, 100.0 * (nd - errors) / nd);
    }
    
    // Cleanup
    for (int t = 0; t < T_actual; t++) free(surv[t]);
    free(surv);
    free(syms);
    free(input_bits);
    free(decoded);
    
    return (errors == 0) ? 0 : 1;
}
