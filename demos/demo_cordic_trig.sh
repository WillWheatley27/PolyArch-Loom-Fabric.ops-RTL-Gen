#!/usr/bin/env bash
# End-to-end demo: generate group-13 RTL, lint it, simulate the TB, expect PASS.
# Lives in demos/; cd's to the repo root. (CORDIC sin/cos, ~16-bit, |x|<=pi.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/demo_cordic_trig
rm -rf "$OUT"
mkdir -p "$OUT"

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@math.sin, @math.cos]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_cordic_trig.sv"
TB="tb/math/cordic_trig/tb_fu_cordic_trig.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

echo "[demo] build + run TB (WIDTH=32) ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_cordic_trig -GWIDTH=32 --Mdir "$OUT/obj" -o sim \
  "$RTL" "$TB"
"$OUT/obj/sim" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
