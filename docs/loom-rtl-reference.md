# Loom RTL Reference (for Fabric FU / Share-Group Implementations)

**Purpose:** A distilled, verified reference of what we learned reading the loom
project, to speed up future share-group RTL implementations in `fabric_op_gen`.
Loom is a **read-only reference** at `/edata1/mykol/loom` — do not modify it.

**Date compiled:** 2026-06-02 (during share group 2, `fu_div_rem_signed`).
All file:line references below were confirmed firsthand against loom HEAD at that
time. Loom may evolve — re-verify before relying on a specific line.

---

## 1. The one critical distinction: loom is per-op, we are per-share-group

This is the single most important thing to internalize.

- **Loom emits one SystemVerilog module per MLIR op.** There is **no `op_sel`**
  and **no `hwShareGroups()` function** in loom's source. The op→module mapping
  is a flat table in `lib/loom/SVGen/SVModuleRegistry.cpp` (`struct OpMapping`,
  entries like `{"arith.divsi", "arith", "fu_op_divsi.sv"}`). Modules are named
  `fu_op_<opname>.sv` and live under `src/rtl/design/<dialect>/`.
- **Where does selection happen in loom?** At the IR level via `fabric.mux`
  inside a `fabric.function_unit` body. Two ops each get their own datapath
  block and a mux picks the output. (See `docs/fabric_hardware_share_groups.md`
  §"What to do when sharing does not exist".)
- **fabric_op_gen (this project) is a layer loom does not have.** We take a
  share-group `op_list` and emit **one shared-datapath module** with a held
  `op_sel` config input that selects between members. The share-group taxonomy
  lives in `registry.yaml` + `generator/fabric_gen/sharegroups.py`, narrated in
  `docs/fabric_hardware_share_groups.md`. The doc claims the canonical source is
  `hwShareGroups()` in `FabricOps.cpp` — **that function does not currently exist
  in loom**; treat our registry/sharegroups as the de-facto source of truth.

**Practical consequence:** loom's `fu_op_<member>.sv` files are our best
reference for the *datapath math and handshake* of each member, but we must
**merge** the members of a share group into one module and add the `op_sel`
output mux ourselves. For group 2 the two loom modules (`fu_op_divsi.sv`,
`fu_op_remsi.sv`) shared an identical iteration and differed only in sign fix-up
and output tap — exactly what `op_sel` selects. Expect similar structure for
other groups (the share-group rationale in the doc tells you what is shared).

---

## 2. FU RTL interface convention (verified from loom modules)

Every loom FU, combinational or multi-cycle, uses the same port shape. Match it.

```systemverilog
module fu_op_<name> #(
  parameter int unsigned WIDTH = 32
) (
  input  logic                clk,
  input  logic                rst_n,
  // [optional] config input(s) — e.g. cfg_bits / op_sel
  input  logic [WIDTH-1:0]    in_data_0,   // operand A
  input  logic                in_valid_0,
  output logic                in_ready_0,
  input  logic [WIDTH-1:0]    in_data_1,   // operand B (if 2-input)
  input  logic                in_valid_1,
  output logic                in_ready_1,
  output logic [WIDTH-1:0]    out_data,
  output logic                out_valid,
  input  logic                out_ready
);
```

- Per-operand input channel: `in_data_N` / `in_valid_N` / `in_ready_N`.
- Single output channel: `out_data` / `out_valid` / `out_ready`.
- `clk`/`rst_n` always present. For **combinational** FUs they are unused — loom
  wraps them in `// verilator lint_off UNUSEDSIGNAL` … `lint_on`. For
  **multi-cycle** FUs they are real (drop the waiver).

### Config inputs (precedent for our `op_sel`)
Loom already uses held config inputs to select behavior in one block:
- `fu_op_cmpi.sv`: `input logic [3:0] cfg_bits;` — a 4-bit predicate selecting
  eq/ne/slt/sle/sgt/sge/ult/ule/ugt/uge (encoding matches `arith.cmpi`).
- `fu_op_cmpf.sv`: 4-bit predicate config (latency 0).

Our `op_sel` plays the same role. Name it `op_sel` (single bit for 2-member
groups; widen to `[ceil(log2(N))-1:0]` for larger groups, e.g. group 17 rounding
has 5 members → 3-bit `op_sel`).

---

## 3. The two canonical datapath patterns

### 3a. Combinational, latency 0 (e.g. addi, andi, cmpi)
`fu_op_addi.sv` is the template:
```systemverilog
assign out_valid  = in_valid_0 & in_valid_1;     // 2-input join
assign in_ready_0 = out_ready & out_valid;       // lossless backpressure
assign in_ready_1 = out_ready & out_valid;
assign out_data   = in_data_0 + in_data_1;        // pure comb datapath
```
This is exactly our group 1 (`fu_add_sub`).

### 3b. Multi-cycle FSM (e.g. divsi, remsi, divui, remui, muli)
`fu_op_divsi.sv` / `fu_op_remsi.sv` are the template. Restoring division,
intrinsic latency `WIDTH+2`, **non-pipelined** (one op in flight):

- States: `ST_IDLE → ST_COMPUTE → ST_DONE` (`typedef enum logic [1:0]`).
- Iteration counter: `localparam CNT_WIDTH = $clog2(WIDTH+1)`, count `0..WIDTH-1`.
- Input handshake: `in_ready_* = (state_r == ST_IDLE) & in_valid_0 & in_valid_1`.
  **Operands are captured at accept** — the producer may drop `in_data`
  afterward, so register everything you need (magnitudes, divisor, sign flags).
- Output handshake: `out_valid = (state_r == ST_DONE)`; return to `ST_IDLE` on
  `out_ready`.
- Restoring-division core (per iteration): shift partial remainder left bringing
  in the next dividend bit, trial-subtract the divisor, set the quotient bit and
  keep-or-restore. After `WIDTH` iterations: quotient magnitude in the shift
  register, remainder magnitude in the partial-remainder register `[WIDTH-1:0]`.
- Signed fix-up at the output: quotient negated iff `a_neg ^ b_neg`; remainder
  negated iff `a_neg` (sign follows dividend — C / MLIR semantics).

This is exactly our group 2 (`fu_div_rem_signed`), which merges the two loom
modules and selects the tap with `op_sel`.

---

## 4. Reference RTL available for each future share group

Loom modules to read (under `src/rtl/design/arith/` or `.../math/`) when we
implement each group. Map from `registry.yaml`:

| Group | Name | Members | Loom reference module(s) | Pattern |
|------:|------|---------|--------------------------|---------|
| 1 | add_sub | addi, subi | `fu_op_addi.sv`, `fu_op_subi.sv` | comb (done) |
| 2 | div_rem_signed | divsi, remsi | `fu_op_divsi.sv`, `fu_op_remsi.sv` | multi-cycle (done) |
| 3 | div_rem_unsigned | divui, remui | `fu_op_divui.sv`, `fu_op_remui.sv` | multi-cycle (same as g2, no sign fix-up) |
| 4 | barrel_shift | shli, shrsi, shrui | `fu_op_shli.sv`, `fu_op_shrsi.sv`, `fu_op_shrui.sv` | comb |
| 5 | bitwise_alu | andi, ori, xori | `fu_op_andi.sv`, `fu_op_ori.sv`, `fu_op_xori.sv` | comb |
| 8 | int_to_fp | sitofp, uitofp | `fu_op_sitofp.sv`, `fu_op_uitofp.sv` | multi-cycle, FP (`ifdef SYNTH_FP_IP`) |
| 9 | fp_to_int | fptosi, fptoui | `fu_op_fptosi.sv`, `fu_op_fptoui.sv` | multi-cycle, FP |
| 10 | fp_add_sub | addf, subf | `fu_op_addf.sv`, `fu_op_subf.sv` | multi-cycle, FP |
| 11 | fp_div_rem | divf, remf | `fu_op_divf.sv` (no `remf` in loom) | FP; remf may need new RTL |
| 12 | fp_min_max | minimumf, maximumf | `fu_op_minimumf.sv` (no maximumf) | comb FP |
| 13 | cordic_trig | sin, cos | `fu_op_sin.sv`, `fu_op_cos.sv` | CORDIC |
| 18 | sqrt_rsqrt | sqrt, rsqrt | `fu_op_sqrt.sv`, `fu_op_rsqrt.sv` | multi-cycle |

Groups 6, 7 (min/max int), 14–17, 19 have **no** direct loom module — we design
fresh from the share-group rationale. Some FP members (`remf`, `maximumf`,
several math ops) are absent in loom and will need new RTL. Confirm presence with
`ls /edata1/mykol/loom/src/rtl/design/{arith,math}/` before assuming a reference
exists. Loom's full op→module table: `lib/loom/SVGen/SVModuleRegistry.cpp`.

---

## 5. Latency / interval model (loom's three layers)

From `docs/spec-rtl-generation-constraints.md`. Useful context even though we only
emit the FU core today (loom adds the wrapper layers):

1. **Intrinsic latency** — the FU module's own cycle count. Combinational = 0;
   div/rem/mul = "≥ 1, width-dependent" (our divider is `WIDTH+2`).
2. **Slot wrapper** — adds `(declared_latency − intrinsic_latency)` retiming
   shift-register stages. `latency == 0` is only legal when intrinsic == 0.
3. **Interval throttle** — `interval == 1` fully pipelined (no counter);
   `interval > 1` adds a countdown counter blocking re-fire. Our dividers are
   non-pipelined (effective interval = latency).

Rules: non-dataflow FUs need `latency >= 0` and `interval >= 1`; dataflow FUs
require `latency == -1` and `interval == -1`.

---

## 6. Synthesizable subset & style (match loom and group 1)

- **Single clock, synchronous reset** (`always_ff @(posedge clk)` with
  `if (!rst_n)`); no latches, tristates, `initial`, or `#delay` in *design* RTL.
- **Named `begin : label … end : label` blocks** everywhere (FSM cases, if/else,
  reset/normal). Loom and our group-1/group-2 RTL do this consistently.
- **No `/` or `%` operators in the datapath** — division must be an explicit
  iterative FSM. (`/` and `%` are fine in *testbench* golden models only.)
- **Width-explicit constants.** Loom idioms:
  - two's-complement negate: `~x + {{(WIDTH-1){1'b0}}, 1'b1}` (value 1).
  - We instead used the equivalent sized cast `WIDTH'(1)` / `CNT_WIDTH'(1)` — see
    the Jinja gotcha below for why.
  - replication/zero: `{WIDTH{1'b0}}`, `{(WIDTH+1){1'b0}}`.
- `initial` / `#delay` / `$display` / `$random` / `$finish` / `$fatal` are
  **testbench-only**.

### Jinja2 `{{` gotcha (template authoring)
SystemVerilog nested replication `{{(WIDTH-1){1'b0}}, 1'b1}` starts with `{{`,
which collides with Jinja2's variable delimiter. Two safe options:
1. Use a sized cast instead: `WIDTH'(1)` (what `fu_div_rem_signed.sv.j2` does).
2. Pass the literal as a render variable (group 1 passes `carry_term =
   "{{(WIDTH-1){1'b0}}, op_sel}"`). **Note** that existing `carry_term` ends in
   `op_sel`, not `1'b1` — it is group-1-specific, not a generic "+1".

---

## 7. Verilator lint policy

Loom lints generated RTL with `verilator --lint-only -Wall` plus a specific
suppression set (`src/rtl/python/gen_sv.py`, `run_verilator_lint`):

```
-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET -Wno-UNDRIVEN
-Wno-PINMISSING -Wno-PINCONNECTEMPTY -Wno-UNSIGNED
```
Crucially **no `-Wno-fatal`**: any *unwaived* warning (notably `WIDTHTRUNC` /
`WIDTHEXPAND`) is a hard error. Keep RTL width-clean.

Our `demo*.sh` simulate with: `verilator --binary --timing -Wno-WIDTHTRUNC
-Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD`. Our committed RTL passes a
strict `verilator --lint-only -Wall` with **zero** warnings.

**Tooling:** Verilator is not on `PATH`; load it with `module load
verilator/5.044` (the `module` command is available in login shells: `bash -lc`).

---

## 8. gen-sv error contract (what our `errors.py` mirrors)

Loom format: `gen-sv error: <category>: <message>`. Categories observed in
`docs/spec-rtl-generation-constraints.md`:

| Loom category | Meaning | Our `errors.py` analog |
|---------------|---------|------------------------|
| `unsupported-op` | op not in supported tier / no RTL | `TemplateNotImplemented` (`unsupported-op`) |
| `latency` | declared vs intrinsic latency violation | — (we don't model latency yet) |
| `interval` | interval rule violation | — |
| `timing-class` | dataflow op mixed with others | — |
| `param-range` | width/port/tag/depth out of range | — (could add) |
| `decomposition` | switch decomposition invalid | — |

Our own categories: `parse` (`ParseError`), `share-group` (`ShareGroupError`),
`registry` (`RegistryError`), plus `unsupported-op`. The CLI prints
`fabric-gen error: <category>: <message>` and exits non-zero, mirroring loom.

---

## 9. Tier classification (which groups are "easy" vs need IP)

From the constraints spec:
- **Tier 1** — integer/logic/bitwise. Fully synthesizable. (Groups 1–9 mostly.)
  Sub-split: combinational (latency 0) vs multi-cycle (div/rem/mul).
- **Tier 2** — floating-point. Behavioral RTL guarded by `ifdef SYNTH_FP_IP`
  (real synthesis swaps in a vendor IP). (Groups 8–12.)
- **Tier 3** — transcendental FP (sin/cos/exp/log/tanh/erf …). **Rejected without
  `--fp-ip-profile`** in loom — no portable synthesizable implementation. (Groups
  13–19.) These will be the hardest; expect to design approximations (CORDIC,
  series, LUT) ourselves or gate behind a profile.

---

## 10. Behavioral divergences we deliberately chose

- **Divide-by-zero:** loom's `fu_op_divsi`/`remsi` return **0**. We chose
  **RISC-V M-extension** semantics instead (div0 → quotient `-1`, remainder =
  dividend; `INT_MIN/-1` → quotient `INT_MIN`, remainder `0`). If you reuse a
  loom divider as reference, remember to add the div0 fast-path and verify
  `INT_MIN/-1` (it falls out of restoring division naturally — no special case).
- **Verilator native `/` overflow:** in a TB golden model, `$signed(INT_MIN) /
  $signed(-1)` returns **0** in Verilator (it guards the C++ UB), *not* `INT_MIN`.
  Encode `INT_MIN/-1` explicitly in the golden, or the RTL (correct) will appear
  to mismatch.

---

## 11. Key loom paths (index)

| What | Path under `/edata1/mykol/loom` |
|------|---------------------------------|
| Op → SV module table | `lib/loom/SVGen/SVModuleRegistry.cpp` |
| FU body op allowlist + `FunctionUnitOp::verify` | `lib/loom/Dialect/Fabric/FabricOps.cpp` |
| Combinational FU template | `src/rtl/design/arith/fu_op_addi.sv` |
| Multi-cycle FU template | `src/rtl/design/arith/fu_op_divsi.sv`, `fu_op_remsi.sv` |
| Config-input precedent | `src/rtl/design/arith/fu_op_cmpi.sv` (`cfg_bits`) |
| RTL generation constraints (tiers, latency, errors, lint) | `docs/spec-rtl-generation-constraints.md` |
| gen-sv driver + lint policy | `src/rtl/python/gen_sv.py` |
| All arith / math RTL | `src/rtl/design/{arith,math}/` |
