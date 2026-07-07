#!/usr/bin/env bash
# Demo: fp_min_max across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct fp_min_max "fabric.op[@arith.minimumf, @arith.maximumf]" fp_arith/fp_min_max
