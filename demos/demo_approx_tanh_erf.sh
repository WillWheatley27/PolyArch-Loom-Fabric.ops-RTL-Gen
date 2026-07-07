#!/usr/bin/env bash
# Demo: approx_tanh_erf across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_data approx_tanh_erf "fabric.op[@math.tanh, @math.erf]" math/approx_tanh_erf
