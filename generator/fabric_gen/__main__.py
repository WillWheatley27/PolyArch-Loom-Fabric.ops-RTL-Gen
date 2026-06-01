"""CLI: python -m fabric_gen '<op-string>' -o <dir> [--width N]."""

import argparse
import sys

from .generator import generate
from .errors import FabricGenError


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="fabric_gen",
        description="Generate Fabric FU SystemVerilog from a fabric.op[...] string.",
    )
    p.add_argument("op_string", help="e.g. 'fabric.op[@arith.addi, @arith.subi]'")
    p.add_argument("-o", "--out-dir", default=".", help="output directory")
    p.add_argument("--width", type=int, default=None, help="override data width")
    args = p.parse_args(argv)

    try:
        out = generate(args.op_string, args.out_dir, width=args.width)
    except FabricGenError as e:
        print(f"fabric-gen error: {e.category}: {e}", file=sys.stderr)
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
