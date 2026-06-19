# Design: Share Group 10 RTL (`fu_fp_add_sub`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (structural, FTZ subnormals — user choice), pending impl
**Scope:** Share group 10 (`fp_add_sub` = `arith.addf` / `arith.subf`). First FP
**arithmetic**: a structural IEEE-754 binary32 adder/subtractor. 2-input,
latency-1.

---

## 1. Goal
- `op_sel = 0` → `arith.addf` (`a + b`)
- `op_sel = 1` → `arith.subf` (`a - b`) = `addf` with operand B's sign flipped.

Rationale (group 10): *"Floating-point adder with sign invert on operand B."*

## 2. Why structural + FTZ
loom's addf/subf are behavioral `$bitstoshortreal` + real add (Verilator can't
run `shortreal`). So this is a **structural** binary32 adder. Per user decision,
**subnormals are flushed to zero (FTZ)**: subnormal inputs (`exp==0, mant!=0`)
are treated as signed zero, and any result in the subnormal range underflows to
signed zero. Normal range is full IEEE-754 with round-to-nearest-even. (Diverges
from strict IEEE only for `|x| < 2^-126`.)

## 3. Datapath — `ops/fp_arith/fp_add_sub/fu_fp_add_sub.sv`
Combinational core + latency-1 register; 2-input join handshake
(`fire = in_valid_0 & in_valid_1 & (~out_valid | out_ready)`).

1. **subf**: flip `in_data_1[31]` when `op_sel=1`.
2. **Unpack** sign/exp/mant; `is_nan/inf`; FTZ-zero = `exp==0`. Significand
   `{1'b1, mant}` (normal).
3. **Special cases (priority):** NaN in → qNaN `0x7FC00000`; `Inf+Inf`
   (same sign → that Inf, opposite → qNaN); one Inf → that Inf; both zero →
   `{sa&sb, 0}` (+0 unless both −0); one zero → the other operand.
4. **Both normal:** pick larger-magnitude operand (`big`) by (exp, then mant);
   `diff = |ea-eb|`. Align `small` significand right by `diff` (capped) into a
   28-bit field, collecting **guard/sticky**. `add_op = (signs equal)`.
   `raw = add_op ? big+small_aligned : big-small_aligned` (big ≥ small ⇒ ≥0).
5. **Normalize:** add-carry → `>>1`, exp+1; subtract → leading-one count, `<<`,
   exp−shift; exact cancellation (`raw==0`) → `+0`.
6. **Round (RNE):** `round_up = guard & (sticky | mant_lsb)`; mantissa-overflow
   → exp+1.
7. **Range:** biased exp `≥255` → Inf (sign); `≤0` → FTZ signed zero; else pack.

Hand-verified: `1+1=2`, `1+0.5=1.5`, `1.5−1=0.5`, `2²⁴+1→2²⁴` (tie→even),
`2²⁴+3→2²⁴+4`, `5+(−5)=+0`.

## 4. Generator + template
- New template `generator/templates/fu_fp_add_sub.sv.j2` (uses `params.width`,
  `op_list`; `{N{..}}` replications only, no `{{`-collision). Add `"fp_add_sub"`
  to `_TEMPLATE_MAP`. Golden = output for `fabric.op[@arith.addf, @arith.subf]`.
- `registry.yaml`: group 10 `status: not_started → verified`. Lives under a new
  `ops/fp_arith/` / `tb/fp_arith/` family path (family `fp_arith`).

## 5. Testbench — `tb/fp_arith/fp_add_sub/tb_fu_fp_add_sub.sv`
2-input latency-1. Layers:
1. **Directed exact** hand-computed vectors: basic add/sub, RNE ties, signed
   zeros, cancellation, Inf/NaN/Inf−Inf, overflow→Inf, underflow→0; both op_sel.
2. **Randomized correct-rounding property:** decode both inputs to `real`,
   compute `true = da ± db`; classify (NaN/Inf/overflow/underflow) for exact
   checks, else decode DUT output and require `|dec − true| ≤ half_ULP` (the
   double-rounding-safe property for a single add). Operands generated with
   moderate, overlapping exponents to exercise alignment, cancellation, rounding.
3. **Handshake corners:** 2-input join latency-1 timing, backpressure, no-accept.

## 6. Verification
`demos/demo_fp_add_sub.sh`: generate → `verilator --lint-only -Wall` → build+run
TB → `PASS:`.

## 7. Python tests
- Add lookup + writes + golden for `fp_add_sub`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 11 (`fabric.op[@arith.divf, @arith.remf]`, fp_div_rem).
