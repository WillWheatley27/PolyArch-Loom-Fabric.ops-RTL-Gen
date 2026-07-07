#!/usr/bin/env bash
# Demo: cordic_trig across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data cordic_trig "fabric.op[@math.sin, @math.cos]" math/cordic_trig
