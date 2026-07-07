#!/usr/bin/env bash
# Demo: sqrt_rsqrt across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data sqrt_rsqrt "fabric.op[@math.sqrt, @math.rsqrt]" math/sqrt_rsqrt
