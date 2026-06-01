# Design: `fabric_gen` Generator + Share Group 1 RTL (`fu_add_sub`)

**Date:** 2026-05-31 (RTL design); generator subsystem added 2026-06-01
**Status:** Approved design, pending implementation plan
**Scope:** Two integrated deliverables forming one end-to-end vertical slice:

1. **RTL** — the `fu_add_sub.sv` module + a self-checking testbench for fabric
   hardware share group 1 (`arith.addi` / `arith.subi`). (§3–§5)
2. **Generator** — the `fabric_gen` Python package that parses a `fabric.op[...]`
   string, validates it against the share groups, and emits the group-1 RTL from
   a Jinja2 template — plus tests, a demo runner, end-to-end verification, and a
   README. (§8–§12)

The generator's **parser and share-group validator are general** (any op string,
all 19 groups). **RTL emission is implemented for group 1 only**; any other valid
group returns a clear "template not yet implemented" error. This is the vertical
slice that proves the whole pipeline on the one group with real, verified RTL.

---

## 1. Goal

Produce one synthesizable, simulatable SystemVerilog module that implements
share group 1 as a **single shared-datapath block** selectable at runtime via an
`op_sel` config knob:

- `op_sel = 0` → `arith.addi` (`out = a + b`)
- `op_sel = 1` → `arith.subi` (`out = a - b`)

faithful to the share-group rationale: *"Subtraction is addition with one operand
inverted plus a carry-in. One adder tree, one control bit."* (see
`docs/fabric_hardware_share_groups.md`, group 1).

The whole flow must be **(1) simulatable** (Synopsys VCS) and **(2)
synthesizable** (Design Compiler, loom's synthesizable subset).

## 2. Context and references

- Registry entry (source of truth): `registry.yaml` group 1 —
  `name: add_sub`, `family: int_arith`, `ops: [arith.addi, arith.subi]`,
  `rtl_module: fu_add_sub.sv`, `params: {width: 32}`.
- `op_sel` semantics: `docs/fabric_reconfigurable_ops.md` — a multi-member
  `op_list` yields an `op_sel` `sw_config` axis (one value per member) that
  "alters the materialized software function **without changing the hardware**."
  → one physical block, runtime select.
- RTL conventions mirrored from loom (read-only reference at
  `/edata1/mykol/loom`):
  - `src/rtl/design/arith/fu_op_addi.sv`, `fu_op_subi.sv` — the combinational
    latency-0 FU handshake template this design follows.
  - `src/rtl/design/arith/fu_op_cmpi.sv` — precedent for a config input
    (`cfg_bits`) selecting behavior; `op_sel` plays the same role here.
  - `docs/spec-rtl-generation-constraints.md` — synthesizable-subset rules,
    lint gate, style requirements.
  - `src/rtl/testbench/common/*` — TB style reference (not reused; see §4).

## 3. RTL design — `ops/int_arith/add_sub/fu_add_sub.sv`

### 3.1 Module interface

```systemverilog
module fu_add_sub #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,        // unused (combinational); kept for uniform FU interface
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,     // held config: 0 = arith.addi, 1 = arith.subi (op_list order)

  input  logic [WIDTH-1:0]  in_data_0,  // operand A (data, handshaked)
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,  // operand B (data, handshaked)
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);
```

### 3.2 Shared datapath (single adder)

```systemverilog
  // subtract = add with operand B inverted and carry-in = 1
  logic [WIDTH-1:0] b_eff;
  assign b_eff    = op_sel ? ~in_data_1 : in_data_1;
  assign out_data = in_data_0 + b_eff + {{(WIDTH-1){1'b0}}, op_sel};  // op_sel = carry-in
```

`op_sel=0` → `a + b`; `op_sel=1` → `a + ~b + 1 = a - b`. Synthesizes to a single
WIDTH-bit adder with an XOR row on operand B — no second datapath. The carry-in
term is explicitly zero-extended for clean width handling.

### 3.3 Handshake — contract (A): combinational, latency 0, full backpressure

```systemverilog
  assign out_valid  = in_valid_0 & in_valid_1;   // join: fire only when both operands valid
  assign in_ready_0 = out_ready & out_valid;      // consume only when output is accepted
  assign in_ready_1 = out_ready & out_valid;
```

Properties:
- Transfer on each port iff `valid && ready`.
- **Lossless under backpressure**: operands consumed only when `out_ready` is
  high (no data dropped on a downstream stall).
- **`out_valid` never depends on `out_ready`** → no combinational loop when
  chained.
- **2-input join**: each data input's `ready` is gated on the other's `valid`.
- Combinational, **unbuffered** (latency 0). Retiming/elastic buffering, if
  needed, belongs to the PE slot wrapper (loom's three-layer latency model), not
  this FU body.

### 3.4 `op_sel` is config, not a data operand

`op_sel` is a **held configuration input**: no `valid`/`ready`, and it does
**not** gate the handshake. It is stable for the duration of a configuration,
matching its `sw_config` role (`docs/fabric_reconfigurable_ops.md`). Width is 1
bit (`ceil(log2(2))` for a 2-member group).

### 3.5 Synthesizability + simulatability

- Pure combinational; every output driven (no inferred latches).
- No `initial`, no `#delay`, no tri-state in the design module.
- Single clock domain; `clk`/`rst_n` carried for interface uniformity but unused
  (no state) — lint-waived as loom does for `addi`.
- Clean under both VCS and `verilator --lint-only -Wall` (loom waiver set).
- Style: named `begin`/`end` blocks, `endmodule : fu_add_sub`,
  `parameter int unsigned WIDTH`.

## 4. Testbench design — `tb/int_arith/add_sub/tb_fu_add_sub.sv`

Self-contained, self-checking single file (loom has no per-FU TB; its hex-trace
infra is built for streaming tokens and is overkill for one combinational FU).

- Free-running clock; `rst_n` asserted briefly then held high. DUT is
  combinational, so each vector is checked the cycle it is applied.
- **Independent golden reference** (uses `+`/`-` directly, so it cross-checks the
  DUT's invert+carry implementation rather than mirroring it):
  `function automatic logic [WIDTH-1:0] golden(a, b, op_sel); return op_sel ? (a - b) : (a + b);`
- **Directed corner vectors:**
  - add (`op_sel=0`): `0+0`, `a+0`, `1+max` (overflow wrap), `max+max`.
  - sub (`op_sel=1`): `5-3`, `3-5` (underflow wrap), `0-1` (→ all-ones),
    `min-1`, `a-a=0`.
  - `op_sel` toggled between consecutive vectors (catch any stale/latched select).
- **Randomized:** N (default 10000) iterations of random `a`, `b`, `op_sel`;
  compare `out_data` vs `golden`.
- **Handshake checks:**
  - both valid + `out_ready=1` → expect `out_valid=1` and `in_ready_*=1`.
  - `out_ready=0` → expect `out_valid=1` but `in_ready_*=0` (no transfer).
  - one input invalid → expect `out_valid=0`.
- **Verdict:** error counter; final `$display` `PASS`/`FAIL`; non-zero
  exit / `$fatal` on any mismatch so CI can gate.
- **Coverage of widths:** primary run at `WIDTH=32`; also instantiate `WIDTH=8`
  to flush width-dependent bugs (carry-in extension, sign wrap) cheaply.
- `initial`/`#delay`/`$display` confined to the TB. Same style conventions as the
  design (named blocks, `iter_varN` loop vars). Runs under VCS; verilator-lint
  clean.

## 5. Verification gate

A change is "done" only when:
1. `verilator --lint-only -Wall` (loom waiver set) on `fu_add_sub.sv` is clean.
2. VCS compiles and runs `tb_fu_add_sub.sv` to completion with `PASS` and
   zero mismatches across directed + randomized vectors at WIDTH 32 and 8.

## 6. Out of scope (explicit)

- **RTL emission for share groups 2–19.** The generator validates them but
  returns a "template not yet implemented" error; authoring those synthesizable
  templates (FSM dividers, FP behavioral models, CORDIC/Newton transcendentals)
  is future work.
- PE/slot-wrapper integration, config-memory word-serial loading of `op_sel`,
  and fabric-level integration. This effort delivers the leaf FU + its unit TB +
  the generator that emits the FU.
- Generator-emitted testbenches (the TB is hand-authored; see §10).

## 7. Open items / future

- `op_sel` width and encoding generalize to `ceil(log2(N))` for N-member groups;
  this 2-member case (1 bit) is the base. The generator computes this from
  `op_list` length so later templates inherit it.
- A future PE slot wrapper owns any retiming registers / interval throttling per
  loom's three-layer latency model.

---

## 8. Generator package — `fabric_gen`

### 8.1 Responsibility and flow

`fabric_gen` turns an op string into a SystemVerilog file:

```
"fabric.op[@arith.addi, @arith.subi]"
        │  parse
        ▼
ParsedOp(op_list=["arith.addi", "arith.subi"])
        │  validate (share groups)
        ▼
ShareGroup #1  (add_sub)            ──► registry lookup (module name, width, params)
        │  select template + build context
        ▼
render generator/templates/fu_add_sub.sv.j2
        │  write
        ▼
<out_dir>/fu_add_sub.sv
```

### 8.2 File structure

Honors the existing scaffold (`generator/templates/`, top-level `tests/`):

| Path | Responsibility |
|------|----------------|
| `generator/fabric_gen/__init__.py` | Package marker; exports `generate`, error types |
| `generator/fabric_gen/__main__.py` | CLI entry (`python -m fabric_gen`) |
| `generator/fabric_gen/errors.py` | `ParseError`, `ShareGroupError`, `TemplateNotImplemented` |
| `generator/fabric_gen/parser.py` | `parse_op_string(s) -> ParsedOp` |
| `generator/fabric_gen/sharegroups.py` | 19-group table + `validate(op_list) -> ShareGroup` |
| `generator/fabric_gen/registry.py` | Load `registry.yaml`; lookup group meta by op set |
| `generator/fabric_gen/generator.py` | `generate(op_string, out_dir, width=None) -> Path` |
| `generator/templates/fu_add_sub.sv.j2` | Group-1 RTL template |
| `generator/pyproject.toml` | Package metadata + deps (`jinja2`, `pyyaml`) + console script `fabric-gen` |
| `tests/test_parser.py` | Parser unit tests |
| `tests/test_sharegroups.py` | Validator unit tests |
| `tests/test_generator.py` | End-to-end generation + golden-file + error tests |
| `tests/conftest.py` | Puts `generator/` on `sys.path` for imports |

Run without install via `PYTHONPATH=generator python -m fabric_gen ...`; or
`pip install -e generator` for the `fabric-gen` console script. The template
directory is resolved as `Path(__file__).resolve().parents[1] / "templates"`.

### 8.3 Parser (`parser.py`)

- Accepts: `fabric.op[arith.addi]`, `fabric.op[@arith.addi, arith.subi]`,
  `fabric.op[@arith.addi, @arith.subi]` — leading `@` optional per member,
  whitespace-tolerant.
- Algorithm: assert `fabric.op[` prefix and `]` suffix; take the inside; split on
  `,`; for each member strip whitespace + a leading `@`; drop empties.
- Returns `ParsedOp(op_list: list[str])` (a `@dataclass`).
- Raises `ParseError` on: missing `fabric.op[...]` shell, empty `op_list`,
  member that does not match `^[a-z]+\.[a-z0-9_]+$`.

### 8.4 Share-group validator (`sharegroups.py`)

- `SHARE_GROUPS`: list of 19 tuples mirroring `docs/fabric_hardware_share_groups.md`
  (the canonical 19-row table). Each is the frozenset of member op names.
- `validate(op_list) -> ShareGroup`:
  - `len == 1`: always legal. Returns the multi-member group that contains the
    member if any, else a synthetic singleton group.
  - `len > 1`: enforce the two verifier rules — (1) every member is in some
    multi-member group, (2) all members are in the **same** group. On violation
    raise `ShareGroupError` with a message naming the offending members
    (mirrors `FuOp::verify` semantics from the share-groups doc).
- `ShareGroup` carries the member set and the canonical group index (1–19).

### 8.5 Registry (`registry.py`)

- `load_registry(path="registry.yaml") -> list[dict]` via `pyyaml`.
- `lookup_by_ops(op_list) -> dict`: find the group whose `ops` set equals the
  parsed `op_list` set; returns the dict (`name`, `family`, `rtl_module`,
  `params`). Raises `KeyError`-derived error if absent.

### 8.6 Generation (`generator.py`)

`generate(op_string: str, out_dir: Path, width: int | None = None) -> Path`:

1. `parse_op_string` → `ParsedOp`.
2. `validate(op_list)` → `ShareGroup` (raises on illegal combinations).
3. `lookup_by_ops` → registry meta (`rtl_module`, `params.width`).
4. Resolve template by group name. Only `add_sub` is wired; any other group
   raises `TemplateNotImplemented(f"RTL template for share group '{name}' is not "
   f"yet implemented")`.
5. Build Jinja2 context:
   - `module_name` = `rtl_module` without `.sv` (e.g. `fu_add_sub`)
   - `width` = explicit arg, else `params.width`, else `32`
   - `op_list` = the member list (for the header comment)
   - `op_sel_map` = `{member: index}` (0 = first member = `arith.addi`,
     1 = `arith.subi`) — the `op_sel` encoding
6. Render the template (Jinja2 `Environment`, `trim_blocks=True,
   lstrip_blocks=True`), write to `out_dir / rtl_module`, return the path.

### 8.7 CLI (`__main__.py`)

```
python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/rtl [--width 32]
```

- argparse: positional `op_string`; `-o/--out-dir` (default `.`); `--width` (int,
  optional override).
- On success: print the written path, exit 0.
- On `ParseError` / `ShareGroupError` / `TemplateNotImplemented`: print
  `fabric-gen error: <category>: <message>` to stderr, exit 1 (mirrors loom's
  `gen-sv error:` contract).

### 8.8 Template (`generator/templates/fu_add_sub.sv.j2`)

Renders byte-for-byte the module specified in §3 (interface, shared-adder
datapath, combinational handshake), with `{{ module_name }}`, the default
`WIDTH = {{ width }}`, and a generated header comment listing `op_list` and the
`op_sel` encoding. The rendered output must be identical to the hand-authored
reference `fu_add_sub.sv` (verified by a golden-file test, §9).

## 9. Generator tests (pytest)

- `test_parser.py`: all three accepted string forms parse to the right
  `op_list`; `@`-tolerance; errors on malformed shell, empty list, bad member.
- `test_sharegroups.py`: `[addi, subi]` → group 1; singleton `[muli]` legal;
  `[addi, muli]` → `ShareGroupError` (not in a common group); `[addi, subf]` →
  `ShareGroupError` (different groups); `[divsi, remsi]` → group 2.
- `test_generator.py`:
  - generate group 1 → file exists; content contains `module fu_add_sub`,
    `input  logic              op_sel`, and the shared-adder expression
    `in_data_0 + b_eff`.
  - **golden-file test**: rendered output equals the committed
    `ops/int_arith/add_sub/fu_add_sub.sv` (byte-identical) — proves the template
    and the hand-authored reference never drift.
  - generating `fabric.op[@arith.divsi, @arith.remsi]` raises
    `TemplateNotImplemented`.
  - generating `fabric.op[@arith.addi, @arith.muli]` raises `ShareGroupError`.
- Run: `PYTHONPATH=generator pytest tests/ -v`. No simulator needed (fast gate).

## 10. Demo runner + end-to-end verification

`demo.sh` (repo root) — the e2e proof:

1. `PYTHONPATH=generator python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/demo`
2. `module load verilator/5.044`
3. `verilator --lint-only -Wall build/demo/fu_add_sub.sv` → clean.
4. `verilator --binary --timing --top-module tb_fu_add_sub -GWIDTH=32`
   over `build/demo/fu_add_sub.sv` + `tb/int_arith/add_sub/tb_fu_add_sub.sv`,
   then run the produced binary → expect `PASS`.
5. Print `DEMO OK` on success; non-zero exit on any failure.

This closes the loop: **generator emits the RTL → that emitted RTL lints clean →
the hand-authored TB drives it to PASS.** VCS sign-off (§5) is an additional
manual step once the `-full64`/libelf environment issue is resolved.

## 11. README (`README.md`, repo root)

Sections: project overview (registry-driven fabric FU generator); layout
(`ops/`, `tb/`, `generator/`, `docs/`, `registry.yaml`); install
(`pip install -e generator` or `PYTHONPATH`); usage (CLI example + Python API);
running tests (`pytest`); running the demo (`./demo.sh`); the verification gate
(verilator primary, VCS sign-off); pointers to `docs/` specs; current coverage
(group 1 only) and how to extend.

## 12. Dependencies

`jinja2`, `pyyaml` (runtime); `pytest` (test). Declared in
`generator/pyproject.toml`. Simulation needs `verilator/5.044` (module);
VCS optional for sign-off.
