#!/usr/bin/env bash
# End-to-end demo: generate group-19 RTL, lint it, simulate the TB, expect PASS.
# Lives in demos/; cd's to the repo root. (LUT tanh/erf, approximate, |x|<=4 table.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/demo_approx_tanh_erf
rm -rf "$OUT"
mkdir -p "$OUT"

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@math.tanh, @math.erf]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_approx_tanh_erf.sv"
TB="tb/math/approx_tanh_erf/tb_fu_approx_tanh_erf.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

echo "[demo] build + run TB (WIDTH=32) ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_approx_tanh_erf -GEXP_W=8 -GMANT_W=23 --Mdir "$OUT/obj" -o sim \
  "$RTL" "$TB"
"$OUT/obj/sim" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
