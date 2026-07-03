"""IEEE-754 format descriptors for parameterizing floating-point FUs.

A format is defined by (exp_w, mant_w); all other shape constants derive from it.
The generator passes a resolved descriptor into templates so a single parameterized
SystemVerilog module works at any format (fp32 default, fp64, optional bf16).
"""

# Named formats -> (exponent bits, mantissa/fraction bits).
FP_FORMATS = {
    "bf16": (8, 7),    # optional
    "fp32": (8, 23),   # IEEE-754 binary32 (default)
    "fp64": (11, 52),  # IEEE-754 binary64
}

DEFAULT_FP_FORMAT = "fp32"


def fp_format(name):
    """Resolve a format name into a descriptor dict of derived shape constants."""
    if name not in FP_FORMATS:
        raise ValueError(
            f"unknown FP format '{name}'; known: {sorted(FP_FORMATS)}"
        )
    exp_w, mant_w = FP_FORMATS[name]
    return {
        "name": name,
        "exp_w": exp_w,
        "mant_w": mant_w,
        "total_w": 1 + exp_w + mant_w,   # sign + exponent + mantissa
        "sig_w": mant_w + 1,             # significand incl. implicit leading 1
        "bias": (1 << (exp_w - 1)) - 1,  # exponent bias
    }
