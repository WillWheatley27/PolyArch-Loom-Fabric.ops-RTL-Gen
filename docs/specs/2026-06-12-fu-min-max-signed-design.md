# Design: Share Group 6 RTL (`fu_min_max_signed`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (replicates the established per-group pattern), pending impl
**Scope:** Add share group 6 (`min_max_signed` = `arith.minsi` / `arith.maxsi`)
as a full end-to-end slice, mirroring groups 1-5.

The generator pipeline is unchanged; the only generator change is one
`_TEMPLATE_MAP` entry.

---

## 1. Goal

One synthesizable, simulatable SystemVerilog module implementing share group 6 as
a single shared signed comparator, selectable via a 1-bit `op_sel`:

- `op_sel = 0` → `arith.minsi` (`out = signed-min(a, b)`)
- `op_sel = 1` → `arith.maxsi` (`out = signed-max(a, b)`)

faithful to the share-group rationale: *"One signed comparator; min vs max is a
single output mux on the result."* (`docs/fabric_hardware_share_groups.md`,
group 6).

## 2. Relationship to prior groups

**Combinational, latency 0 — like groups 1/4/5.** `clk`/`rst_n` unused (uniform FU
interface, wrapped in `// verilator lint_off UNUSEDSIGNAL`). 2-input join
handshake with lossless backpressure.

A 2-member group, so `op_sel` is **back to 1 bit** (groups 4/5 used 2 bits for
3 members). Like group 5, there are **no edge cases** — signed min/max are total
functions (equal operands and INT_MIN/INT_MAX resolve naturally), and both
operands are fully used.

**No loom reference exists** for integer min/max (`fu_op_minsi`/`maxsi` are absent
from loom's `SVModuleRegistry` and `src/rtl/design/arith/`). This module is
designed fresh from the rationale — trivially: one signed comparator + an output
mux.

## 3. RTL design — `ops/int_arith/min_max_signed/fu_min_max_signed.sv`

### 3.1 Interface
Standard FU ports + a **1-bit** `op_sel`. `in_data_0` = A, `in_data_1` = B.
`parameter WIDTH = 32`.

### 3.2 Datapath
```
a_lt_b   = $signed(in_data_0) < $signed(in_data_1);   // one signed comparator
out_data = op_sel ? (a_lt_b ? in_data_1 : in_data_0)  // maxsi: larger operand
                  : (a_lt_b ? in_data_0 : in_data_1); // minsi: smaller operand
```
`$signed(...)` makes the comparison signed (no `UNSIGNED` lint). Pure
combinational; `out_valid = in_valid_0 & in_valid_1`,
`in_ready_* = out_ready & out_valid`.

Correctness (by hand): minsi picks `a` iff `a < b`; maxsi picks `b` iff `a < b`;
ties (`a == b`) give the common value either way; INT_MIN/INT_MAX compare
correctly under signed semantics.

## 4. Generator + template
- New template `generator/templates/fu_min_max_signed.sv.j2` (plain substitution:
  `module_name`, `width`, `op_list`; no `{{` replication, no reset).
- `generator.py`: add `"min_max_signed": "fu_min_max_signed.sv.j2"` to
  `_TEMPLATE_MAP`.
- Committed golden = generator output for
  `fabric.op[@arith.minsi, @arith.maxsi]`.
- `registry.yaml`: group 6 `status: not_started → verified`.

## 5. Testbench — `tb/int_arith/min_max_signed/tb_fu_min_max_signed.sv`
Self-checking, combinational (mirrors group 1), parameterized by `WIDTH`. Drives
A, B, 1-bit `op_sel`; settles; compares to a golden model (`$signed` comparison
selecting min/max). Coverage: all four sign quadrants (±a, ±b), equal operands,
INT_MIN/INT_MAX corners, `op_sel` toggle on identical operands, handshake corners
(backpressure; no output when an input invalid), randomized signed vectors with
`op_sel ∈ {0,1}`.

## 6. Python tests
- Add: registry lookup for `min_max_signed`; `generate(...)` writes the file;
  golden-file match.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.minsi, @arith.maxsi]` (now implemented). Repoint it to group 7
  (`fabric.op[@arith.minui, @arith.maxui]`, min_max_unsigned).

## 7. Verification
`demo_min_max_signed.sh` mirroring prior demos: generate → `verilator --lint-only
-Wall` → build+run TB at `WIDTH=32` and `WIDTH=8` → assert `PASS:`.
