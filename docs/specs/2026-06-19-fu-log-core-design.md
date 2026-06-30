# Design: Share Group 16 RTL (`fu_log_core`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (LUT log2(m) core; log1p = log(1+x)), pending impl
**Scope:** Share group 16 (`log_core` = `math.log` / `math.log2` / `math.log10`
/ `math.log1p`). Approximate, tolerance-verified. No loom reference. 4 members
→ 2-bit `op_sel`.

---

## 1. Goal
- `op_sel = 0` → `math.log(x)`   = ln(x)
- `op_sel = 1` → `math.log2(x)`
- `op_sel = 2` → `math.log10(x)`
- `op_sel = 3` → `math.log1p(x)` = ln(1+x)

Rationale (group 16): *"Same logarithm core; output multiplier and pre-bias
differ."*

## 2. Approach — shared log2 core
For `x = 2^e · m` (m ∈ [1,2)): `log2(x) = e + log2(m)`. `e` = unbiased float
exponent; `log2(m) ∈ [0,1)` from a 129-entry LUT + linear interp (Q2.30).
- `log2`: result = log2core.
- `log`: result = log2core · ln2.
- `log10`: result = log2core · (1/log2(10)).
- `log1p`: `V = fp_add(x, 1.0)` (inline group-10 adder), then the log (ln) path
  on V.

**Datapath:** decode binary32 (handle specials first) → `log2core` (signed
Q6.26: range roughly [−127, 128]) = `{e as Q.0} + LUT_log2(m)` → multiply by the
op's Q2.30 scale (`1.0`, `ln2`, or `1/log2(10)`) → encode signed fixed-point →
binary32 (sign, clz-normalize, RNE). Latency-1, unary.

## 3. Special cases (IEEE/libm)
- `x` is NaN → NaN; `x < 0` (sign set, nonzero) → NaN (`0x7FC00000`).
- `x = +0` or `−0` → `−Inf` (`0xFF800000`).
- `x = +Inf` → `+Inf`.
- `x = 1.0` → `+0` (falls out: e=0, log2(m=1)=0).
- `log1p`: domain is `1+x`; `x = −1` → `−Inf`; `x < −1` → NaN. These are produced
  naturally by running the log path on `V = fp_add(x,1.0)` (V=0→−Inf, V<0→NaN).

## 4. Accuracy & verification
~LUT accuracy (Δ=2⁻⁷, log2(m) smooth → ~1e-5). log1p relative accuracy near 0
limited (1+x rounding) — documented; absolute-accurate. TB tolerance
`|dut − ref| ≤ 1e-3·|ref| + 1e-4` vs `$ln`, `$log10`, `log2 = $ln/ln2`,
`log1p = $ln(1+x)`. Random x ∈ (0, 1e6] for log*, x ∈ (−0.9, 1e3] for log1p;
directed specials by exact bits.

## 5. Generator + template
- `generator/templates/fu_log_core.sv.j2` (embeds LN2, INVLOG2_10, LOG2_M ROM,
  inline fp_add). Add `"log_core"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]`. Path
  `ops/math/log_core/`.
- `registry.yaml`: group 16 `status: not_started → verified`.

## 6. Testbench — `tb/math/log_core/tb_fu_log_core.sv`
Unary, latency-1. Directed (1→0 all bases, log2(2)=1, log2(8)=3, log(e)≈1,
log10(100)=2, log1p(0)=0, log(0)=−Inf, log(−1)=NaN, log(Inf)=Inf, log1p(−1)=−Inf)
+ random within TOL; handshake. Reports worst-case relative error.

## 7. Python tests
- Add lookup + writes + golden for `log_core`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 17 (`fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]`).
