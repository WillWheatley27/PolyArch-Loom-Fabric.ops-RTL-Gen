# Design: Share Group 18 RTL (`fu_sqrt_rsqrt`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (shared LUT, both approximate — user choice). FINAL group.
**Scope:** Share group 18 (`sqrt_rsqrt` = `math.sqrt` / `math.rsqrt`). Approximate,
tolerance-verified. No simulatable loom reference (behavioral shortreal).

---

## 1. Goal
- `op_sel = 0` → `math.sqrt(x)`   = √x
- `op_sel = 1` → `math.rsqrt(x)`  = 1/√x

Rationale (group 18): *"Same Newton iteration; reciprocal is one extra division
step."* We implement the shared core as **two LUTs** (mantissa sqrt and rsqrt)
rather than Newton — simpler, lower-risk, consistent with groups 13–16/19. Noted
divergence from the registry's `iterations: 8` (advisory).

## 2. Approach — shared LUT + exponent split
For `x = 1.m · 2^e` write `e = 2q + r` (`q = e>>>1` floor-div, `r = e&1`):
- `sqrt(x)  = [SQRT_M(m)  · (r? √2   : 1)] · 2^q`
- `rsqrt(x) = [RSQRT_M(m) · (r? 1/√2 : 1)] · 2^(−q)`

`SQRT_M(m)`/`RSQRT_M(m)` are 129-entry LUTs over m∈[1,2) + linear interpolation,
Q.30. The `√2`/`1/√2` factor (Q.30 multiply) folds in the odd-exponent half.
Mantissa-factor `mf` (Q.30) is normalized to [1,2) (rsqrt's (0.5,1] needs one left
shift), then clz/RNE-encoded to binary32 with exponent `q (sqrt)` / `−q (rsqrt)`
(+ the normalize adjust + bias). Overflow→+Inf, underflow→+0. Result sign +.

## 3. Special cases
- NaN → NaN.
- `x < 0` (sign set, nonzero; incl −Inf) → NaN (both ops).
- `+Inf` → sqrt: +Inf; rsqrt: +0.
- zero (E==0, FTZ ±0/subnormal) → sqrt: `{s,0}` (sqrt(−0)=−0); rsqrt: `s? −Inf : +Inf`.

## 4. Accuracy & verification
LUT+interp ~1e-5; the √2 multiply adds a touch of rounding. **Tolerance** TB:
`|dut − ref| ≤ 1e-3·|ref| + tiny` vs `$sqrt(x)` and `1.0/$sqrt(x)`. Random x over a
wide positive range (incl. <1 and >1, even/odd exponents); directed perfect
squares + specials by exact bits. Reports worst-case relative error.

## 5. Generator + template
- `generator/templates/fu_sqrt_rsqrt.sv.j2` (embeds SQRT_M, RSQRT_M, √2/1/√2). Add
  `"sqrt_rsqrt"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@math.sqrt, @math.rsqrt]`. Path `ops/math/sqrt_rsqrt/`.
- `registry.yaml`: group 18 `status: not_started → verified`.

## 6. Testbench — `tb/math/sqrt_rsqrt/tb_fu_sqrt_rsqrt.sv`
Unary, latency-1, 1-bit `op_sel`. Directed (sqrt/rsqrt of 1,4,2,0.25,1e6,small;
specials: 0, −1, +Inf) + random within TOL; handshake corners.

## 7. Python tests
- Add lookup + writes + golden for `sqrt_rsqrt`.
- **This completes all 19 groups.** The stale `test_generate_unimplemented_group_raises`
  is replaced with a test asserting an out-of-group/cross-group op string still
  raises (e.g. `fabric.op[@math.sqrt, @math.sin]` → ShareGroupError), since no
  unimplemented valid group remains.
