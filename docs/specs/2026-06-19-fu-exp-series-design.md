# Design: Share Group 15 RTL (`fu_exp_series`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (LUT 2^f core; expm1 = exp−1), pending impl
**Scope:** Share group 15 (`exp_series` = `math.exp` / `math.exp2` / `math.expm1`).
Approximate, tolerance-verified. No loom reference. 3 members → 2-bit `op_sel`.

---

## 1. Goal
- `op_sel = 0` → `math.exp(x)` = eˣ
- `op_sel = 1` → `math.exp2(x)` = 2ˣ
- `op_sel = 2` → `math.expm1(x)` = eˣ − 1

Rationale (group 15): *"Same exponential series core; arguments and
post-corrections differ."*

## 2. Approach — shared 2^f core
- exp2 is the natural core: `2^y`, `y = n + f` (n = floor(y), f ∈ [0,1)). `n`
  drives the float exponent; `2^f ∈ [1,2)` is the significand.
- `exp`: same core with `y = x·log₂e` (pre-scale by LOG2E ≈ 1.4427, Q2.30).
- `expm1`: same as exp, then `−1` post-correction.

**Datapath:** decode binary32 x → Q10.22 fixed-point → pre-scale (×log₂e for
exp/expm1) → split `n`/`f` → `2^f` via 129-entry LUT + linear interp (Q1.23,
~7e-6) → assemble `V = {0, n+127, mant}` with **overflow→+Inf / underflow→+0**
clamping. `expm1` = `V + (−1.0)` via an **inline copy of the verified group-10
IEEE-754 FP adder** (handles V=Inf→Inf, V=0→−1, normal V→V−1). Latency-1, unary.

## 3. Accuracy & verification
exp/exp2: ~7e-6 relative (LUT interp dominated). expm1: absolute-accurate;
**relative accuracy degrades for tiny x** (exp−1 cancellation) — documented.
TB tolerance combines relative + an absolute floor: `|dut − ref| ≤ 1e-3·|ref| +
1e-4`. References: `$exp`, `2.0**x`, `$exp(x)−1`. Inputs in [−30, 30] (avoids the
Inf region); directed overflow/underflow corners.

## 4. Generator + template
- `generator/templates/fu_exp_series.sv.j2` (embeds LOG2E + the 2^f ROM + an
  inline fp_add). Add `"exp_series"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@math.exp, @math.exp2, @math.expm1]`. Path `ops/math/exp_series/`.
- `registry.yaml`: group 15 `status: not_started → verified`.

## 5. Testbench — `tb/math/exp_series/tb_fu_exp_series.sv`
Unary, latency-1. Directed (0, ±1, ±2, 0.5, ±10, overflow x=100→Inf,
underflow x=−100→0/−1) + random x ∈ [−30, 30] for all three ops within TOL;
handshake. Reports worst-case relative error.

## 6. Python tests
- Add lookup + writes + golden for `exp_series`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 16 (`fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]`).
