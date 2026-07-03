"""Compile-time polynomial approximation for transcendental FUs (pure Python).

No numpy: uses Chebyshev-node interpolation (near-minimax for smooth functions)
with a Gaussian-elimination solver, then quantizes to signed fixed-point integer
coefficients for a Horner evaluator in generated RTL. Coefficients and their
count/precision are chosen by the generator per (function, format) at generation
("compile") time -- no runtime ROM.
"""

import math


def _solve(A, b):
    """Solve A x = b (dense, Gaussian elimination with partial pivoting)."""
    n = len(A)
    M = [list(A[i]) + [b[i]] for i in range(n)]
    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(M[r][col]))
        M[col], M[piv] = M[piv], M[col]
        pv = M[col][col]
        for j in range(col, n + 1):
            M[col][j] /= pv
        for r in range(n):
            if r != col and M[r][col] != 0.0:
                f = M[r][col]
                for j in range(col, n + 1):
                    M[r][j] -= f * M[col][j]
    return [M[i][n] for i in range(n)]


def cheb_fit(func, a, b, degree):
    """Monomial coeffs [c0..c_degree] (ascending) interpolating func at the
    degree+1 Chebyshev nodes on [a, b] -- near-minimax for smooth func."""
    n = degree + 1
    nodes = [0.5 * (a + b) + 0.5 * (b - a) * math.cos(math.pi * (k + 0.5) / n)
             for k in range(n)]
    A = [[x ** j for j in range(n)] for x in nodes]
    return _solve(A, [func(x) for x in nodes])


def poly_eval(coeffs, x):
    """Horner evaluation of a monomial polynomial (ascending coeffs)."""
    acc = 0.0
    for c in reversed(coeffs):
        acc = acc * x + c
    return acc


def max_abs_error(func, coeffs, a, b, samples=4000):
    m = 0.0
    for i in range(samples + 1):
        x = a + (b - a) * i / samples
        e = abs(poly_eval(coeffs, x) - func(x))
        if e > m:
            m = e
    return m


def fixed_coeffs(coeffs, frac_bits):
    """Round real coeffs to signed integers scaled by 2^frac_bits (Q?.frac_bits)."""
    scale = 1 << frac_bits
    return [int(round(c * scale)) for c in coeffs]


def fit_for_precision(func, a, b, target_err, max_degree=12, min_degree=2):
    """Lowest-degree Chebyshev fit whose sampled max error <= target_err.
    Returns (degree, coeffs, err). Falls back to max_degree if unmet."""
    best = None
    for d in range(min_degree, max_degree + 1):
        c = cheb_fit(func, a, b, d)
        e = max_abs_error(func, c, a, b)
        best = (d, c, e)
        if e <= target_err:
            return best
    return best
