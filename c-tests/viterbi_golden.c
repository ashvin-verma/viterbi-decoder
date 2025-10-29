#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#ifndef K
#define K 5           
#endif
    // constraint length

#ifndef D_TB
#define D_TB 32           
#endif
    // traceback depth

#ifndef G0_OCT
#define G0_OCT 023
#endif

#ifndef G1_OCT
#define G1_OCT 035
#endif

static inline uint8_t parity_u32(uint32_t x) {
    x ^= x >> 16; // xor-reduce to 16 bits
    x ^= x >> 8; // xor-reduce to 8 bits
    x ^= x >> 4; // xor-reduce to 4 bits
    x &= 0xFu; // keep only lower 4 bits
    return (uint8_t)((0x6996u >> x) & 1u); // lookup parity from precomputed LUT
}

static inline int ham2(uint8_t a, uint8_t b) {
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

static inline uint8_t encode_symbol(uint8_t state, uint8_t input_bit) {
    uint8_t shift_reg = (state << 1) | (input_bit & 0x1u);
    uint8_t out0 = parity_u32(shift_reg & G0_OCT);
    uint8_t out1 = parity_u32(shift_reg & G1_OCT);
    return (out0 << 1) | out1;
}

static uint32_t oct_to_mask(int oct, int Kbits) {
    uint32_t mask = 0;
    int v = oct;
    int bitpos = 0;
    while (v > 0) {
        int tri = v & 7; // select lowest 3 bits
        for (int i = 0; i < 3; ++i) {
            if (tri & (1 << i)) {
                int pos = bitpos + i;
                if (pos < Kbits) mask |= (1u << pos);
            }
        }
        v >>= 3;
        bitpos += 3;
    }
    return mask;
}

static inline uint32_t next_state(uint32_t curr_state, uint8_t input_bit, int mem_bits) { 
    return (curr_state >> 1) | ((input_bit & 0x1u) << (mem_bits - 1));
}


