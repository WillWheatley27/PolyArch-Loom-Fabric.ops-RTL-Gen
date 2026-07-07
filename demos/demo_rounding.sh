#!/usr/bin/env bash
# Demo: rounding across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct rounding "fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]" math/rounding
