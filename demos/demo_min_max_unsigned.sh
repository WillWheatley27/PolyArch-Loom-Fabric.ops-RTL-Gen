#!/usr/bin/env bash
# Demo: min_max_unsigned across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int min_max_unsigned "fabric.op[@arith.minui, @arith.maxui]" int_arith/min_max_unsigned
