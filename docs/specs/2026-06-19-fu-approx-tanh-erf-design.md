# Design: Share Group 19 RTL (`fu_approx_tanh_erf`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (LUT + linear interpolation; approximate-transcendental
pattern), pending impl
**Scope:** Share group 19 (`approx_tanh_erf` = `math.tanh` / `math.erf`).
Approximate (~LUT-accuracy), tolerance-verified, range-limited. No loom reference.

---

## 1. Goal
- `op_sel = 0` → `math.tanh(x)`
- `op_sel = 1` → `math.erf(x)`
Both are odd sigmoids in (-1, 1), saturating to ±1.

Rationale (group 19): *"Same Pade or LUT-based approximation core within shared
input ranges."* One shared LUT-address + linear-interpolation datapath; `op_sel`
selects the tanh vs erf table.

## 2. Approach — shared LUT + linear interpolation
- **Odd symmetry:** compute `f(|x|)`, then apply the sign of x.
- **Table:** 129 entries per function at `x = k/32`, `k = 0..128` (i.e. step
  Δ = 2⁻⁵ over `[0, 4]`), stored Q1.23 (×2²³, values in [0,1]). Computed exactly
  (Python `math.tanh`/`math.erf`) and embedded as localparam ROMs `TANH_T`/`ERF_T`.
- **Index/interp:** decode binary32 `|x|` to `u = |x|·32` in Q8.16 (`u = sig >>
  (129-e)`). `index = u[22:16]` (0..127), `frac = u[15:0]`. Linear interp:
  `f = t0 + (frac·(t1−t0)) >> 16`, where `t0=T[index]`, `t1=T[index+1]`.
- **Saturate:** `|x| ≥ 4` (or exp > 129) → `f = T[128]` (= tanh(4)=0.99933 /
  erf(4)≈1.0). Larger |x| out of scope as a *value* but handled (flat saturate).
- **Encode** magnitude (Q1.23, value = mag·2⁻²³) → binary32 (clz normalize + RNE),
  sign = x[31]. FTZ on underflow.
- **Latency-1**, unary handshake.

## 3. Accuracy & verification
Linear interp over Δ=2⁻⁵ gives ~Δ²·max|f''|/8 ≈ a few ×10⁻⁴; saturation beyond
x=4 adds ≤ ~7×10⁻⁴ (tanh). **Tolerance-based** TB: tanh checked vs Verilator
`$tanh`; erf vs an Abramowitz-Stegun 7.1.26 reference (~1.5e-7, independent of the
DUT LUT). `|decode(dut) − ref| < TOL`; reports max error.

## 4. Generator + template
- `generator/templates/fu_approx_tanh_erf.sv.j2` (uses `params.width`, `op_list`;
  embeds the two ROMs). Add `"approx_tanh_erf"` to `_TEMPLATE_MAP`. Golden =
  output for `fabric.op[@math.tanh, @math.erf]`. Path `ops/math/approx_tanh_erf/`.
- `registry.yaml`: group 19 `status: not_started → verified`.

## 5. Testbench — `tb/math/approx_tanh_erf/tb_fu_approx_tanh_erf.sv`
Unary, latency-1. Directed (0, ±0.5, ±1, ±2, ±4, ±5, small) + random x ∈ [−5, 5]
vs `$tanh` / A&S-erf within TOL; handshake corners. Reports worst-case error.

## 6. Python tests
- Add lookup + writes + golden for `approx_tanh_erf`.
- This is the **last** wired group; the stale `test_generate_unimplemented_group_raises`
  is repointed to a still-unimplemented group (group 15, exp_series).
