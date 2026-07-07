#!/usr/bin/env bash
# Demo: fp_add_sub across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct fp_add_sub "fabric.op[@arith.addf, @arith.subf]" fp_arith/fp_add_sub
