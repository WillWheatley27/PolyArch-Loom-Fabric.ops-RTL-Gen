#!/usr/bin/env bash
# Demo: div_rem_signed across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int div_rem_signed "fabric.op[@arith.divsi, @arith.remsi]" int_arith/div_rem_signed
