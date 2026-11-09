/*
 * fbloop.c -- tight frame loop for the Viterbi frame buffer (PYNQ Linux).
 *
 * The Python agent spends ~2 ms per frame in pynq.MMIO calls; this does the
 * same register sequence as Board.decode_many() with plain 32-bit volatile
 * accesses through an mmap of /dev/mem. Built on the board by deploy.py:
 *     gcc -O2 -shared -fPIC -o libfbloop.so fbloop.c
 * and called through ctypes (requires root, like pynq.MMIO).
 */
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define FB_BASE   0x43C00000u
#define FB_SIZE   0x40000u
#define R_CTRL    (0x000 / 4)
#define R_STATUS  (0x004 / 4)
#define R_FLEN    (0x008 / 4)
#define R_IN      (0x400 / 4)
#define R_OUT     (0x800 / 4)
#define ST_BUSY   0x1u
#define ST_DONE   0x2u

static volatile uint32_t *fb;

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* Map the frame buffer. Returns 0 on success. */
int fb_open(void)
{
    if (fb)
        return 0;
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0)
        return -1;
    void *p = mmap(NULL, FB_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FB_BASE);
    close(fd);
    if (p == MAP_FAILED)
        return -2;
    fb = (volatile uint32_t *)p;
    return 0;
}

/*
 * Decode nframes frames back to back.
 *   in:      frames packed at a 256-byte stride; in_len[i] bytes valid (1..256)
 *   out:     receives each frame's output at a 256-byte stride
 *   out_len: receives each frame's output byte count
 *   hw_s:    receives the wall time of the whole loop in seconds
 * Returns the number of frames completed (== nframes on success).
 */
int fb_decode_many(const uint8_t *in, const int *in_len, int nframes,
                   uint8_t *out, int *out_len, double timeout_s, double *hw_s)
{
    if (!fb)
        return -1;
    double t0 = now_s();
    for (int f = 0; f < nframes; f++) {
        const uint8_t *src = in + (size_t)f * 256;
        int n = in_len[f];
        fb[R_FLEN] = (uint32_t)n;
        for (int i = 0; i < n; i += 4) {
            uint32_t w = 0;
            for (int b = 0; b < 4 && i + b < n; b++)
                w |= (uint32_t)src[i + b] << (8 * b);
            fb[R_IN + i / 4] = w;
        }
        fb[R_CTRL] = 1;

        /* Wait for DONE to drop (trigger accepted), then to rise again. A
         * frame takes >= 0.4 ms, so a stale DONE from the previous frame
         * can never be mistaken for completion. */
        double t1 = now_s();
        uint32_t st;
        while ((st = fb[R_STATUS]) & ST_DONE) {
            if (now_s() - t1 > timeout_s)
                goto timeout;
        }
        while (!((st = fb[R_STATUS]) & ST_DONE)) {
            if (now_s() - t1 > timeout_s)
                goto timeout;
        }
        int oc = (st >> 8) & 0xFF;
        uint8_t *dst = out + (size_t)f * 256;
        for (int i = 0; i < oc; i += 4) {
            uint32_t w = fb[R_OUT + i / 4];
            for (int b = 0; b < 4 && i + b < oc; b++)
                dst[i + b] = (uint8_t)(w >> (8 * b));
        }
        out_len[f] = oc;
        continue;
timeout:
        *hw_s = now_s() - t0;
        return f;
    }
    *hw_s = now_s() - t0;
    return nframes;
}
