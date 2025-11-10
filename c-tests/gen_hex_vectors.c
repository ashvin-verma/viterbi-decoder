// Generate binary test vectors for easy reading in Verilog
// Outputs: symbols.hex and expected.hex

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// Compile-time parameters
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

#ifndef NUM_FRAMES
#define NUM_FRAMES 10
#endif

#ifndef L_FRAME
#define L_FRAME 64  // Smaller for testing
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

void encoder_encode_bit(encoder_t *enc, uint8_t in_bit, uint8_t *y0, uint8_t *y1) {
    uint8_t sr = (enc->shift_reg << 1) | (in_bit & 1);
    
    *y0 = __builtin_popcount(sr & G0) & 1;
    *y1 = __builtin_popcount(sr & G1) & 1;
    
    enc->shift_reg = sr & ((1 << M) - 1);
}

int main(int argc, char **argv) {
    int seed = 42;
    
    if (argc > 1) {
        seed = atoi(argv[1]);
    }
    
    srand(seed);
    
    FILE *sym_file = fopen("symbols.hex", "w");
    FILE *exp_file = fopen("expected.hex", "w");
    
    if (!sym_file || !exp_file) {
        fprintf(stderr, "Error opening output files\n");
        return 1;
    }
    
    fprintf(sym_file, "// Encoded symbols (2 bits each, hex format)\n");
    fprintf(sym_file, "// K=%d, G0=%03o, G1=%03o, L=%d, D=%d\n", K, G0, G1, L_FRAME, D_TB);
    fprintf(sym_file, "// Each line: one frame of %d symbols (L + M tail bits)\n", L_FRAME + M);
    fprintf(sym_file, "//\n");
    
    fprintf(exp_file, "// Expected decoded bits (drop first D)\n");
    fprintf(exp_file, "// Each line: %d bits (L - D + M tail)\n", L_FRAME + M - D_TB);
    fprintf(exp_file, "//\n");
    
    for (int frame = 0; frame < NUM_FRAMES; frame++) {
        // Generate random info bits
        uint8_t info_bits[L_FRAME];
        for (int i = 0; i < L_FRAME; i++) {
            info_bits[i] = rand() & 1;
        }
        
        // Encode with tail
        encoder_t enc;
        encoder_init(&enc);
        
        for (int i = 0; i < L_FRAME; i++) {
            uint8_t y0, y1;
            encoder_encode_bit(&enc, info_bits[i], &y0, &y1);
            uint8_t sym = (y0 << 1) | y1;
            fprintf(sym_file, "%x", sym);
        }
        
        // Tail (M zeros)
        for (int i = 0; i < M; i++) {
            uint8_t y0, y1;
            encoder_encode_bit(&enc, 0, &y0, &y1);
            uint8_t sym = (y0 << 1) | y1;
            fprintf(sym_file, "%x", sym);
        }
        fprintf(sym_file, "\n");
        
        // Expected output (original bits + tail zeros, but drop first D)
        for (int i = D_TB; i < L_FRAME + M; i++) {
            if (i < L_FRAME) {
                fprintf(exp_file, "%d", info_bits[i]);
            } else {
                fprintf(exp_file, "0");  // Tail bits
            }
        }
        fprintf(exp_file, "\n");
    }
    
    fclose(sym_file);
    fclose(exp_file);
    
    printf("Generated:\n");
    printf("  symbols.hex - %d frames x %d symbols each\n", NUM_FRAMES, L_FRAME + M);
    printf("  expected.hex - %d frames x %d bits each\n", NUM_FRAMES, L_FRAME + M - D_TB);
    
    return 0;
}
