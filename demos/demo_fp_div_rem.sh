#!/usr/bin/env bash
# Demo: fp_div_rem across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct fp_div_rem "fabric.op[@arith.divf, @arith.remf]" fp_arith/fp_div_rem
