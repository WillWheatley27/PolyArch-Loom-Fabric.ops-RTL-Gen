#!/usr/bin/env bash
# Demo: exp_series across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data exp_series "fabric.op[@math.exp, @math.exp2, @math.expm1]" math/exp_series
