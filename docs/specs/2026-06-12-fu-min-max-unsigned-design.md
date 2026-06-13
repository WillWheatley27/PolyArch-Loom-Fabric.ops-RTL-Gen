# Design: Share Group 7 RTL (`fu_min_max_unsigned`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (replicates the established per-group pattern), pending impl
**Scope:** Add share group 7 (`min_max_unsigned` = `arith.minui` / `arith.maxui`)
as a full end-to-end slice, mirroring groups 1-6.

The generator pipeline is unchanged; the only generator change is one
`_TEMPLATE_MAP` entry.

---

## 1. Goal

One synthesizable, simulatable SystemVerilog module implementing share group 7 as
a single shared unsigned comparator, selectable via a 1-bit `op_sel`:

- `op_sel = 0` → `arith.minui` (`out = unsigned-min(a, b)`)
- `op_sel = 1` → `arith.maxui` (`out = unsigned-max(a, b)`)

faithful to the share-group rationale: *"Unsigned counterpart of group 6."*
(`docs/fabric_hardware_share_groups.md`, group 7).

## 2. Relationship to group 6

**Identical to `fu_min_max_signed` except the comparator is unsigned** — drop
`$signed(...)` so `a_lt_b = in_data_0 < in_data_1` is an unsigned compare. Same
combinational shape, same 1-bit `op_sel`, same output mux, no edge cases (total
functions), both operands fully used. **No loom reference** exists for integer
min/max; designed fresh from the rationale.

Key behavioral distinction from group 6: a value with the MSB set (e.g.
`0x8000_0000`) is the *largest* unsigned but the *smallest* signed. So
`minui(0x8000_0000, 1) = 1` (vs `minsi = 0x8000_0000`). The testbench includes
MSB-set vectors to pin this down.

## 3. RTL design — `ops/int_arith/min_max_unsigned/fu_min_max_unsigned.sv`

### 3.1 Interface
Standard FU ports + a **1-bit** `op_sel`. `in_data_0` = A, `in_data_1` = B.
`parameter WIDTH = 32`.

### 3.2 Datapath
```
a_lt_b   = in_data_0 < in_data_1;                     // one unsigned comparator
out_data = op_sel ? (a_lt_b ? in_data_1 : in_data_0)  // maxui: larger operand
                  : (a_lt_b ? in_data_0 : in_data_1); // minui: smaller operand
```
Operands are unsigned `logic` vectors, so `<` is an unsigned comparison (no
`$signed`). Pure combinational; `out_valid = in_valid_0 & in_valid_1`,
`in_ready_* = out_ready & out_valid`. Lint-clean under `-Wall` (a two-variable
`<` is never constant, so no `UNSIGNED`/`CMPCONST` warning).

## 4. Generator + template
- New template `generator/templates/fu_min_max_unsigned.sv.j2` (plain
  substitution: `module_name`, `width`, `op_list`).
- `generator.py`: add `"min_max_unsigned": "fu_min_max_unsigned.sv.j2"` to
  `_TEMPLATE_MAP`.
- Committed golden = generator output for
  `fabric.op[@arith.minui, @arith.maxui]`.
- `registry.yaml`: group 7 `status: not_started → verified`.

## 5. Testbench — `tb/int_arith/min_max_unsigned/tb_fu_min_max_unsigned.sv`
Self-checking, combinational (mirrors group 6), parameterized by `WIDTH`. Golden
model uses an unsigned `<` selecting min/max. Coverage: ordered pairs, ties,
`0`/`UMAX` extremes, **MSB-set vectors** (distinguish unsigned from signed),
`op_sel` toggle on identical operands, handshake corners (backpressure; no output
when an input invalid), randomized vectors with `op_sel ∈ {0,1}`.

## 6. Python tests
- Add: registry lookup for `min_max_unsigned`; `generate(...)` writes the file;
  golden-file match.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.minui, @arith.maxui]` (now implemented). Repoint it to group 8
  (`fabric.op[@arith.sitofp, @arith.uitofp]`, int_to_fp).

## 7. Verification
`demos/demo_min_max_unsigned.sh` (in the `demos/` folder, cd's to repo root):
generate → `verilator --lint-only -Wall` → build+run TB at `WIDTH=32` and
`WIDTH=8` → assert `PASS:`.
