#!/usr/bin/env bash
# End-to-end demo: generate group-17 RTL, lint it, simulate the TB, expect PASS.
# Lives in demos/; cd's to the repo root. (floor/ceil/round/trunc/roundeven, exact.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/demo_rounding
rm -rf "$OUT"
mkdir -p "$OUT"

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_rounding.sv"
TB="tb/math/rounding/tb_fu_rounding.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

echo "[demo] build + run TB (WIDTH=32) ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_rounding -GEXP_W=8 -GMANT_W=23 --Mdir "$OUT/obj" -o sim \
  "$RTL" "$TB"
"$OUT/obj/sim" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
