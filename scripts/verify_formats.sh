#!/usr/bin/env bash
# verify_formats.sh -- multi-format regression: for every share group, generate +
# lint + simulate the testbench at EACH supported design point (not just the fp32
# default the demos use). Integer FUs sweep WIDTH 8/16/32/64; FP/transcendental
# FUs run fp32 and fp64 (bf16 too where cheap).
#
#   - Integer & structural-FP FUs are genuinely parameterized SV: generate once,
#     re-parameterize via -GWIDTH / -GEXP_W/-GMANT_W.
#   - Poly/LUT/CORDIC FUs bake per-format data, so they are GENERATED per format
#     (--format) and the TB compiled with the matching -G.
#
# Usage: scripts/verify_formats.sh          (all groups, all points)
set -uo pipefail
cd "$(dirname "$0")/.."

PY=./.venv/bin/python; [ -x "$PY" ] || PY=python3
if ! command -v verilator >/dev/null 2>&1; then
  type module >/dev/null 2>&1 && module load verilator/5.044 2>/dev/null || true
fi
command -v verilator >/dev/null 2>&1 || { echo "verilator not found"; exit 1; }

VF="--binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD"
GEN() { PYTHONPATH=generator "$PY" -m fabric_gen "$@" >/dev/null; }
pass=0; fail=0; fails=""

# build+run one (name, top, rtl, tb, "-G flags"); lint-clean -Wall required
run() {
  local name=$1 top=$2 rtl=$3 tb=$4 g=$5
  local out=build/vf/$name; rm -rf "$out"; mkdir -p "$out"
  if ! verilator --lint-only -Wall $g "$rtl" >"$out/lint.log" 2>&1; then
    printf "  %-28s LINT-FAIL\n" "$name"; fail=$((fail+1)); fails="$fails $name(lint)"; return
  fi
  if ! verilator $VF --top-module "$top" $g --Mdir "$out/obj" -o sim "$rtl" "$tb" >"$out/b.log" 2>&1; then
    printf "  %-28s BUILD-FAIL\n" "$name"; fail=$((fail+1)); fails="$fails $name(build)"; return
  fi
  local res; res=$("$out/obj/sim" 2>/dev/null | grep -E "^PASS:|^FAIL:" | head -1)
  if [[ "$res" == PASS:* ]]; then
    printf "  %-28s ok    (%s)\n" "$name" "${res#PASS: }"; pass=$((pass+1))
  else
    printf "  %-28s SIM-FAIL\n" "$name"; fail=$((fail+1)); fails="$fails $name(sim)"
  fi
}

# --- Integer FUs: one generated file, sweep WIDTH ---
echo "== integer FUs (WIDTH 8/16/32/64) =="
INT_GROUPS=(
  "add_sub:fabric.op[@arith.addi, @arith.subi]:int_arith/add_sub"
  "div_rem_signed:fabric.op[@arith.divsi, @arith.remsi]:int_arith/div_rem_signed"
  "div_rem_unsigned:fabric.op[@arith.divui, @arith.remui]:int_arith/div_rem_unsigned"
  "barrel_shift:fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]:int_arith/barrel_shift"
  "bitwise_alu:fabric.op[@arith.andi, @arith.ori, @arith.xori]:int_arith/bitwise_alu"
  "min_max_signed:fabric.op[@arith.minsi, @arith.maxsi]:int_arith/min_max_signed"
  "min_max_unsigned:fabric.op[@arith.minui, @arith.maxui]:int_arith/min_max_unsigned"
)
for spec in "${INT_GROUPS[@]}"; do
  m=${spec%%:*}; rest=${spec#*:}; op=${rest%:*}; path=${rest##*:}
  d=build/vf/gen_$m; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d"
  for w in 8 16 32 64; do
    run "${m}_W${w}" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GWIDTH=$w"
  done
done

# --- Structural FP FUs: one generated file, re-parameterize by format ---
echo "== structural FP FUs (bf16 + fp32 + fp64) =="
FP_GROUPS=(
  "int_to_fp:fabric.op[@arith.sitofp, @arith.uitofp]:int_arith/int_to_fp"
  "fp_to_int:fabric.op[@arith.fptosi, @arith.fptoui]:int_arith/fp_to_int"
  "fp_add_sub:fabric.op[@arith.addf, @arith.subf]:fp_arith/fp_add_sub"
  "fp_div_rem:fabric.op[@arith.divf, @arith.remf]:fp_arith/fp_div_rem"
  "fp_min_max:fabric.op[@arith.minimumf, @arith.maximumf]:fp_arith/fp_min_max"
  "rounding:fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]:math/rounding"
)
for spec in "${FP_GROUPS[@]}"; do
  m=${spec%%:*}; rest=${spec#*:}; op=${rest%:*}; path=${rest##*:}
  d=build/vf/gen_$m; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d"
  run "${m}_bf16" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=8 -GMANT_W=7"
  run "${m}_fp32" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=8 -GMANT_W=23"
  run "${m}_fp64" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=11 -GMANT_W=52"
done

# --- Data-bearing FUs (poly/LUT/CORDIC): generate per format ---
echo "== poly/LUT/CORDIC FUs (generated per format: bf16 + fp32 + fp64) =="
DATA_GROUPS=(
  "cordic_trig:fabric.op[@math.sin, @math.cos]:math/cordic_trig"
  "cordic_hyp:fabric.op[@math.sinh, @math.cosh]:math/cordic_hyp"
  "exp_series:fabric.op[@math.exp, @math.exp2, @math.expm1]:math/exp_series"
  "log_core:fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]:math/log_core"
  "sqrt_rsqrt:fabric.op[@math.sqrt, @math.rsqrt]:math/sqrt_rsqrt"
  "approx_tanh_erf:fabric.op[@math.tanh, @math.erf]:math/approx_tanh_erf"
)
for spec in "${DATA_GROUPS[@]}"; do
  m=${spec%%:*}; rest=${spec#*:}; op=${rest%:*}; path=${rest##*:}
  for fmt in "bf16:8:7" "fp32:8:23" "fp64:11:52"; do
    fn=${fmt%%:*}; e=$(echo "$fmt"|cut -d: -f2); mw=$(echo "$fmt"|cut -d: -f3)
    d=build/vf/gen_${m}_${fn}; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d" --format "$fn"
    run "${m}_${fn}" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=$e -GMANT_W=$mw"
  done
done

echo "======================================================"
echo "verify_formats: $pass passed, $fail failed"
[ -n "$fails" ] && echo "failures:$fails"
[ "$fail" -eq 0 ]
