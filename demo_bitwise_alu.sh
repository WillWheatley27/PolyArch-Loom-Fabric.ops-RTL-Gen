#!/usr/bin/env bash
# End-to-end demo: generate group-5 RTL, lint it, simulate the TB at two widths,
# expect PASS. Mirrors the prior demos.
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/demo_bitwise
rm -rf "$OUT"
mkdir -p "$OUT"

# Python via project venv if present, else system python3.
PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then PY="python3"; fi

echo "[demo] generate ..."
PYTHONPATH=generator "$PY" -m fabric_gen "fabric.op[@arith.andi, @arith.ori, @arith.xori]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="$OUT/fu_bitwise_alu.sv"
TB="tb/int_arith/bitwise_alu/tb_fu_bitwise_alu.sv"

echo "[demo] lint ..."
verilator --lint-only -Wall "$RTL"

for W in 32 8; do
  echo "[demo] build + run TB (WIDTH=$W) ..."
  verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
    --top-module tb_fu_bitwise_alu -GWIDTH="$W" --Mdir "$OUT/obj_${W}" -o "sim_w${W}" \
    "$RTL" "$TB"
  "$OUT/obj_${W}/sim_w${W}" | tee "$OUT/sim_${W}.log"
  grep -q "^PASS:" "$OUT/sim_${W}.log"
done

echo "DEMO OK"
