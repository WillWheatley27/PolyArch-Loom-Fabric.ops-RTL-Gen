# _demo_lib.sh -- shared helpers for the per-group demos (sourced, not executed;
# the leading underscore keeps it out of `demos/demo*.sh` globs).
#
# Each demo sweeps EVERY design point its FU supports (not just the fp32/width-32
# default): generate -> lint (-Wall) -> build -> run the parameterized testbench ->
# require PASS, once per point. Three FU classes:
#   demo_int       WIDTH 8/16/32/64        (one generated file, re-param via -GWIDTH)
#   demo_fp_struct bf16/fp32/fp64          (one generated file, re-param via -GEXP_W/-GMANT_W)
#   demo_fp_data   bf16/fp32/fp64          (poly/LUT/CORDIC: GENERATE per --format)

PY=./.venv/bin/python; [ -x "$PY" ] || PY=python3
if ! command -v verilator >/dev/null 2>&1; then
  type module >/dev/null 2>&1 && module load verilator/5.044 2>/dev/null || true
fi
VFLAGS="--binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD"
GEN() { PYTHONPATH=generator "$PY" -m fabric_gen "$@" >/dev/null; }

# _run <label> <top> <rtl> <tb> <-G flags...>   (lint-clean -Wall required)
_run() {
  local label=$1 top=$2 rtl=$3 tb=$4 g=$5
  local out=build/demo/$label; rm -rf "$out"; mkdir -p "$out"
  if ! verilator --lint-only -Wall $g "$rtl" >"$out/lint.log" 2>&1; then
    printf "  %-24s LINT-FAIL  (see %s)\n" "$label" "$out/lint.log"; return 1
  fi
  if ! verilator $VFLAGS --top-module "$top" $g --Mdir "$out/obj" -o sim "$rtl" "$tb" >"$out/build.log" 2>&1; then
    printf "  %-24s BUILD-FAIL (see %s)\n" "$label" "$out/build.log"; return 1
  fi
  local res; res=$("$out/obj/sim" 2>/dev/null | grep -E "^PASS:|^FAIL:" | head -1)
  printf "  %-24s %s\n" "$label" "${res:-SIM-FAIL (no PASS/FAIL line)}"
  [[ "$res" == PASS:* ]]
}

# demo_int <module> <op-string> <tb-family/dir>
demo_int() {
  local m=$1 op=$2 path=$3
  local d=build/demo/gen_$m; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d"
  echo "== $m : WIDTH 8 / 16 / 32 / 64 =="
  local w
  for w in 8 16 32 64; do
    _run "${m}_W${w}" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GWIDTH=$w"
  done
  echo "DEMO OK ($m: all widths)"
}

# demo_fp_struct <module> <op-string> <tb-family/dir>   (genuinely parameterized SV)
demo_fp_struct() {
  local m=$1 op=$2 path=$3
  local d=build/demo/gen_$m; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d"
  echo "== $m : bf16 / fp32 / fp64 =="
  _run "${m}_bf16" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=8 -GMANT_W=7"
  _run "${m}_fp32" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=8 -GMANT_W=23"
  _run "${m}_fp64" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=11 -GMANT_W=52"
  echo "DEMO OK ($m: bf16/fp32/fp64)"
}

# demo_fp_data <module> <op-string> <tb-family/dir>   (coeffs/tables baked per format)
demo_fp_data() {
  local m=$1 op=$2 path=$3 fmt fn e mw d
  echo "== $m : bf16 / fp32 / fp64 (generated per format) =="
  for fmt in "bf16:8:7" "fp32:8:23" "fp64:11:52"; do
    fn=${fmt%%:*}; e=$(echo "$fmt" | cut -d: -f2); mw=$(echo "$fmt" | cut -d: -f3)
    d=build/demo/gen_${m}_${fn}; rm -rf "$d"; mkdir -p "$d"; GEN "$op" -o "$d" --format "$fn"
    _run "${m}_${fn}" "tb_fu_${m}" "$d/fu_${m}.sv" "tb/${path}/tb_fu_${m}.sv" "-GEXP_W=$e -GMANT_W=$mw"
  done
  echo "DEMO OK ($m: bf16/fp32/fp64)"
}
