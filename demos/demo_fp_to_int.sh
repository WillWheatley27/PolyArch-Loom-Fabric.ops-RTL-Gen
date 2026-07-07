#!/usr/bin/env bash
# Demo: fp_to_int across ALL supported design points.
set -euo pipefail
cd "$(dirname "$0")/.."
source demos/_demo_lib.sh
demo_fp_struct fp_to_int "fabric.op[@arith.fptosi, @arith.fptoui]" int_arith/fp_to_int
