#!/usr/bin/env bash
# Demo: min_max_signed across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int min_max_signed "fabric.op[@arith.minsi, @arith.maxsi]" int_arith/min_max_signed
