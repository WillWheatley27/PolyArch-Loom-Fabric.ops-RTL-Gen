#!/usr/bin/env bash
# End-to-end demo: generate group-15 RTL, lint it, simulate the TB, expect PASS.
# Lives in demos/; cd's to the repo root. (exp/exp2/expm1 via 2^f LUT, approximate.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/demo_exp_series
rm -rf "$OUT"
mkdir -p "$OUT"

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@math.exp, @math.exp2, @math.expm1]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_exp_series.sv"
TB="tb/math/exp_series/tb_fu_exp_series.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

echo "[demo] build + run TB (WIDTH=32) ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_exp_series -GEXP_W=8 -GMANT_W=23 --Mdir "$OUT/obj" -o sim \
  "$RTL" "$TB"
"$OUT/obj/sim" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
