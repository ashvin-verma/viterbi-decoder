// Dump survivor memory using TESTBENCH state convention (MSB=newest input bit)
// This allows direct use in the testbench

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define K 3
#define G0 05  // octal
#define G1 07  // octal

static inline int parity_u32(uint32_t x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    x ^= x >> 2;
    x ^= x >> 1;
    return (int)(x & 1u);
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t diff = (a ^ b) & 0x3u;
    return parity_u32(diff & 1u) + parity_u32(diff & 2u);
}

// TESTBENCH convention: MSB = newest input bit
// next_state = (state >> 1); next_state[MSB] = input_bit
// So for m=2: state = [bit_{t-1}, bit_t] where bit_t is at MSB
// Predecessor calculation:
// If next_state = [b_{t}, b_{t+1}], then:
//   p0 had MSB=0, so p0 = [0, b_t]
//   p1 had MSB=1, so p1 = [1, b_t]

static inline uint8_t conv_sym_tb(uint32_t state, uint32_t input_bit, uint32_t g0, uint32_t g1, int m) {
    // State bits: [bit_{t-m+1}, ..., bit_{t-1}, bit_t] with bit_t at MSB
    // For K=3, m=2: state = [bit_{t-1}, bit_t]
    // Shift register for encoder: [bit_t, bit_{t-1}] with bit_t at LSB (position 0)
    // So: reg[0] = state[MSB], reg[1] = state[MSB-1]
    
    // Next input goes to position 0
    uint32_t reg = input_bit & 1u;
    for (int i = 0; i < m; i++) {
        int bit = (state >> (m - 1 - i)) & 1u;
        reg |= bit << (i + 1);
    }
    
    uint8_t c0 = parity_u32(reg & g0);
    uint8_t c1 = parity_u32(reg & g1);
    return (uint8_t)((c0 << 1) | c1);
}

int main() {
    int m = K - 1;
    int S = 1 << m;
    int T = 50;
    int N = 48;
    
    printf("// Testbench convention: MSB = newest input bit\n");
    printf("// K=%d, m=%d, S=%d, T=%d, N=%d\n", K, m, S, T, N);
    printf("// Input pattern: bit_hist[t] = (t %% 3 == 1)\n\n");
    
    // Generate input sequence
    uint8_t *input_bits = (uint8_t*)calloc(N, 1);
    for (int i = 0; i < N; i++) {
        input_bits[i] = (i % 3 == 1) ? 1 : 0;
    }
    
    // Encode (testbench convention)
    uint8_t *syms = (uint8_t*)calloc(T, 1);
    uint32_t state = 0;  // start in all-zeros state
    for (int t = 0; t < T; t++) {
        uint8_t input_bit;
        if (t < N) {
            input_bit = input_bits[t];
        } else {
            // Tail bits to return to state 0
            // With MSB=newest: state = [bit_{t-1}, bit_t]
            // To go to 0, need input_bit such that next_state[MSB] = 0
            // Since next_state = (state >> 1) with MSB set to input_bit
            // We want MSB = 0, so input_bit = 0
            input_bit = 0;
        }
        
        syms[t] = conv_sym_tb(state, input_bit, G0, G1, m);
        
        // Update state: shift right, set MSB to new input
        uint32_t next_state = state >> 1;
        if (input_bit) {
            next_state |= (1u << (m - 1));
        }
        state = next_state;
    }
    
    // Viterbi forward pass
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    for (int t = 0; t < T; t++) {
        surv[t] = (uint8_t*)malloc(S);
    }
    
    // Init metrics
    for (int s = 0; s < S; s++) {
        pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    }
    
    // Forward pass
    for (int t = 0; t < T; t++) {
        uint8_t r = syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; s_next++) {
            // Predecessors in testbench convention
            // s_next = (p >> 1) with MSB set to some bit
            // So p[MSB] = s_next[MSB-1] for p0 (input_bit=0)
            // and p[MSB] = 1 for p1 (input_bit=1)
            // Actually, simpler: the input bit that led to s_next is s_next[MSB]
            // p0: had input_bit=0, so p0 = (s_next << 1) & mask, then clear bit 0
            // p1: had input_bit=1, so p1 = (s_next << 1) | 1, & mask
            
            uint32_t mask = (1u << m) - 1u;
            uint8_t b_t = (s_next >> (m - 1)) & 1u;  // MSB of s_next
            uint32_t p0 = ((s_next << 1) | 0) & mask;
            uint32_t p1 = ((s_next << 1) | 1) & mask;
            
            uint8_t e0 = conv_sym_tb(p0, b_t, G0, G1, m);
            uint8_t e1 = conv_sym_tb(p1, b_t, G0, G1, m);
            
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
        
        int *tmp = pm_prev;
        pm_prev = pm_curr;
        pm_curr = tmp;
    }
    
    // Dump survivor memory
    printf("Survivor memory dump:\n");
    for (int t = 0; t < T; t++) {
        printf("t=%2d: ", t);
        for (int s = S - 1; s >= 0; s--) {
            printf("%d", surv[t][s]);
        }
        printf("\n");
    }
    
    // Cleanup
    for (int t = 0; t < T; t++) free(surv[t]);
    free(surv);
    free(pm_prev);
    free(pm_curr);
    free(syms);
    free(input_bits);
    
    return 0;
}
