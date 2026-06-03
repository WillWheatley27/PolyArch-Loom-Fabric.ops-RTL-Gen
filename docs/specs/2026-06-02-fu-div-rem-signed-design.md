# Design: Share Group 2 RTL (`fu_div_rem_signed`) + Generator Wiring

**Date:** 2026-06-02
**Status:** Approved design (brainstormed with user), pending implementation
**Scope:** Add share group 2 (`div_rem_signed` = `arith.divsi` / `arith.remsi`)
as a full end-to-end vertical slice, mirroring the group-1 deliverable:
RTL module + self-checking testbench + Jinja2 template + generator wiring +
Python tests + sim-verification + docs.

This reuses the existing `fabric_gen` pipeline unchanged (parse → validate →
registry lookup → render → write); the only generator change is registering the
new template in `_TEMPLATE_MAP`.

---

## 1. Goal

Produce one synthesizable, simulatable SystemVerilog module that implements
share group 2 as a **single shared-datapath block** selectable at runtime via an
`op_sel` config knob:

- `op_sel = 0` → `arith.divsi` (`out = signed(a) / signed(b)`, quotient tap)
- `op_sel = 1` → `arith.remsi` (`out = signed(a) % signed(b)`, remainder tap)

faithful to the share-group rationale: *"Quotient and remainder fall out of the
same signed long-division iteration."* (`docs/fabric_hardware_share_groups.md`,
group 2). One physical iterating divider; `op_sel` selects which tap drives the
output.

The flow must be **(1) simulatable** (Verilator / VCS) and **(2) synthesizable**
(loom's synthesizable subset — no `/` or `%` operators in the datapath).

## 2. Context and references

- Registry entry (source of truth): `registry.yaml` group 2 —
  `name: div_rem_signed`, `family: int_arith`,
  `ops: [arith.divsi, arith.remsi]`, `rtl_module: fu_div_rem_signed.sv`,
  `params: {width: 32}`. Status moves `not_started → verified`.
- RTL conventions mirrored from loom (read-only reference at `/edata1/mykol/loom`):
  - `src/rtl/design/arith/fu_op_divsi.sv`, `fu_op_remsi.sv` — the multi-cycle
    restoring-division FSM this design merges. Both use an **identical**
    iteration; they differ only in sign fix-up and output tap, which is exactly
    what `op_sel` selects.
  - Standard FU handshake: `in_data_N/in_valid_N/in_ready_N` per operand,
    `out_data/out_valid/out_ready`, `WIDTH` parameter.

## 3. Key contrast with group 1

Group 1 (`fu_add_sub`) is combinational, latency 0, with a trivial 2-input join
handshake (`out_valid = in_valid_0 & in_valid_1`). Group 2 is **multi-cycle**:
a restoring-division state machine. `clk`/`rst_n` are real (no longer lint-waived
as unused), and the handshake is FSM-driven.

## 4. RTL design — `ops/int_arith/div_rem_signed/fu_div_rem_signed.sv`

### 4.1 Interface

Same port shape as group 1 + loom:

```
module fu_div_rem_signed #(parameter int unsigned WIDTH = 32) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              op_sel,     // 0 = divsi (quotient), 1 = remsi (remainder)
  input  logic [WIDTH-1:0]  in_data_0,  // dividend a
  input  logic              in_valid_0,
  output logic              in_ready_0,
  input  logic [WIDTH-1:0]  in_data_1,  // divisor b
  input  logic              in_valid_1,
  output logic              in_ready_1,
  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);
```

### 4.2 FSM and handshake

- States `ST_IDLE → ST_COMPUTE → ST_DONE`. Intrinsic latency `WIDTH+2`.
- Non-pipelined: one operation in flight. `in_ready_*` asserted only in
  `ST_IDLE` when both inputs are valid; operands are **captured at accept** (the
  producer may drop `in_data` afterward). `out_valid` asserted in `ST_DONE`;
  unit returns to `ST_IDLE` on `out_ready`.

### 4.3 Datapath (shared restoring division)

- Compute `|a|`, `|b|` at accept. Working registers: `quo_mag_r` (dividend shift
  source that accumulates the quotient magnitude), `rem_acc_r` (WIDTH+1-bit
  partial remainder), `divisor_r = |b|`, and two sign-fix-up flags.
- Each of `WIDTH` iterations: shift the partial remainder left bringing in the
  next dividend bit, trial-subtract the divisor, set the quotient bit and either
  keep the subtraction (fits) or restore.
- After the iteration, quotient magnitude is in `quo_mag_r` and remainder
  magnitude in `rem_acc_r[WIDTH-1:0]`.
- Sign fix-up at the output taps:
  - `negate_q = a_neg ^ b_neg` (quotient sign)
  - `negate_r = a_neg` (remainder sign follows dividend — C / MLIR semantics)
  - `quo_signed = negate_q ? -quo_mag : quo_mag`
  - `rem_signed = negate_r ? -rem_mag : rem_mag`
- Output mux: `out_data = op_sel ? rem_signed : quo_signed`.

### 4.4 Edge-case semantics (RISC-V M-extension)

Deterministic, testbench-checked. **This deliberately diverges from loom's
`fu_op_divsi`/`fu_op_remsi`, which return 0 on divide-by-zero.**

- `b == 0`: quotient = `-1` (all ones), remainder = dividend `a`. Implemented as
  an `ST_IDLE → ST_DONE` fast-path that loads the standard output formula to
  produce these values (quotient magnitude `1` with `negate_q = 1` → `-1`;
  remainder magnitude `|a|` with `negate_r = a_neg` → `a`). No extra registers.
- `INT_MIN / -1`: quotient = `INT_MIN`, remainder = `0`. **No special case** —
  the restoring datapath naturally produces magnitude `2^(WIDTH-1)` which, with
  `negate_q = 0`, is the bit pattern `INT_MIN`; remainder is `0`. Verified by
  hand for WIDTH=4 and exercised explicitly in the testbench.

## 5. Generator + template

- New template `generator/templates/fu_div_rem_signed.sv.j2` — the §4 module with
  `{{ module_name }}`, `{{ width }}`, and the `op_sel` comment derived from
  `op_list` (canonical order `[arith.divsi, arith.remsi]`, same style as group 1).
- `generator.py`: add `"div_rem_signed": "fu_div_rem_signed.sv.j2"` to
  `_TEMPLATE_MAP`. No other generator changes.
- The committed golden `ops/int_arith/div_rem_signed/fu_div_rem_signed.sv` is the
  generator's own output for `fabric.op[@arith.divsi, @arith.remsi]`, so the
  golden-file test is exact by construction.

## 6. Testbench — `tb/int_arith/div_rem_signed/tb_fu_div_rem_signed.sv`

Self-checking, multi-cycle, parameterized by `WIDTH`. Drives operands + `op_sel`,
waits for `out_valid` (not a fixed delay), compares to a golden model, completes
the output handshake.

- Golden model: native `$signed(a)/$signed(b)` and `$signed(a)%$signed(b)`
  (both truncate toward zero / remainder follows dividend, matching divsi/remsi),
  with the `b==0` RISC-V result substituted.
- Coverage: directed corners (zero, ±1, max, min, all four sign quadrants,
  `b==0` variants, `INT_MIN/-1`, `INT_MIN/1`, `|a|<|b|`, `op_sel` toggle on
  identical operands); handshake corners (backpressure: `out_valid` holds and
  `in_ready` stays low while `out_ready=0`; no accept while `in_valid` low);
  randomized vectors for both `op_sel` values.

## 7. Python tests (`tests/`)

- Add: registry lookup for `div_rem_signed`; `generate(...)` writes
  `fu_div_rem_signed.sv`; golden-file match against the committed RTL.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.divsi, @arith.remsi]` (now implemented). Repoint it to a
  still-unimplemented group — group 3, `fabric.op[@arith.divui, @arith.remui]`.

## 8. Verification

- `demo_div_rem_signed.sh` mirroring `demo.sh`: generate → `verilator --lint-only`
  → `verilator --binary --timing` → run TB → assert `PASS:`. Run at `WIDTH=32`
  and `WIDTH=8`. Verilator obtained via `module load verilator/5.044`.

## 9. Supported input strings (for reference)

Only the two-member combination generates this module (registry lookup is
exact-set):

- ✅ `fabric.op[arith.divsi, arith.remsi]` / `fabric.op[@arith.divsi, @arith.remsi]`
  (+ whitespace / order variants)
- `fabric.op[arith.divsi]` or `[arith.remsi]` alone → validates as group 2 but
  `RegistryError` (no singleton entry), same as group 1.
- Cross-group multi-member (e.g. `divsi, addi` or `divsi, remui`) → `ShareGroupError`.
- Malformed / unwrapped → `ParseError`.
