#include <stdio.h>
#define K 4
#define M 3
#define S 8
#define D 6
#define T 50

int main() {
    // Simple pattern for K=4: all states end up at state 0
    printf("For K=4, with simple test pattern, survivor memory:\n");
    printf("// All survivor bits will be 0 (always choose predecessor from lower half)\n");
    printf("Pattern for testbench: surv_row = 8'b00000000;\n");
    printf("Expected output: all zeros (since surv[t][0] = 0 for all t)\n");
    return 0;
}
