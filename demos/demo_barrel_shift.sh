#!/usr/bin/env bash
# Demo: barrel_shift across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int barrel_shift "fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]" int_arith/barrel_shift
