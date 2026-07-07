#!/usr/bin/env bash
# Demo: add_sub across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_int add_sub "fabric.op[@arith.addi, @arith.subi]" int_arith/add_sub
