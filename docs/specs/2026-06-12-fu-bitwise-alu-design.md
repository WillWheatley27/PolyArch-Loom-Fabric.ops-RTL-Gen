# Design: Share Group 5 RTL (`fu_bitwise_alu`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (replicates the established per-group pattern), pending impl
**Scope:** Add share group 5 (`bitwise_alu` = `arith.andi` / `arith.ori` /
`arith.xori`) as a full end-to-end slice, mirroring groups 1-4.

The generator pipeline is unchanged; the only generator change is one
`_TEMPLATE_MAP` entry.

---

## 1. Goal

One synthesizable, simulatable SystemVerilog module implementing share group 5 as
a single shared bitwise ALU, selectable via a 2-bit `op_sel`:

- `op_sel = 0` → `arith.andi` (`out = a & b`)
- `op_sel = 1` → `arith.ori`  (`out = a | b`)
- `op_sel = 2` → `arith.xori` (`out = a ^ b`)
- `op_sel = 3` → reserved (defaults to andi)

faithful to the share-group rationale: *"One bit-wise ALU; the function is
selected by 2 control bits per bit-slice."* (`docs/fabric_hardware_share_groups.md`,
group 5). One physical ALU; `op_sel` selects the per-bit function.

## 2. Relationship to prior groups

**Combinational, latency 0 — like groups 1 (`fu_add_sub`) and 4
(`fu_barrel_shift`)**, not the multi-cycle FSM of groups 2/3. `clk`/`rst_n` are
unused (kept for a uniform FU interface, wrapped in
`// verilator lint_off UNUSEDSIGNAL`). 2-input join handshake with lossless
backpressure. Uses the same **2-bit `op_sel`** as group 4 (3 members).

**Simplest group so far:** bitwise AND/OR/XOR are total functions — there are
**no edge cases** (no poison, no divide-by-zero, no shift masking), and **both
operands are fully used** bit-for-bit, so there is no `UNUSEDSIGNAL` concern and
no Jinja `{{` collision.

Loom references (per-op): `src/rtl/design/arith/fu_op_andi.sv`, `fu_op_ori.sv`,
`fu_op_xori.sv`.

## 3. RTL design — `ops/int_arith/bitwise_alu/fu_bitwise_alu.sv`

### 3.1 Interface
Standard FU ports + a **2-bit** `op_sel`. `in_data_0` = A, `in_data_1` = B.
`parameter WIDTH = 32`.

### 3.2 Datapath
```
case (op_sel)
  0: out = in_data_0 & in_data_1;   // andi
  1: out = in_data_0 | in_data_1;   // ori
  2: out = in_data_0 ^ in_data_1;   // xori
  default: out = in_data_0 & in_data_1;  // reserved -> andi
endcase
```
Pure combinational; `out_valid = in_valid_0 & in_valid_1`,
`in_ready_* = out_ready & out_valid`.

## 4. Generator + template
- New template `generator/templates/fu_bitwise_alu.sv.j2` (plain substitution:
  `module_name`, `width`, `op_list`).
- `generator.py`: add `"bitwise_alu": "fu_bitwise_alu.sv.j2"` to `_TEMPLATE_MAP`.
- Committed golden = generator output for
  `fabric.op[@arith.andi, @arith.ori, @arith.xori]`.
- `registry.yaml`: group 5 `status: not_started → verified`.

## 5. Testbench — `tb/int_arith/bitwise_alu/tb_fu_bitwise_alu.sv`
Self-checking, combinational (mirrors groups 1/4), parameterized by `WIDTH`.
Drives A, B, 2-bit `op_sel`; settles; compares to a golden model (native `&`,
`|`, `^`). Coverage: per-op directed corners (0, all-ones, identity/annihilator
cases, `a op a`), `op_sel` toggle on identical operands, handshake corners
(backpressure; no output when an input is invalid), randomized vectors with
`op_sel ∈ {0,1,2}`.

## 6. Python tests
- Add: registry lookup for `bitwise_alu`; `generate(...)` writes the file;
  golden-file match.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.andi, @arith.ori, @arith.xori]` (now implemented). Repoint it
  to group 6 (`fabric.op[@arith.minsi, @arith.maxsi]`, min_max_signed).

## 7. Verification
`demo_bitwise_alu.sh` mirroring prior demos: generate → `verilator --lint-only
-Wall` → build+run TB at `WIDTH=32` and `WIDTH=8` → assert `PASS:`.
