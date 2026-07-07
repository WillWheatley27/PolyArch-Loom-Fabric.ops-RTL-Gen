#!/usr/bin/env bash
# Demo: int_to_fp across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct int_to_fp "fabric.op[@arith.sitofp, @arith.uitofp]" int_arith/int_to_fp
