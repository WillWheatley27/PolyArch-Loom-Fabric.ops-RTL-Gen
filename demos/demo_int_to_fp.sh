#!/usr/bin/env bash
# End-to-end demo: generate group-8 RTL, lint it, simulate the TB, expect PASS.
# Lives in demos/; cd's to the repo root. (int32 -> IEEE-754 binary32.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/demo_int_to_fp
rm -rf "$OUT"
mkdir -p "$OUT"

# Python via project venv if present, else system python3.
PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@arith.sitofp, @arith.uitofp]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_int_to_fp.sv"
TB="tb/int_arith/int_to_fp/tb_fu_int_to_fp.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

echo "[demo] build + run TB (INT_WIDTH=32) ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_int_to_fp -GINT_WIDTH=32 --Mdir "$OUT/obj" -o sim \
  "$RTL" "$TB"
"$OUT/obj/sim" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
