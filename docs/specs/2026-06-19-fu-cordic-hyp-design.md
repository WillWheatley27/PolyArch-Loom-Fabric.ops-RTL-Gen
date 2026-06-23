# Design: Share Group 14 RTL (`fu_cordic_hyp`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (hyperbolic analog of group 13; same approximate-CORDIC
philosophy), pending impl
**Scope:** Share group 14 (`cordic_hyp` = `math.sinh` / `math.cosh`). Hyperbolic
CORDIC. Approximate (~16-bit), tolerance-verified, range-limited.

---

## 1. Goal
- `op_sel = 0` → `math.sinh(x)`
- `op_sel = 1` → `math.cosh(x)`
One shared hyperbolic CORDIC rotator: X output = cosh, Y = sinh.

## 2. Approach — hyperbolic CORDIC (differences vs group 13)
Same structure as `fu_cordic_trig` (binary32 ↔ Q4.28, unrolled CORDIC, latency-1),
with the hyperbolic-mode changes:
- **Recurrence:** `x += d·(y>>i)`, `y += d·(x>>i)`, `z -= d·atanh(2⁻ⁱ)` (the X
  update sign matches Y's, unlike circular mode).
- **Iteration sequence (16 steps):** i = 1,2,3,**4,4**,5,…,**13,13**,14 — iterations
  4 and 13 are **repeated** (required for hyperbolic convergence).
- **Start:** `x₀ = 1/A_h = 1.20750` (Q4.28 `324135026`), `y₀=0`, `z₀=x` → `x→cosh`,
  `y→sinh`. (`A_h = ∏√(1−2⁻²ⁱ)`.)
- **No quadrant fold** (sinh/cosh aren't periodic). cosh is even (always ≥1),
  sinh is odd (sign follows x) — both fall out of `z₀=x` directly.
- **Range:** converges only for **|x| ≤ θ_max ≈ 1.1181** (Σ atanh over the
  sequence). Larger |x| is **out of scope / documented** (no range extension;
  sinh/cosh grow exponentially). This is the analog of group 13's |x| ≤ π limit.

Constants (Q4.28, computed exactly, embedded): `x₀=324135026`, plus per-step
`SHIFT` (i) and `ATANH(2⁻ⁱ)` 16-entry tables.

## 3. Datapath — `ops/math/cordic_hyp/fu_cordic_hyp.sv`
decode binary32 → Q4.28 (FTZ) → 16-step hyperbolic CORDIC (unrolled) → select
`op_sel ? cosh(X) : sinh(Y)` → encode Q4.28 → binary32 (RNE, FTZ). Latency-1
unary handshake. Same decode/encode as group 13.

## 4. Accuracy & verification
~16-bit accurate over |x| ≤ ~1.118. **Tolerance-based** TB: `|decode(dut) −
$sinh/$cosh(decode(x))| < TOL`; inputs in [−1.118, 1.118]; reports max error.

## 5. Generator + template
- `generator/templates/fu_cordic_hyp.sv.j2` (uses `params.width`, `op_list`). Add
  `"cordic_hyp"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@math.sinh, @math.cosh]`. Path `ops/math/cordic_hyp/`.
- `registry.yaml`: group 14 `status: not_started → verified`.

## 6. Python tests
- Add lookup + writes + golden for `cordic_hyp`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 15 (`fabric.op[@math.exp, @math.exp2, @math.expm1]`, exp_series).
