#!/usr/bin/env bash
# Lint + simulate fu_add_sub at WIDTH 32 and 8. Requires verilator on PATH
# (run `module load verilator/5.044` first, or this script loads it if available).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="ops/int_arith/add_sub/fu_add_sub.sv"
TB="tb/int_arith/add_sub/tb_fu_add_sub.sv"

echo "== lint =="
verilator --lint-only -Wall "$RTL"

for W in 32 8; do
  echo "== sim WIDTH=$W =="
  verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
    --top-module tb_fu_add_sub -GWIDTH="$W" --Mdir "build/obj_w$W" -o "sim_w$W" \
    "$RTL" "$TB"
  "build/obj_w$W/sim_w$W" | tee "build/sim_w$W.log"
  grep -q "^PASS:" "build/sim_w$W.log"
done
echo "ALL RTL CHECKS PASSED"
