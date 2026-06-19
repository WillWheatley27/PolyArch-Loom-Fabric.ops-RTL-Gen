# Design: Share Group 12 RTL (`fu_fp_min_max`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (replicates established pattern; combinational), pending impl
**Scope:** Share group 12 (`fp_min_max` = `arith.minimumf` / `arith.maximumf`).
FP minimum/maximum. Combinational, latency 0.

---

## 1. Goal
- `op_sel = 0` → `arith.minimumf(a, b)`
- `op_sel = 1` → `arith.maximumf(a, b)`

IEEE-754-2019 `minimum`/`maximum` semantics (what MLIR `arith.minimumf`/
`maximumf` use): **NaN-propagating** (either operand NaN → NaN), and
**−0.0 < +0.0** (so `minimumf(−0,+0) = −0`, `maximumf(−0,+0) = +0`). Note these
are the NaN-*propagating* variants, distinct from `minnumf`/`maxnumf`.

Rationale (group 12): *"Floating-point comparator with one output-mux control."*

## 2. Approach (combinational, no FTZ)
loom's `fu_op_minimumf` is latency-0. Min/max selects one input **verbatim**, so
no arithmetic/rounding and **no FTZ** — subnormals and Inf pass through correctly;
only NaN is special.

**Monotonic-key compare** (total order in one unsigned `<`):
`key(x) = x ^ (x[31] ? 32'hFFFFFFFF : 32'h80000000)`. Then `a_lt_b = key(a) <
key(b)` (unsigned) gives the IEEE total order, including `−0 < +0`
(`key(−0)=0x7FFFFFFF < key(+0)=0x80000000`) and `−Inf < … < +Inf`. Verified on
sign quadrants, ±0, ±Inf.

## 3. RTL — `ops/fp_arith/fp_min_max/fu_fp_min_max.sv`
Combinational, 2-input join handshake (`out_valid = in_valid_0 & in_valid_1`,
`in_ready_* = out_ready & out_valid`), `clk`/`rst_n` unused (lint-waived).
```
a_nan = (ea==0xFF)&|ma; b_nan = (eb==0xFF)&|mb;
keya = in_data_0 ^ (in_data_0[31] ? 32'hFFFFFFFF : 32'h80000000);
keyb = in_data_1 ^ (in_data_1[31] ? 32'hFFFFFFFF : 32'h80000000);
a_lt_b = keya < keyb;                          // unsigned, total order
out = (a_nan|b_nan) ? 32'h7FC00000              // qNaN
    : op_sel ? (a_lt_b ? in_data_1 : in_data_0) // maximumf
             : (a_lt_b ? in_data_0 : in_data_1);// minimumf
```

## 4. Generator + template
- `generator/templates/fu_fp_min_max.sv.j2` (uses `params.width`, `op_list`; no
  `{{`-collision). Add `"fp_min_max"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@arith.minimumf, @arith.maximumf]`. Path `ops/fp_arith/fp_min_max/`.
- `registry.yaml`: group 12 `status: not_started → verified`.

## 5. Testbench — `tb/fp_arith/fp_min_max/tb_fu_fp_min_max.sv`
Combinational (like group 6/7). Directed exact: sign quadrants, ±0
(`min(−0,+0)=−0`, `max=+0`), NaN (either operand → NaN), ±Inf, equal operands.
Random: normal operands (exp ∈ [1,254]) compared via `real` decode →
`min = (da<db)?a:b`, `max = (da<db)?b:a` (bit-exact). Handshake corners
(backpressure, input-invalid).

## 6. Verification
`demos/demo_fp_min_max.sh`: generate → `verilator --lint-only -Wall` → build+run
TB → `PASS:`.

## 7. Python tests
- Add lookup + writes + golden for `fp_min_max`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 13 (`fabric.op[@math.sin, @math.cos]`, cordic_trig).
