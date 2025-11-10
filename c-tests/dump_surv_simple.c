#include <stdio.h>
#include <stdint.h>
#include <limits.h>

#define K 3
#define M (K-1)
#define S (1<<M)
#define D 8
#define G0 07
#define G1 05

static inline uint8_t parity(uint32_t x) {
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

static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b) {
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity(reg & G0);
    uint8_t c1 = parity(reg & G1);
    return (uint8_t)((c0 << 1) | c1);
}

int main() {
    // Test pattern: 10101010 (bits 0-7)
    uint8_t test_bits[8] = {0, 1, 0, 1, 0, 1, 0, 1};  // LSB first to match indexing
    uint8_t symbols[20];
    int T = 0;
    uint32_t state = 0;
    
    printf("=== ENCODING ===\n");
    for (int i = 0; i < 8; i++) {
        uint8_t b = test_bits[i];
        symbols[T] = conv_sym_from_pred(state, b);
        printf("Bit %d: %d -> State %d -> Symbol %d%d\n", i, b, state, 
            (symbols[T] >> 1) & 1, symbols[T] & 1);
        state = ((state << 1) | b) & ((1u << M) - 1);
        T++;
    }
    
    // Tail bits
    for (int i = 0; i < M; i++) {
        symbols[T] = conv_sym_from_pred(state, 0);
        printf("Tail %d: 0 -> State %d -> Symbol %d%d\n", i, state, 
            (symbols[T] >> 1) & 1, symbols[T] & 1);
        state = (state << 1) & ((1u << M) - 1);
        T++;
    }
    
    // Viterbi forward pass
    printf("\n=== VITERBI FORWARD PASS ===\n");
    int pm_prev[S], pm_curr[S];
    uint8_t surv[20][S];  // [time][state]
    
    // Init: start in state 0
    for (int s = 0; s < S; s++) {
        pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;
    }
    
    for (int t = 0; t < T; t++) {
        uint8_t r = symbols[t];
        printf("T=%d: Symbol=%02b\n", t, r);
        
        for (int s_next = 0; s_next < S; s_next++) {
            uint32_t p0 = s_next >> 1;
            uint32_t p1 = (s_next >> 1) | (1u << (M - 1));
            uint8_t b_t = s_next & 1u;
            
            uint8_t e0 = conv_sym_from_pred(p0, b_t);
            uint8_t e1 = conv_sym_from_pred(p1, b_t);
            
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
            
            printf("  S%d: p0=%d (sym=%02b, bm=%d, pm=%d) p1=%d (sym=%02b, bm=%d, pm=%d) -> chose %d, surv=%d\n",
                s_next, p0, e0, bm0, m0, p1, e1, bm1, m1, (m1 < m0) ? p1 : p0, surv[t][s_next]);
        }
        
        // Swap
        for (int s = 0; s < S; s++) pm_prev[s] = pm_curr[s];
    }
    
    // Print survivor matrix
    printf("\n=== SURVIVOR MEMORY (should match Verilog dump) ===\n");
    for (int t = 0; t < T; t++) {
        printf("T=%d: S0=%d S1=%d S2=%d S3=%d\n", t,
            surv[t][0], surv[t][1], surv[t][2], surv[t][3]);
    }
    
    // Traceback
    printf("\n=== TRACEBACK ===\n");
    int s_best = 0;  // Force state 0
    int s = s_best;
    uint8_t decoded[10];
    int out_idx = 7;  // 8 bits - 1
    
    for (int t = T - 1; t >= 0 && out_idx >= 0; t--) {
        uint8_t take_p1 = surv[t][s];
        decoded[out_idx] = take_p1;
        printf("T=%d: s=%d, surv=%d -> bit=%d\n", t, s, take_p1, take_p1);
        
        if (take_p1)
            s = (s >> 1) | (1u << (M - 1));
        else
            s = (s >> 1);
        
        out_idx--;
    }
    
    printf("\n=== DECODED vs EXPECTED ===\n");
    for (int i = 0; i < 8; i++) {
        printf("Bit %d: decoded=%d expected=%d %s\n", 
            i, decoded[i], test_bits[i], 
            (decoded[i] == test_bits[i]) ? "✓" : "✗");
    }
    
    return 0;
}
