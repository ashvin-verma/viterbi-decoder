// Generate test vectors for traceback module verification
// Outputs: input bits, survivor memory, and expected decoded sequence

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define K 3
#define M (K-1)
#define S (1<<M)
#define D 6
#define N 48
#define T 50

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

void conv_encode(const uint8_t *in_bits, int n_bits, uint8_t *out_syms, int *T_out) {
    int m = M;
    uint32_t state = 0;
    int t = 0;
    for (int i = 0; i < n_bits; i++) {
        out_syms[t++] = conv_sym(state, in_bits[i], G0, G1);
        state = next_state(state, in_bits[i], m);
    }
    while (state != 0) {
        out_syms[t++] = conv_sym(state, 0, G0, G1);
        state = next_state(state, 0, m);
    }
    *T_out = t;
}

void viterbi_forward(const uint8_t *rx_syms, int t_syms, uint8_t **surv) {
    int m = M;
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    
    for (int s = 0; s < S; s++) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    
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
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;
    }
    
    free(pm_prev);
    free(pm_curr);
}

int main() {
    // Generate input sequence
    uint8_t *input_bits = (uint8_t*)calloc(N, 1);
    printf("// Test vector generation for traceback module\n");
    printf("// K=%d, M=%d, S=%d, D=%d, N=%d, T=%d\n\n", K, M, S, D, N, T);
    
    printf("// Input sequence (N=%d bits):\n", N);
    printf("reg [0:%d] input_bits = %d'b", N-1, N);
    for (int i = 0; i < N; i++) {
        input_bits[i] = (i % 3 == 1) ? 1 : 0;
        printf("%d", input_bits[i]);
    }
    printf(";\n\n");
    
    // Encode
    uint8_t *syms = (uint8_t*)calloc(T, 1);
    int T_actual;
    conv_encode(input_bits, N, syms, &T_actual);
    
    // Run Viterbi forward pass
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    for (int t = 0; t < T; t++) surv[t] = (uint8_t*)malloc(S);
    viterbi_forward(syms, T, surv);
    
    // Print survivor memory for testbench
    printf("// Survivor memory (T=%d times, S=%d states):\n", T, S);
    printf("// Format: mem[time][state]\n");
    printf("// For circular buffer of depth D=%d:\n\n", D);
    
    for (int t = 0; t < T; t++) {
        int idx = t % D;
        printf("// t=%2d (idx=%d): ", t, idx);
        for (int s = S-1; s >= 0; s--) {
            printf("%d", surv[t][s]);
        }
        printf("\n");
    }
    
    printf("\n// Survivor memory initialization for testbench:\n");
    printf("// (last D=%d time steps in circular buffer)\n", D);
    for (int t = T-D; t < T; t++) {
        int idx = t % D;
        printf("mem[%d] = 4'b", idx);
        for (int s = S-1; s >= 0; s--) {
            printf("%d", surv[t][s]);
        }
        printf("; // t=%d\n", t);
    }
    
    // Perform traceback
    printf("\n// TRACEBACK EXECUTION:\n");
    printf("// Starting from t=%d, s=0, going back D=%d steps\n\n", T-1, D);
    
    uint32_t s = 0;  // end state
    int m = M;
    uint8_t *decoded = (uint8_t*)calloc(N, 1);
    int nd = 0;
    
    for (int t = T - 1; t >= D; t--) {
        uint8_t surv_bit = surv[t][s];
        decoded[nd] = surv_bit;
        
        if (nd < 10 || nd >= N - D) {  // Print first 10 and last D
            printf("t=%2d s=%d surv=%d -> decoded[%2d]=%d", t, s, surv_bit, nd, surv_bit);
            
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
            printf("... (middle outputs omitted) ...\n");
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
    
    printf("\n// Total decoded: %d bits (expected %d)\n", nd, N - D + 1);
    
    // Print expected output sequence for testbench
    printf("\n// EXPECTED OUTPUT SEQUENCE (for testbench validation):\n");
    printf("// Outputs arrive in REVERSE time order (newest first)\n");
    printf("reg [0:%d] expected_output = %d'b", nd-1, nd);
    for (int i = 0; i < nd; i++) {
        printf("%d", decoded[i]);
    }
    printf(";\n");
    
    // Compare with input
    printf("\n// VERIFICATION:\n");
    printf("// Comparing decoded output with original input...\n");
    int errors = 0;
    for (int i = 0; i < nd && (N - 1 - i) >= 0; i++) {
        int input_idx = N - 1 - i;  // Reverse order
        if (decoded[i] != input_bits[input_idx]) {
            errors++;
            if (errors <= 5) {
                printf("ERROR at decoded[%d]: got %d, expected input[%d]=%d\n", 
                       i, decoded[i], input_idx, input_bits[input_idx]);
            }
        }
    }
    printf("Total errors: %d / %d (%.1f%% accuracy)\n", errors, nd, 100.0 * (nd - errors) / nd);
    
    // Cleanup
    for (int t = 0; t < T; t++) free(surv[t]);
    free(surv);
    free(syms);
    free(input_bits);
    free(decoded);
    
    return 0;
}
