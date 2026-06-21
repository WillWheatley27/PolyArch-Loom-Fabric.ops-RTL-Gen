# Design: Share Group 13 RTL (`fu_cordic_trig`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (CORDIC, base-range fold — user choice), pending impl
**Scope:** Share group 13 (`cordic_trig` = `math.sin` / `math.cos`). First
transcendental / `math`-dialect group. **Approximate** (~16-bit), tolerance-
verified, range-limited. No loom reference (loom rejects transcendentals).

---

## 1. Goal
- `op_sel = 0` → `math.sin(x)`
- `op_sel = 1` → `math.cos(x)`
x in radians (binary32). One shared CORDIC rotator: X output = cos, Y = sin.

## 2. Approach (CORDIC, fixed-point Q4.28, binary32 I/O)
- **Decode** binary32 x → signed Q4.28 fixed-point (×2²⁸). FTZ (exp==0 → 0).
- **Quadrant fold** to [-π/2, π/2] (CORDIC convergence ≈ ±1.74 ⊃ ±π/2):
  if `ang > π/2`: `ang -= π`, negate both outputs; if `ang < -π/2`: `ang += π`,
  negate both. **Assumes |x| ≤ π** (no full mod-2π reduction; larger |x| is out
  of scope / documented).
- **CORDIC** circular rotation mode, 16 iterations (unrolled, combinational):
  `x₀=K (gain 0.60725…), y₀=0, z₀=ang`. Each i: if z≥0 `{x-=y>>i, y+=x>>i,
  z-=atan(2⁻ⁱ)}` else the mirror. `x₁₆≈cos(ang)`, `y₁₆≈sin(ang)` (gain
  pre-compensated by K). Arithmetic shifts; atan ROM in Q4.28.
- **Quadrant correct**: negate cos/sin if folded. `op_sel` taps sin (Y) or cos (X).
- **Encode** Q4.28 result → binary32 (leading-zero normalize + RNE; value =
  fixed × 2⁻²⁸). FTZ on underflow.
- **Latency-1** registered output (loom unary FP handshake).

Constants (Q4.28): `K=163008219`, `π=843314857`, `π/2=421657428`, and the
16-entry `atan(2⁻ⁱ)` table (computed exactly, embedded as localparams).

## 3. Accuracy & verification
~16-bit accurate (16 iterations) over the supported range. **Not bit-exact** —
the testbench checks `|decode(dut) − $sin/$cos(decode(x))| < TOL` (absolute), with
`TOL` documented from the measured worst case (target ≈ 2⁻¹², i.e. < ~2.5e-4).
Random inputs constrained to [-π, π]; directed corners (0, ±π/2, ±π/6, ±π/4, etc.).

## 4. Generator + template
- `generator/templates/fu_cordic_trig.sv.j2` (uses `params.width`,
  `params.iterations`, `op_list`). Add `"cordic_trig"` to `_TEMPLATE_MAP`.
  Golden = output for `fabric.op[@math.sin, @math.cos]`. New family path
  `ops/math/cordic_trig/`, `tb/math/cordic_trig/`.
- `registry.yaml`: group 13 `status: not_started → verified`.

## 5. Testbench — `tb/math/cordic_trig/tb_fu_cordic_trig.sv`
Unary, latency-1. Directed (sin/cos of 0, ±π/6, ±π/4, ±π/3, ±π/2, ±π, small x)
checked within TOL; randomized x ∈ [-π, π] checked vs `$sin`/`$cos` within TOL;
handshake corners. Reports max observed error.

## 6. Python tests
- Add lookup + writes + golden for `cordic_trig`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 14 (`fabric.op[@math.sinh, @math.cosh]`, cordic_hyp).

## 7. Notes
This is the first **approximate** unit: results are float-formatted but ~16-bit
accurate and range-limited (|x| ≤ π). Distinct from the bit-exact groups 1–12.
