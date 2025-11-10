// Generate test vectors for Viterbi decoder testbench
// Outputs: input bits, encoded symbols, expected decoded bits

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// Compile-time parameters (override with -D flags)
#ifndef K
#define K 3
#endif

#ifndef G0_OCT
#define G0_OCT 07
#endif

#ifndef G1_OCT
#define G1_OCT 05
#endif

#ifndef D_TB
#define D_TB 6
#endif

#ifndef L_FRAME
#define L_FRAME 256
#endif

#define M (K-1)
#define S (1<<M)
#define G0 G0_OCT
#define G1 G1_OCT

// Encoder
typedef struct {
    uint8_t shift_reg;
} encoder_t;

void encoder_init(encoder_t *enc) {
    enc->shift_reg = 0;
}

void encoder_encode_bit(encoder_t *enc, uint8_t bit, uint8_t *y0, uint8_t *y1) {
    uint8_t sr = (enc->shift_reg << 1) | (bit & 1);
    
    *y0 = __builtin_popcount(sr & G0) & 1;
    *y1 = __builtin_popcount(sr & G1) & 1;
    
    enc->shift_reg = sr & ((1 << M) - 1);
}

// Simple Viterbi decoder (using same code as golden model)
typedef struct {
    int pm[2][S];  // Path metrics [bank][state]
    uint8_t surv[D_TB][S];  // Survivor memory
    int wr_ptr;
    int bank_sel;
} decoder_t;

void decoder_init(decoder_t *dec) {
    memset(dec->pm, 0, sizeof(dec->pm));
    memset(dec->surv, 0, sizeof(dec->surv));
    
    // Initialize with large values except state 0
    for (int s = 1; s < S; s++) {
        dec->pm[0][s] = 1000000;
        dec->pm[1][s] = 1000000;
    }
    dec->pm[0][0] = 0;
    dec->pm[1][0] = 0;
    
    dec->wr_ptr = 0;
    dec->bank_sel = 0;
}

void decoder_process_symbol(decoder_t *dec, uint8_t y0, uint8_t y1) {
    int prev_bank = dec->bank_sel;
    int curr_bank = 1 - prev_bank;
    
    // ACS for all states
    for (int s = 0; s < S; s++) {
        // Two parent states
        int p0 = s >> 1;
        int p1 = p0 | (1 << (M-1));
        
        // Expected outputs for each parent
        uint8_t e0_0 = __builtin_popcount(p0 & G0) & 1;
        uint8_t e0_1 = __builtin_popcount(p0 & G1) & 1;
        uint8_t e1_0 = __builtin_popcount(p1 & G0) & 1;
        uint8_t e1_1 = __builtin_popcount(p1 & G1) & 1;
        
        // Branch metrics (Hamming distance)
        int bm0 = (e0_0 != y0) + (e0_1 != y1);
        int bm1 = (e1_0 != y0) + (e1_1 != y1);
        
        // Path metrics
        int pm0 = dec->pm[prev_bank][p0] + bm0;
        int pm1 = dec->pm[prev_bank][p1] + bm1;
        
        // Select survivor
        if (pm0 <= pm1) {
            dec->pm[curr_bank][s] = pm0;
            dec->surv[dec->wr_ptr][s] = 0;
        } else {
            dec->pm[curr_bank][s] = pm1;
            dec->surv[dec->wr_ptr][s] = 1;
        }
    }
    
    dec->bank_sel = curr_bank;
    dec->wr_ptr = (dec->wr_ptr + 1) % D_TB;
}

uint8_t decoder_traceback(decoder_t *dec, uint8_t end_state) {
    int state = end_state;
    int t = (dec->wr_ptr == 0) ? (D_TB - 1) : (dec->wr_ptr - 1);
    
    // Traceback D steps
    for (int step = 0; step < D_TB; step++) {
        uint8_t surv_bit = dec->surv[t][state];
        int parent = state >> 1;
        if (surv_bit) {
            parent |= (1 << (M-1));
        }
        
        if (step == D_TB - 1) {
            // At the end, extract the information bit
            return state & 1;
        }
        
        state = parent;
        t = (t == 0) ? (D_TB - 1) : (t - 1);
    }
    
    return 0;  // Should not reach here
}

int main(int argc, char **argv) {
    int num_frames = 10;
    int seed = 42;
    
    if (argc > 1) {
        num_frames = atoi(argv[1]);
    }
    if (argc > 2) {
        seed = atoi(argv[2]);
    }
    
    srand(seed);
    
    printf("# Viterbi Test Vectors\n");
    printf("# K=%d, M=%d, S=%d, D=%d\n", K, M, S, D_TB);
    printf("# G0=%03o, G1=%03o (octal)\n", G0, G1);
    printf("# Frame length: %d bits\n", L_FRAME);
    printf("# Number of frames: %d\n", num_frames);
    printf("#\n");
    printf("# Format per frame:\n");
    printf("# FRAME <frame_num>\n");
    printf("# INFO_BITS <hex>\n");
    printf("# SYMBOLS <hex pairs>\n");
    printf("# EXPECTED <hex> (after dropping first D bits)\n");
    printf("#\n");
    
    for (int frame = 0; frame < num_frames; frame++) {
        // Generate random info bits
        uint8_t info_bits[L_FRAME];
        for (int i = 0; i < L_FRAME; i++) {
            info_bits[i] = rand() & 1;
        }
        
        // Encode with tail
        encoder_t enc;
        encoder_init(&enc);
        
        uint8_t symbols[2][L_FRAME + M];
        for (int i = 0; i < L_FRAME; i++) {
            encoder_encode_bit(&enc, info_bits[i], &symbols[0][i], &symbols[1][i]);
        }
        
        // Tail (M zeros to force state 0)
        for (int i = 0; i < M; i++) {
            encoder_encode_bit(&enc, 0, &symbols[0][L_FRAME + i], &symbols[1][L_FRAME + i]);
        }
        
        // Decode
        decoder_t dec;
        decoder_init(&dec);
        
        uint8_t decoded[L_FRAME + M];
        int num_syms = L_FRAME + M;
        
        for (int i = 0; i < num_syms; i++) {
            decoder_process_symbol(&dec, symbols[0][i], symbols[1][i]);
            
            // Traceback after each symbol (streaming mode)
            if (i >= D_TB - 1) {
                uint8_t end_state = 0;  // Force state 0 for tail-terminated
                decoded[i - (D_TB - 1)] = decoder_traceback(&dec, end_state);
            }
        }
        
        printf("FRAME %d\n", frame);
        
        // Print info bits in hex
        printf("INFO_BITS ");
        for (int i = 0; i < L_FRAME; i += 8) {
            uint8_t byte = 0;
            for (int b = 0; b < 8 && (i + b) < L_FRAME; b++) {
                byte |= (info_bits[i + b] << b);
            }
            printf("%02x", byte);
        }
        printf("\n");
        
        // Print encoded symbols as hex pairs (y0,y1)
        printf("SYMBOLS ");
        for (int i = 0; i < num_syms; i++) {
            uint8_t sym = (symbols[0][i] << 1) | symbols[1][i];
            printf("%x", sym);
        }
        printf("\n");
        
        // Print expected decoded bits (drop first D)
        printf("EXPECTED ");
        int num_decoded = num_syms - (D_TB - 1);
        for (int i = D_TB; i < num_decoded; i++) {  // Drop first D bits
            if (i % 8 == 0 && i > D_TB) printf(" ");
            printf("%d", decoded[i]);
        }
        printf("\n");
        
        printf("\n");
    }
    
    return 0;
}
