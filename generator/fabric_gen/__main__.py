"""CLI: python -m fabric_gen '<op-string>' -o <dir> [--width N] [--format FMT]."""

import argparse
import sys

from .generator import generate
from .errors import FabricGenError
from .formats import FP_FORMATS


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="fabric_gen",
        description="Generate Fabric FU SystemVerilog from a fabric.op[...] string.",
    )
    p.add_argument("op_string", help="e.g. 'fabric.op[@arith.addi, @arith.subi]'")
    p.add_argument("-o", "--out-dir", default=".", help="output directory")
    p.add_argument("--width", type=int, default=None,
                   help="override integer data width (e.g. 8, 16, 32, 64)")
    p.add_argument("--format", default=None, choices=sorted(FP_FORMATS),
                   help="floating-point format for FP/transcendental FUs (default fp32)")
    args = p.parse_args(argv)

    try:
        out = generate(args.op_string, args.out_dir, width=args.width, fmt=args.format)
    except FabricGenError as e:
        print(f"fabric-gen error: {e.category}: {e}", file=sys.stderr)
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
