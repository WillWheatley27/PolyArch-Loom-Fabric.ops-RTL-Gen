# Design: Share Group 3 RTL (`fu_div_rem_unsigned`) + Generator Wiring

**Date:** 2026-06-04
**Status:** Approved (replicates the group-2 pattern for unsigned), pending impl
**Scope:** Add share group 3 (`div_rem_unsigned` = `arith.divui` / `arith.remui`)
as a full end-to-end slice, mirroring groups 1 and 2: RTL module + self-checking
testbench + Jinja2 template + generator wiring + Python tests + sim-verification
+ docs.

This is the **unsigned counterpart of group 2** (`fu_div_rem_signed`). The
generator pipeline is unchanged; the only generator change is one `_TEMPLATE_MAP`
entry.

---

## 1. Goal

One synthesizable, simulatable SystemVerilog module implementing share group 3 as
a single shared restoring-division datapath, selectable via `op_sel`:

- `op_sel = 0` → `arith.divui` (`out = a / b`, unsigned, quotient tap)
- `op_sel = 1` → `arith.remui` (`out = a % b`, unsigned, remainder tap)

faithful to the share-group rationale: *"Unsigned counterpart of group 2."*
(`docs/fabric_hardware_share_groups.md`, group 3).

## 2. Relationship to group 2

Identical to `fu_div_rem_signed` **minus all sign handling**:
- No absolute-value preprocessing — the dividend/divisor go straight into the
  datapath.
- No sign fix-up registers (`negate_q`/`negate_r`) — quotient and remainder are
  output directly.
- Same restoring-division iteration, same FSM (`IDLE → COMPUTE → DONE`), same
  latency (`WIDTH+2`), same non-pipelined handshake, same `op_sel` output mux.

Loom references: `src/rtl/design/arith/fu_op_divui.sv`, `fu_op_remui.sv` (which
share the same iteration; divui outputs `quotient_r`, remui outputs
`remainder_r[WIDTH-1:0]`).

## 3. RTL design — `ops/int_arith/div_rem_unsigned/fu_div_rem_unsigned.sv`

### 3.1 Interface
Same port shape as group 2 (`clk`, `rst_n`, `op_sel`, two input channels, one
output channel, `parameter WIDTH=32`). `op_sel`: 0 = divui (quotient), 1 = remui
(remainder).

### 3.2 FSM / datapath
- `ST_IDLE → ST_COMPUTE (WIDTH iters) → ST_DONE`, latency `WIDTH+2`,
  non-pipelined. `in_ready_*` only in IDLE; operands captured at accept;
  `out_valid` in DONE; return to IDLE on `out_ready`.
- Working registers: `quo_mag_r` (dividend shift source → quotient), `rem_acc_r`
  (WIDTH+1-bit partial remainder), `divisor_r`. **No sign registers.**
- Each iteration: shift the partial remainder left bringing in the next dividend
  bit, trial-subtract the divisor, set the quotient bit, keep-or-restore.
- Output: `quo_out = quo_mag_r`; `rem_out = rem_acc_r[WIDTH-1:0]`;
  `out_data = op_sel ? rem_out : quo_out`.

### 3.3 Edge case (RISC-V M-extension, unsigned)
Only divide-by-zero exists for unsigned (no signed overflow case). Deterministic,
testbench-checked. **Diverges from loom**, which returns 0:
- `b == 0`: quotient = all-ones (`2^WIDTH − 1`, max unsigned); remainder =
  dividend `a`. Implemented as an `IDLE → DONE` fast-path
  (`quo_mag = {WIDTH{1'b1}}`, `rem_acc = {1'b0, a}`).

## 4. Generator + template
- New template `generator/templates/fu_div_rem_unsigned.sv.j2`. Note: with no
  two's-complement `~x+1` term, there is **no Jinja `{{` collision** — the
  template needs no `WIDTH'(1)` workaround for that (the counter still uses
  `CNT_WIDTH'(1)`).
- `generator.py`: add `"div_rem_unsigned": "fu_div_rem_unsigned.sv.j2"` to
  `_TEMPLATE_MAP`.
- Committed golden = generator output for `fabric.op[@arith.divui, @arith.remui]`.
- `registry.yaml`: group 3 `status: not_started → verified`.

## 5. Testbench — `tb/int_arith/div_rem_unsigned/tb_fu_div_rem_unsigned.sv`
Self-checking, multi-cycle, parameterized by `WIDTH`. Mirrors group 2's TB but the
golden model uses native **unsigned** `/` and `%` with the `b==0` RISC-V result
(quotient all-ones, remainder = dividend). Coverage: directed corners (0, 1, max
unsigned, `|a|<|b|`, `b==0` variants, `op_sel` toggle), handshake corners
(backpressure, no-accept), randomized vectors for both `op_sel` values.

## 6. Python tests
- Add: registry lookup for `div_rem_unsigned`; `generate(...)` writes the file;
  golden-file match.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.divui, @arith.remui]` (now implemented). Repoint it to group 4
  (`fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]`, barrel_shift).

## 7. Verification
`demo_div_rem_unsigned.sh` mirroring the group-2 demo: generate → lint → sim at
`WIDTH=32` and `WIDTH=8` → assert `PASS:`.
