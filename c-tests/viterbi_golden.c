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

static inline uint8_t parity_u32(uint32_t x) { // -> collapses to ^x in rtl
    x ^= x >> 16; // xor-reduce to 16 bits
    x ^= x >> 8; // xor-reduce to 8 bits
    x ^= x >> 4; // xor-reduce to 4 bits
    x &= 0xFu; // keep only lower 4 bits 
    return (uint8_t)((0x6996u >> x) & 1u); // lookup parity from precomputed LUT
}

static inline int ham2(uint8_t a, uint8_t b) { // ham2.v
    uint8_t x = (a ^ b) & 0x3u;
    return (x & 1u) + ((x >> 1) & 1u);
}

// 1) next_state: LSB insertion (new bit into LSB, shift left)
// LSB insertion (new bit at LSB)
static inline uint32_t next_state(uint32_t curr_state, uint8_t b, int m){
    uint32_t mask = (1u << m) - 1u;
    return ((curr_state << 1) | (b & 1u)) & mask;
}


static inline uint8_t conv_sym_from_pred(uint32_t p, uint32_t b,
                                         uint32_t g0, uint32_t g1){
    // Register: bit 0 = newest input b, bits [K-1:1] = shifted predecessor state
    // Direct octal polynomial: tap i -> bit i (bit 0 = current input tap)
    uint32_t reg = (b & 1u) | (p << 1);
    uint8_t c0 = parity_u32(reg & g0);
    uint8_t c1 = parity_u32(reg & g1);
    return (uint8_t)((c0 << 1) | c1);
}


void conv_encode(const uint8_t *in_bits, int N, uint8_t *out_syms, int *T_out) {
    const int m = K - 1;
    const uint32_t g0 = G0_OCT;  // Direct octal
    const uint32_t g1 = G1_OCT;
    uint32_t state = 0; // holds previous m bits

    int t = 0;
    for (int i = 0; i < N; ++i) {
        uint32_t b = in_bits[i] & 1u;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    // Tail: append m zeros to force state->0
    for (int i = 0; i < m; ++i) {
        uint32_t b = 0;
        out_syms[t++] = conv_sym_from_pred(state, b, g0, g1);
        state = next_state(state, b, m);
    }
    *T_out = t;
}

// Hard-decision Viterbi (traceback). rx_syms length T (2-bit symbols). Returns number of decoded bits (N=T-m).
int viterbi_decode(const uint8_t *rx_syms, int T, uint8_t *out_bits) {
    const int m = K - 1;
    const int S = 1 << m; // states
    const uint32_t g0 = G0_OCT;  // Direct octal
    const uint32_t g1 = G1_OCT;

    // Path metrics
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    if (!pm_prev || !pm_curr) { fprintf(stderr, "OOM pm\n"); exit(1); }

    // Survivor bits: store winner (0: pred=p0, 1: pred=p1) for each (t, state)
    // Simple byte storage for clarity; bit-pack later if you need speed.
    uint8_t **surv = (uint8_t**)malloc(T * sizeof(uint8_t*));
    if (!surv) { fprintf(stderr, "OOM surv\n"); exit(1); }
    for (int t = 0; t < T; ++t) {
        surv[t] = (uint8_t*)malloc(S);
        if (!surv[t]) { fprintf(stderr, "OOM surv row\n"); exit(1); }
    }

    // Init metrics (start in state 0)
    for (int s = 0; s < S; ++s) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    // forward pass
    for (int t = 0; t < T; ++t) {
        uint8_t r = rx_syms[t] & 0x3u;
        for (int s_next = 0; s_next < S; ++s_next) {

            uint32_t p0 = (uint32_t)(s_next >> 1);
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m - 1)));

            uint8_t b_t = (uint8_t)(s_next & 1u);  // <-- input bit that leads into s_next

            uint8_t e0 = conv_sym_from_pred(p0, b_t, g0, g1);
            uint8_t e1 = conv_sym_from_pred(p1, b_t, g0, g1);

            int bm0 = ham2(r, e0);
            int bm1 = ham2(r, e1);

            int m0 = pm_prev[p0] + bm0;
            int m1 = pm_prev[p1] + bm1;

            if (m1 < m0) {
                pm_curr[s_next] = m1;
                surv[t][s_next] = 1;   // chose predecessor p1
            } else {
                pm_curr[s_next] = m0;
                surv[t][s_next] = 0;   // chose predecessor p0
            }
        }
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;
    }

    // Choose end state: if tail-terminated, best is state 0; otherwise pick argmin
    int s_best = 0;
    int bestm = pm_prev[0];
    for (int s = 1; s < S; ++s) {
        if (pm_prev[s] < bestm) { bestm = pm_prev[s]; s_best = s; }
    }

    // Traceback
    // The input length N = T - m (tail bits), output out_bits[0..N-1]
    int N = T - m;
    int t = T - 1;
    int out_idx = N - 1;
    int s = s_best;

    while (t >= 0) {
        uint8_t take_p1 = surv[t][s]; // survivor decision doubles as the decoded input bit
        if (out_idx >= 0) out_bits[out_idx--] = take_p1;

        if (take_p1)
            s = (s >> 1) | (1u << (m - 1));  // chose predecessor p1
        else
            s = (s >> 1);                    // chose predecessor p0

        --t;
    }


    // Cleanup
    for (int i = 0; i < T; ++i) free(surv[i]);
    free(surv);
    free(pm_prev);
    free(pm_curr);
    return N;
}

// Streaming hard-decision Viterbi matching RTL schedule (one output per symbol)
// Emits the last survivor bit after a D-step traceback starting at time=wr_ptr-1.
// Returns T outputs in out_bits[t], where out_bits[t] corresponds to trellis bit at (t-(D-1)).
int viterbi_decode_streaming(const uint8_t *rx_syms, int T, int D, uint8_t *out_bits, int force_state0) {
    const int m = K - 1;
    const int S = 1 << m;
    const uint32_t g0 = G0_OCT;
    const uint32_t g1 = G1_OCT;

    // Path metrics
    int *pm_prev = (int*)malloc(S * sizeof(int));
    int *pm_curr = (int*)malloc(S * sizeof(int));
    if (!pm_prev || !pm_curr) { fprintf(stderr, "OOM pm\n"); exit(1); }

    // Survivor memory: D x S ring buffer
    uint8_t *mem = (uint8_t*)malloc(D * S);
    if (!mem) { fprintf(stderr, "OOM mem\n"); exit(1); }
    memset(mem, 0, D * S);
    int wr_ptr = 0;

    // Init metrics (start in state 0)
    for (int s = 0; s < S; ++s) pm_prev[s] = (s == 0) ? 0 : INT_MAX / 4;

    for (int t = 0; t < T; ++t) {
        uint8_t r = rx_syms[t] & 0x3u;

        int bestm = INT_MAX/4;
        int bests = 0;

        // Sweep s_next = 0..S-1
        for (int s_next = 0; s_next < S; ++s_next) {
            uint32_t p0 = (uint32_t)(s_next >> 1);
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m - 1)));
            uint8_t  b_t = (uint8_t)(s_next & 1u);

            uint8_t e0 = conv_sym_from_pred(p0, b_t, g0, g1);
            uint8_t e1 = conv_sym_from_pred(p1, b_t, g0, g1);
            int bm0 = ham2(r, e0);
            int bm1 = ham2(r, e1);

            int m0 = pm_prev[p0] + bm0;
            int m1 = pm_prev[p1] + bm1;

            // Tie-break: p0 wins on ties
            int choose_p1 = (m1 < m0);
            int pm_out = choose_p1 ? m1 : m0;

            // Store survivor bit for this destination state
            mem[wr_ptr * S + s_next] = (uint8_t)choose_p1;

            // Track argmin over pm_out
            if (pm_out < bestm) { bestm = pm_out; bests = s_next; }

            pm_curr[s_next] = pm_out;
        }

        // Swap PM banks
        int *tmp = pm_prev; pm_prev = pm_curr; pm_curr = tmp;

        // Advance survivor write pointer
        wr_ptr = (wr_ptr + 1) % D;

        // Traceback burst (D steps), starting from time=wr_ptr-1 and best state
        int time_idx = (wr_ptr == 0) ? (D - 1) : (wr_ptr - 1);
        int state    = force_state0 ? 0 : bests;
        uint8_t last_bit = 0;

        for (int k = 0; k < D; ++k) {
            uint8_t bit = mem[time_idx * S + state]; // b[time_idx] that led into 'state'
            last_bit = bit;

            if (bit)
                state = (state >> 1) | (1u << (m - 1));
            else
                state = (state >> 1);

            time_idx = (time_idx == 0) ? (D - 1) : (time_idx - 1);
        }

        out_bits[t] = last_bit;
    }

    free(mem);
    free(pm_prev);
    free(pm_curr);
    return T;
}

// #define TEST_MAIN

void bsc_hard(uint8_t *syms, int T, double p) {
    for (int t = 0; t < T; ++t) {
        uint8_t s = syms[t] & 3u;
        if ((double)rand()/RAND_MAX < p) s ^= 1u;           // flip LSB
        if ((double)rand()/RAND_MAX < p) s ^= 2u;           // flip MSB
        syms[t] = s;
    }
}

static void hard_quantize_bpsk(const double *y0, const double *y1, int T, uint8_t *syms_out) {
    for (int t = 0; t < T; ++t) {
        uint8_t b0 = (y0[t] < 0.0) ? 1u : 0u;         // 0 -> +1, 1 -> -1 mapping; threshold at 0
        uint8_t b1 = (y1[t] < 0.0) ? 1u : 0u;
        syms_out[t] = (uint8_t)((b0 << 1) | b1);      // keep (c0<<1)|c1 packing used by conv_sym_from_pred
    }
}

static void print_hdr(const char *label) {
    printf("[%s] K=%d  D_TB=%d  G0=%o  G1=%o\n", label, K, D_TB, G0_OCT, G1_OCT);
}

static void run_case(const char *label,
                     const uint8_t *u, int N,
                     const uint8_t *syms_tx, int T,
                     uint8_t *rx_syms)
{
    // Decode
    uint8_t *u_hat = (uint8_t*)malloc(N);
    int Nd = viterbi_decode(rx_syms, T, u_hat);

    // Compare (ignore any mismatch in Nd vs N due to tails; model returns N=T-(K-1))
    int L = (Nd < N) ? Nd : N;
    int err = 0;
    for (int i = 0; i < L; ++i) if ((u[i] & 1) != (u_hat[i] & 1)) ++err;

    // Report
    print_hdr(label);
    printf("  frame: N=%d info bits, T=%d symbols  -> decoded=%d bits\n", N, T, Nd);
    printf("  errors=%d  BER=%.6g\n\n", err, (L>0) ? (double)err / (double)L : 0.0);

    free(u_hat);
}


typedef struct { int state; double pg2b, pb2g; double p_good, p_bad; } GE;
void ge_init(GE* ch, double pg2b, double pb2g, double p_good, double p_bad){ ch->state=0; ch->pg2b=pg2b; ch->pb2g=pb2g; ch->p_good=p_good; ch->p_bad=p_bad; }
static inline int ge_step(GE* c){ double r=(double)rand()/RAND_MAX; if(c->state==0 && r<c->pg2b) c->state=1; else if(c->state==1 && r<c->pb2g) c->state=0; return c->state; }
void gilbert_elliott(uint8_t *syms, int T, GE *ch){
    for(int t=0;t<T;++t){ int bad=ge_step(ch); double p = bad ? ch->p_bad : ch->p_good;
        uint8_t s=syms[t]&3u; if(((double)rand()/RAND_MAX)<p) s^=1u; if(((double)rand()/RAND_MAX)<p) s^=2u; syms[t]=s; }
}

#include <math.h>
// Box–Muller Gaussian
static inline double gauss() { double u= (rand()+1.0)/(RAND_MAX+2.0); double v=(rand()+1.0)/(RAND_MAX+2.0); return sqrt(-2.0*log(u))*cos(2*M_PI*v); }

// BPSK + AWGN: return noisy samples y0,y1 for each symbol
void awgn_bpsk(const uint8_t *syms_in, int T, double EbN0_dB, double rate, double *y0, double *y1){
    double EbN0 = pow(10.0, EbN0_dB/10.0);
    double N0 = 1.0 / EbN0;           // with unit-energy bits; rate scales Eb
    N0 /= rate;                        // rate-1/2: energy per coded bit halves
    double sigma = sqrt(N0/2.0);
    for(int t=0;t<T;++t){
        uint8_t s = syms_in[t] & 3u;
        int b0 = (s>>1)&1, b1 = s&1;
        double x0 = b0? -1.0 : +1.0;
        double x1 = b1? -1.0 : +1.0;
        y0[t] = x0 + sigma*gauss();
        y1[t] = x1 + sigma*gauss();
    }
}

void two_tap_isi_bpsk(const uint8_t *syms, int T, double alpha, double EbN0_dB, double rate, double *y0, double *y1){
    double EbN0 = pow(10.0, EbN0_dB/10.0); double N0 = 1.0/EbN0; N0/=rate; double sigma=sqrt(N0/2.0);
    double prev0=0.0, prev1=0.0;
    for(int t=0;t<T;++t){
        uint8_t s=syms[t]&3u; int b0=(s>>1)&1, b1=s&1;
        double x0 = b0? -1.0:+1.0, x1 = b1? -1.0:+1.0;
        y0[t] = (x0 + alpha*prev0) + sigma*gauss();
        y1[t] = (x1 + alpha*prev1) + sigma*gauss();
        prev0 = x0; prev1 = x1;
    }
}


#ifdef TEST_MAIN
// Quick sanity: random roundtrip
int main(void) {
    // Fixed seed for reproducibility; change if you want varied runs
    srand(12345);

    // ---- Build a random info frame and encode (tail-terminated) ----
    const int N = 2000;                            // info bits (adjust as you like)
    uint8_t *u = (uint8_t*)malloc(N);
    for (int i = 0; i < N; ++i) u[i] = rand() & 1;

    int T = N + (K - 1);                           // symbols incl. tail
    uint8_t *syms_tx = (uint8_t*)malloc(T);
    conv_encode(u, N, syms_tx, &T);                // fills syms_tx[0..T-1]

    uint8_t *rx_syms = (uint8_t*)malloc(T);

    // ---- Noiseless sanity check ----
    memcpy(rx_syms, syms_tx, T);                 // exactly what the encoder produced
    run_case("Noiseless", u, N, syms_tx, T, rx_syms);


    // ===============================================================
    // 1) BSC — i.i.d. flips on coded bits (hard-decision channel)
    // ===============================================================
    memcpy(rx_syms, syms_tx, T);
    const double p_bit = 0.1;                     // 3% per coded-bit flip
    bsc_hard(rx_syms, T, p_bit);
    run_case("BSC", u, N, syms_tx, T, rx_syms);

    // ===============================================================
    // 2) Gilbert–Elliott — bursty channel (hard-decision)
    //    Good->Bad prob pg2b, Bad->Good prob pb2g; error probs p_good, p_bad
    // ===============================================================
    memcpy(rx_syms, syms_tx, T);
    GE ch; ge_init(&ch,
                   0.002,   // pg2b: enter bad state
                   0.2,     // pb2g: leave bad state
                   0.002,   // p_good: low error in good state
                   0.15);   // p_bad: high error in bad state
    gilbert_elliott(rx_syms, T, &ch);
    run_case("Gilbert-Elliott", u, N, syms_tx, T, rx_syms);

    // ===============================================================
    // 3) AWGN (hard quantized) — BPSK map, add Gaussian noise, threshold back to bits
    //    Note: hard decisions lose ~2 dB vs soft, but preserves your hard-decision decoder
    // ===============================================================
    {
        memcpy(rx_syms, syms_tx, T);               // just for consistent baseline (we overwrite below)
        double *y0 = (double*)malloc(sizeof(double)*T);
        double *y1 = (double*)malloc(sizeof(double)*T);
        const double EbN0_dB = 3.0;                // try 0..6 dB
        const double rate = 0.5;                   // r=1/2 code
        awgn_bpsk(syms_tx, T, EbN0_dB, rate, y0, y1);
        hard_quantize_bpsk(y0, y1, T, rx_syms);
        free(y0); free(y1);
        run_case("AWGN (hard)", u, N, syms_tx, T, rx_syms);
    }

    // ===============================================================
    // 4) Two-tap ISI + AWGN (hard quantized) — simple multipath stress test
    //    Your decoder doesn’t equalize ISI; expect higher BER (illustrative)
    // ===============================================================
    {
        memcpy(rx_syms, syms_tx, T);
        double *y0 = (double*)malloc(sizeof(double)*T);
        double *y1 = (double*)malloc(sizeof(double)*T);
        const double alpha = 0.4;                  // postcursor tap (try 0.2..0.6)
        const double EbN0_dB = 5.0;                // a bit higher SNR to compensate ISI
        const double rate = 0.5;
        two_tap_isi_bpsk(syms_tx, T, alpha, EbN0_dB, rate, y0, y1);
        hard_quantize_bpsk(y0, y1, T, rx_syms);
        free(y0); free(y1);
        run_case("ISI(2-tap)+AWGN (hard)", u, N, syms_tx, T, rx_syms);
    }

    free(rx_syms);
    free(syms_tx);
    free(u);
    return 0;
}
#endif

#ifdef TEST_DEBUG

static void print_bits(const char* tag, const uint8_t* b, int n){
    printf("%s:", tag);
    for(int i=0;i<n;i++) printf("%d", b[i]&1);
    printf("\n");
}

int main(void){
    srand(1);

    const int m = K-1;
    const int S = 1<<m;

    // Tiny known pattern (edit freely)
    const int N = 8;
    uint8_t u[N] = {1,0,1,1,0,0,1,0};

    // Encode with tails
    int T = N + m;
    uint8_t *syms = (uint8_t*)malloc(T);
    conv_encode(u, N, syms, &T);

    // Show encoded 2-bit symbols
    printf("K=%d (m=%d)  G=(%o,%o)  T=%d\n", K, m, G0_OCT, G1_OCT, T);
    printf("Encoded syms (c0c1 as two bits):\n");
    for(int t=0;t<T;t++){ printf("%d%d ", (syms[t]>>1)&1, syms[t]&1); } printf("\n\n");

    // Build masks (direct octal notation)
    uint32_t g0 = G0_OCT;
    uint32_t g1 = G1_OCT;

    // Path metrics + survivor bytes (debug only)
    int pm_prev[S], pm_curr[S];
    uint8_t **surv = (uint8_t**)malloc(T*sizeof(uint8_t*));
    for(int t=0;t<T;t++) surv[t] = (uint8_t*)malloc(S);

    for(int s=0;s<S;s++) pm_prev[s] = (s==0)?0:INT_MAX/4;

    // Step through trellis
    for(int t=0;t<T;t++){
        uint8_t r = syms[t] & 3u;
        printf("t=%d  rx=%d%d\n", t, (r>>1)&1, r&1);
        for(int s_next=0; s_next<S; s_next++){
            uint32_t p0 = (uint32_t)(s_next >> 1);
            uint32_t p1 = (uint32_t)((s_next >> 1) | (1u << (m-1)));

            uint8_t b_t = (uint8_t)(s_next & 1u);
            uint8_t e0 = conv_sym_from_pred(p0, b_t, g0, g1);
            uint8_t e1 = conv_sym_from_pred(p1, b_t, g0, g1);

            int bm0 = ham2(r, e0);
            int bm1 = ham2(r, e1);

            int m0 = pm_prev[p0] + bm0;
            int m1 = pm_prev[p1] + bm1;

            int win_b = (m1 < m0); // 1 picks p1, 0 picks p0
            pm_curr[s_next] = win_b ? m1 : m0;
            surv[t][s_next] = (uint8_t)win_b;

            printf("  s_next=%d  p0=%d e0=%d%d bm0=%d | p1=%d e1=%d%d bm1=%d  => win b=%d pm=%d\n",
                s_next, p0, (e0>>1)&1, e0&1, bm0,
                p1, (e1>>1)&1, e1&1, bm1, win_b, pm_curr[s_next]);
        }
        // swap
        for(int s=0;s<S;s++) pm_prev[s] = pm_curr[s];
        // show pm vector
        printf("  pm after t=%d: ", t);
        for(int s=0;s<S;s++) printf("%d ", pm_prev[s]); printf("\n\n");
    }

    // Choose best end state and traceback
    int s_best = 0, bestm = pm_prev[0];
    for(int s=1;s<S;s++) if(pm_prev[s] < bestm){ bestm = pm_prev[s]; s_best = s; }
    printf("End: s_best=%d  metric=%d\n", s_best, bestm);

    uint8_t *u_hat = (uint8_t*)malloc(N);
    int t=T-1, idx=N-1, s=s_best;
    while(t>=0){
        uint8_t b = surv[t][s];
        if(idx>=0) u_hat[idx--] = b;
        if(b==0) s = s >> 1;
        else     s = (s >> 1) | (1u << (m-1));
        t--;
    }
    print_bits("u_true ", u, N);
    print_bits("u_hat  ", u_hat, N);

    // cleanup
    for(int tt=0; tt<T; ++tt) free(surv[tt]);
    free(surv); free(u_hat); free(syms);
    return 0;
}
#endif

#ifdef TEST_VECTORS
// Generate test vectors for expected_bits module
int main(void) {
    const int m = K - 1;
    const int S = 1 << m;
    const uint32_t g0 = G0_OCT;
    const uint32_t g1 = G1_OCT;
    
    // Generate test vectors: pred b expected
    for (uint32_t p = 0; p < S; p++) {
        for (uint32_t b = 0; b <= 1; b++) {
            uint8_t expected = conv_sym_from_pred(p, b, g0, g1);
            printf("%X %d %X\n", p, b, expected);
        }
    }
    return 0;
}
#endif
