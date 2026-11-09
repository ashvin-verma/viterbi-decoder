"""ber_theory.py -- Reference BER curves for rate-1/2 convolutional codes.

* distance_spectrum(): B_d (total information weight of all error events of
  output weight d) by dynamic programming over the code trellis, using the
  same register convention as the RTL / server encoder.
* Union bounds for hard-decision (BSC) and soft-decision (AWGN) Viterbi
  decoding, plus uncoded BPSK.

The on-chip BER tester uses a BSC with crossover p = Q(sqrt(2 R Eb/N0)),
which is exactly what a hard-decision BPSK receiver sees over AWGN.
"""
import math
from functools import lru_cache

RATE = 0.5


def _parity(x):
    return bin(x).count("1") & 1


def q_func(x):
    return 0.5 * math.erfc(x / math.sqrt(2.0))


def ebn0_to_p(ebn0_db, rate=RATE):
    """Hard-decision channel crossover probability for BPSK/AWGN."""
    ebn0 = 10.0 ** (ebn0_db / 10.0)
    return q_func(math.sqrt(2.0 * rate * ebn0))


@lru_cache(maxsize=None)
def distance_spectrum(k, g0, g1, extra=6, max_len=400):
    """Return (d_free, {d: B_d}) for weights d_free .. d_free+extra."""
    m = k - 1
    mask = (1 << m) - 1

    def branch(s, b):
        reg = (b & 1) | (s << 1)
        w = _parity(reg & g0) + _parity(reg & g1)
        return ((s << 1) | b) & mask, w

    # Track weights up to (upper bound on d_free) + extra. For rate-1/2
    # codes d_free <= 2K, and good codes are well below that.
    d_cap = int(1.5 * k) + 2 + extra
    # live[state] = {d: (n_paths, info_weight_sum)}
    live = {}
    s1, w1 = branch(0, 1)
    live[s1] = {w1: (1, 1)}
    spectrum = {}
    for _ in range(max_len):
        if not live:
            break
        nxt = {}
        for s, dmap in live.items():
            for b in (0, 1):
                s2, w = branch(s, b)
                for d, (n, iw) in dmap.items():
                    d2 = d + w
                    if d2 > d_cap:
                        continue
                    n2, iw2 = n, iw + b * n
                    if s2 == 0:
                        on, oiw = spectrum.get(d2, (0, 0))
                        spectrum[d2] = (on + n2, oiw + iw2)
                    else:
                        tgt = nxt.setdefault(s2, {})
                        on, oiw = tgt.get(d2, (0, 0))
                        tgt[d2] = (on + n2, oiw + iw2)
        live = nxt
    if not spectrum:
        return None, {}
    d_free = min(spectrum)
    out = {d: spectrum[d][1] for d in sorted(spectrum) if d <= d_free + extra}
    return d_free, out


def _pd_hard(d, p):
    """Pairwise error probability for weight-d event on a BSC."""
    q = 1.0 - p
    total = 0.0
    for e in range(d // 2 + 1, d + 1):
        total += math.comb(d, e) * p ** e * q ** (d - e)
    if d % 2 == 0:
        total += 0.5 * math.comb(d, d // 2) * (p * q) ** (d // 2)
    return total


def union_bound_hard(spec, ebn0_db):
    p = ebn0_to_p(ebn0_db)
    return min(0.5, sum(bd * _pd_hard(d, p) for d, bd in spec.items()))


def union_bound_soft(spec, ebn0_db):
    ebn0 = 10.0 ** (ebn0_db / 10.0)
    return min(0.5, sum(bd * q_func(math.sqrt(2.0 * d * RATE * ebn0))
                        for d, bd in spec.items()))


def uncoded_bpsk(ebn0_db):
    return q_func(math.sqrt(2.0 * 10.0 ** (ebn0_db / 10.0)))


@lru_cache(maxsize=None)
def theory_curves(k, g0, g1, lo=0.0, hi=10.0, step=0.25):
    d_free, spec = distance_spectrum(k, g0, g1)
    xs = [round(lo + i * step, 3) for i in range(int((hi - lo) / step) + 1)]
    return {
        "k": k,
        "d_free": d_free,
        "spectrum": {str(d): b for d, b in spec.items()},
        "ebn0_db": xs,
        "uncoded": [uncoded_bpsk(x) for x in xs],
        "channel_p": [ebn0_to_p(x) for x in xs],
        "hard_bound": [union_bound_hard(spec, x) for x in xs],
        "soft_bound": [union_bound_soft(spec, x) for x in xs],
    }


if __name__ == "__main__":
    for k, g0, g1 in ((3, 0o7, 0o5), (5, 0o23, 0o35), (7, 0o171, 0o133), (9, 0o561, 0o753)):
        d_free, spec = distance_spectrum(k, g0, g1, extra=4)
        print(f"K={k}: d_free={d_free} B_d={spec}")
