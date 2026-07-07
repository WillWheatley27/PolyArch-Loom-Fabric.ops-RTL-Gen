#!/usr/bin/env bash
# Demo: cordic_hyp across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data cordic_hyp "fabric.op[@math.sinh, @math.cosh]" math/cordic_hyp
