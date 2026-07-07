#!/usr/bin/env bash
# Demo: log_core across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data log_core "fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]" math/log_core
