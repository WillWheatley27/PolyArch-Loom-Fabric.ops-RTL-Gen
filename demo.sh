#!/usr/bin/env bash
# End-to-end demo: generate group-1 RTL, lint it, simulate the TB, expect PASS.
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/demo
rm -rf "$OUT"
mkdir -p "$OUT"

# Python via project venv if present, else system python3.
PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

echo "[demo] lint ..."
verilator --lint-only -Wall "$OUT/fu_add_sub.sv"

echo "[demo] build + run TB ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_add_sub -GWIDTH=32 --Mdir "$OUT/obj_dir" -o sim_w32 \
  "$OUT/fu_add_sub.sv" tb/int_arith/add_sub/tb_fu_add_sub.sv
"$OUT/obj_dir/sim_w32" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
