# Design: Share Group 11 RTL (`fu_fp_div_rem`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (full divf + full fmod remf — user choice), pending impl
**Scope:** Share group 11 (`fp_div_rem` = `arith.divf` / `arith.remf`). The hardest
unit: a multi-cycle structural FP divider sharing a restoring-division core
between IEEE binary32 divide and floating-point remainder (fmod).

---

## 1. Goal
- `op_sel = 0` → `arith.divf` (`a / b`, RNE).
- `op_sel = 1` → `arith.remf` = **fmod** (`a − b·trunc(a/b)`, sign of dividend;
  fixed by MLIR/LLVM `frem`). NOT IEEE `remainder`.

Rationale (group 11): *"Same iteration core; remainder is the divisor-multiply
residue."* loom has `fu_op_divf` (behavioral shortreal → unsimulatable) and
**no `remf` RTL** — remf is designed from scratch.

## 2. Approach (structural, FTZ, multi-cycle)
Verilator can't run loom's `shortreal`, so structural. Subnormals **FTZ**
(consistent with group 10). 2-input join, multi-cycle FSM (variable latency).
Shared 25-bit remainder register + subtract/compare datapath.

### divf (fixed ~27 iterations)
- `Q = floor(sig_a · 2²⁷ / sig_b)` via 27 restoring iterations (rem<<1; q=rem≥D;
  if q rem−=D; Q=(Q<<1)|q). `Q ∈ [2²⁶, 2²⁸)`.
- Normalize: leading 1 at bit 27 (`Q[27]`) or 26 → shift; `exp = ea−eb (or −1)`.
- Round-to-nearest-even from `mant=normQ[26:4]`, `guard=normQ[3]`,
  `sticky = normQ[2:0] | (rem≠0)`. Range → Inf / FTZ. Sign `sa^sb`.
- Special: NaN; Inf/Inf→NaN; Inf/x→Inf; x/Inf→0; x/0→Inf; 0/0→NaN; 0/x→0.

### remf = fmod (variable iterations)
- Special: NaN; fmod(x,0)→NaN; fmod(Inf,y)→NaN; fmod(x,Inf)→x; fmod(0,b)→0.
- If `|a| < |b|` → result = a (passthrough).
- Else: `rem = (sig_a≥sig_b)?sig_a−sig_b:sig_a`; then `(ea−eb)` iterations
  (rem<<1; if rem≥sig_b rem−=sig_b). Final `rem = (sig_a<<(ea−eb)) mod sig_b`.
- Normalize `rem` (leading-one count) → significand; `exp = eb − clz`; FTZ if
  underflow; sign = `sa`. fmod is exact (no rounding). `rem==0` → signed zero.
- Hand-verified: `fmod(3,2)=1.0`, `fmod(5,3)=2.0`.

## 3. FSM
`ST_IDLE` (accept + special/passthrough/setup) → `ST_CALC` (one shift-subtract per
cycle; divf builds Q, remf updates rem; `cnt` counts down) → on `cnt==0` compute
final (normalize/round) and register → `ST_DONE` (out_valid; drain on out_ready).
`in_ready_* = (state==IDLE) & in_valid_0 & in_valid_1`.

## 4. Generator + template
- `generator/templates/fu_fp_div_rem.sv.j2` (uses `params.width`, `op_list`).
  Add `"fp_div_rem"` to `_TEMPLATE_MAP`. Golden = output for
  `fabric.op[@arith.divf, @arith.remf]`. Family path `ops/fp_arith/fp_div_rem/`.
- `registry.yaml`: group 11 `status: not_started → verified`.

## 5. Testbench — `tb/fp_arith/fp_div_rem/tb_fu_fp_div_rem.sv`
Multi-cycle (wait for out_valid). Layers:
1. **Directed exact**: divf (2/2=1, 1/2=0.5, 3/2, RNE cases, x/0=Inf, 0/0=NaN,
   Inf/2, 2/Inf=0, NaN); remf (fmod(3,2)=1, fmod(5,3)=2, fmod(7,3)=1,
   fmod(−7,3)=−1, fmod(2,5)=2, fmod(x,0)=NaN, fmod(Inf,y)=NaN, fmod(x,Inf)=x).
2. **Random oracle**: decode operands to real. divf → `|dec − da/db| ≤ half_ULP`.
   remf → exact `fmod` computed via `da − db·$rtoi(da/db)` (random constrained to
   modest exponent gaps so the integer quotient fits/exact); checks
   `dut == fmod` exactly.
3. **Handshake**: multi-cycle accept/out_valid timing, backpressure.

## 6. Verification
`demos/demo_fp_div_rem.sh`: generate → `verilator --lint-only -Wall` → build+run
TB → `PASS:`.

## 7. Python tests
- Add lookup + writes + golden for `fp_div_rem`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 12 (`fabric.op[@arith.minimumf, @arith.maximumf]`, fp_min_max).
