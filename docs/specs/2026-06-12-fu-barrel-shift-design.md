# Design: Share Group 4 RTL (`fu_barrel_shift`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (replicates the established per-group pattern), pending impl
**Scope:** Add share group 4 (`barrel_shift` = `arith.shli` / `arith.shrsi` /
`arith.shrui`) as a full end-to-end slice, mirroring groups 1-3: RTL module +
self-checking testbench + Jinja2 template + generator wiring + Python tests +
sim-verification + docs.

The generator pipeline is unchanged; the only generator change is one
`_TEMPLATE_MAP` entry.

---

## 1. Goal

One synthesizable, simulatable SystemVerilog module implementing share group 4 as
a single shared barrel shifter, selectable via a 2-bit `op_sel`:

- `op_sel = 0` → `arith.shli`  (`out = a << shamt`, logical left)
- `op_sel = 1` → `arith.shrsi` (`out = a >>> shamt`, arithmetic right, sign-fill)
- `op_sel = 2` → `arith.shrui` (`out = a >> shamt`, logical right, zero-fill)
- `op_sel = 3` → reserved (defaults to shli)

faithful to the share-group rationale: *"One barrel shifter with direction and
arithmetic-vs-logical select bits."* (`docs/fabric_hardware_share_groups.md`,
group 4). One physical shifter; `op_sel` selects direction + fill.

## 2. Relationship to prior groups

**Combinational, latency 0 — structurally like group 1 (`fu_add_sub`)**, not the
multi-cycle FSM of groups 2/3. `clk`/`rst_n` are unused (kept for a uniform FU
interface, wrapped in `// verilator lint_off UNUSEDSIGNAL`). 2-input join
handshake with lossless backpressure (`out_valid = in_valid_0 & in_valid_1`,
`in_ready_* = out_ready & out_valid`).

New vs. groups 1-3: a **2-bit `op_sel`** (3 members), and a shift-amount operand.

Loom references (per-op): `src/rtl/design/arith/fu_op_shli.sv`, `fu_op_shrsi.sv`,
`fu_op_shrui.sv`.

## 3. RTL design — `ops/int_arith/barrel_shift/fu_barrel_shift.sv`

### 3.1 Interface
Standard FU ports + a **2-bit** `op_sel`. `in_data_0` = value to shift,
`in_data_1` = shift amount. `parameter WIDTH = 32`.

### 3.2 Shift-amount semantics (the key decision)
MLIR `arith.shli/shrsi/shrui` return **poison** when the shift amount ≥ bit width
(undefined). We pick a deterministic, RISC-V-consistent behavior:

> **Mask the shift amount to the low `log2(WIDTH)` bits** — i.e.
> `shamt = in_data_1 & (WIDTH-1)`. For WIDTH=32 this is `in_data_1[4:0]`; a shift
> of 32 wraps to 0 (identity), 33 → 1, etc. This matches RISC-V `sll/srl/sra`
> (`shamt = rs2 & (XLEN-1)`) and is exactly how a barrel shifter is physically
> wired (a `log2(WIDTH)`-bit shift control).

Implementing the mask as a full-width AND means **every bit of `in_data_1` is
read**, so the module is `-Wall` clean with no `UNUSEDSIGNAL` pragma needed.
Assumes `WIDTH` is a power of two (true for the supported 8/32).

### 3.3 Datapath
```
shamt = in_data_1 & WIDTH'(WIDTH-1);
case (op_sel)
  0: out = in_data_0 << shamt;                       // shli
  1: out = $unsigned($signed(in_data_0) >>> shamt);  // shrsi (arithmetic)
  2: out = in_data_0 >> shamt;                        // shrui (logical)
  default: out = in_data_0 << shamt;                  // reserved -> shli
endcase
```
`$signed(...) >>> shamt` gives the arithmetic (sign-replicating) right shift;
`>>`/`<<` on the unsigned operand give logical shifts. `$unsigned(...)` makes the
signed→unsigned assignment explicit.

## 4. Generator + template
- New template `generator/templates/fu_barrel_shift.sv.j2`. No two's-complement
  `~x+1` and no reset/replication constructs → **no Jinja `{{` collision**; the
  template is plain substitution (`module_name`, `width`, `op_list`).
- `generator.py`: add `"barrel_shift": "fu_barrel_shift.sv.j2"` to `_TEMPLATE_MAP`.
- Committed golden = generator output for
  `fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]`.
- `registry.yaml`: group 4 `status: not_started → verified`.

## 5. Testbench — `tb/int_arith/barrel_shift/tb_fu_barrel_shift.sv`
Self-checking, combinational (mirrors group 1's TB), parameterized by `WIDTH`.
Drives `in_data_0`, `in_data_1`, 2-bit `op_sel`; settles; compares to a golden
model (native `<<`, `>>>` on `$signed`, `>>`, with the same `& (WIDTH-1)` mask).
Coverage: per-op directed corners (shamt = 0, 1, WIDTH-1, **WIDTH and WIDTH+1 to
exercise masking**, max); sign cases for shrsi (negative operand) vs shrui;
`op_sel` toggle on identical operands; handshake corners (backpressure;
no-output when an input is invalid); randomized vectors with `op_sel ∈ {0,1,2}`.

## 6. Python tests
- Add: registry lookup for `barrel_shift`; `generate(...)` writes the file;
  golden-file match.
- **Fix stale test:** `test_generate_unimplemented_group_raises` currently uses
  `fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]` (now implemented). Repoint
  it to group 5 (`fabric.op[@arith.andi, @arith.ori, @arith.xori]`, bitwise_alu).

## 7. Verification
`demo_barrel_shift.sh` mirroring prior demos: generate → `verilator --lint-only
-Wall` → build+run TB at `WIDTH=32` and `WIDTH=8` → assert `PASS:`.
