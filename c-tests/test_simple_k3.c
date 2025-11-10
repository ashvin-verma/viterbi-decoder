#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#define K 3
#define D_TB 6
#define G0_OCT 0x07
#define G1_OCT 0x05

// From viterbi_golden.c
extern int viterbi_decode(const uint8_t *rx_syms, int T, uint8_t *out_bits);
extern void conv_encode(const uint8_t *in_bits, int N, uint8_t **syms_out, int *T_out, int force_tail);

int main() {
    // Test pattern: 1010110011111111000000
    uint8_t test_bits[] = {1,0,1,0,1,1,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0,0};
    int N = 16; // Just use first 16 bits
    
    // Encode
    uint8_t *syms = NULL;
    int T;
    conv_encode(test_bits, N, &syms, &T, 0); // free-running (force_tail=0)
    
    printf("Encoded %d bits into %d symbols\n", N, T);
    printf("Input bits:  ");
    for (int i = 0; i < N; i++) printf("%d", test_bits[i]);
    printf("\n");
    
    printf("Symbols: ");
    for (int i = 0; i < T; i++) {
        printf("%02x ", syms[i]);
    }
    printf("\n");
    
    // Decode
    uint8_t decoded[100];
    int n_decoded = viterbi_decode(syms, T, decoded);
    
    printf("Decoded %d bits\n", n_decoded);
    printf("Output bits: ");
    for (int i = 0; i < n_decoded; i++) printf("%d", decoded[i]);
    printf("\n");
    
    // Compare
    int errors = 0;
    int compare_len = (n_decoded < N) ? n_decoded : N;
    for (int i = 0; i < compare_len; i++) {
        if (test_bits[i] != decoded[i]) {
            printf("ERROR at bit %d: expected %d, got %d\n", i, test_bits[i], decoded[i]);
            errors++;
        }
    }
    printf("Errors: %d / %d\n", errors, compare_len);
    
    free(syms);
    return 0;
}
