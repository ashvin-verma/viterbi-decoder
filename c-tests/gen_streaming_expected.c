// Generate expected output for STREAMING traceback mode
// In streaming mode: at each time t, do a D-step traceback and output the bit from time t

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define K 3
#define M (K-1)
#define S (1<<M)
#define D 6
#define N 48
#define T 50

int main() {
    // Generate survivor memory pattern: t%3==0 (t>=3) → 1111, else → 0000
    uint8_t surv[T][S];
    
    for (int t = 0; t < T; t++) {
        for (int s = 0; s < S; s++) {
            if (t >= 3 && t % 3 == 0) {
                surv[t][s] = 1;
            } else {
                surv[t][s] = 0;
            }
        }
    }
    
    printf("// Streaming traceback expected output\n");
    printf("// At each time t (from D-1 to T-1), do D-step traceback\n");
    printf("// Output is the survivor bit from the CURRENT time (first read)\n\n");
    
    // For each time from D-1 to T-1
    int output_idx = 0;
    printf("Expected outputs:\n");
    
    for (int t_start = D - 1; t_start < T; t_start++) {
        // Do D-step traceback starting from time t_start, state 0
        int t = t_start;
        uint32_t state = 0;
        
        // The decoded bit is from the FIRST read
        uint8_t decoded_bit = surv[t][state];
        
        printf("t=%2d: state=0, surv[%2d][0]=%d -> output[%2d]=%d\n",
               t_start, t, decoded_bit, output_idx, decoded_bit);
        
        // Continue traceback for D steps to update state
        for (int step = 0; step < D; step++) {
            uint8_t surv_bit = surv[t][state];
            
            // Update state
            if (surv_bit) {
                state = (state >> 1) | (1 << (M - 1));
            } else {
                state = state >> 1;
            }
            
            // Move to previous time (not used for output, just for state update)
            t = (t == 0) ? (T - 1) : (t - 1);  // This would wrap in real circular buffer
        }
        
        output_idx++;
    }
    
    // Generate the expected bit vector
    printf("\n// Expected output vector for testbench:\n");
    printf("reg [0:%d] expected_output = %d'b", T - D, T - D + 1);
    
    for (int t_start = D - 1; t_start < T; t_start++) {
        int t = t_start;
        uint32_t state = 0;
        uint8_t decoded_bit = surv[t][state];
        printf("%d", decoded_bit);
    }
    printf(";\n");
    
    return 0;
}
