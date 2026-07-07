#!/usr/bin/env bash
# Demo: bitwise_alu across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int bitwise_alu "fabric.op[@arith.andi, @arith.ori, @arith.xori]" int_arith/bitwise_alu
