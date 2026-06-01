# fabric_gen Generator + Share Group 1 RTL — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `fu_add_sub.sv` RTL + self-checking testbench for fabric share group 1, and the `fabric_gen` Python package that parses a `fabric.op[...]` string, validates it against the share groups, and emits that RTL from a Jinja2 template — proven end-to-end (generate → lint → simulate → PASS).

**Architecture:** One vertical slice in two task groups. **Group A** hand-authors the synthesizable, simulatable RTL (one shared adder, `op_sel` config input, combinational latency-0 ready/valid join) and its TB. **Group B** builds `fabric_gen` (general parser + share-group validator; group-1-only Jinja2 RTL emission) with a golden-file test asserting the rendered SV is byte-identical to the committed RTL, plus a demo runner that closes the loop.

**Tech Stack:** SystemVerilog (Verilator 5.044 primary sim/lint, VCS sign-off); Python 3.11 (`jinja2`, `pyyaml`, `pytest`).

**Spec:** `docs/specs/2026-05-31-fu-add-sub-design.md`

**Conventions:** Named `begin/end` blocks; `iter_varN` loop vars; `initial`/`#delay`/`$display` only in TB; synth subset in design (no latches/tristate/initial/delay, sync reset, single clock). Verilator load: `module load verilator/5.044`.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `ops/int_arith/add_sub/fu_add_sub.sv` | The shared add/sub FU (design) |
| `tb/int_arith/add_sub/tb_fu_add_sub.sv` | Self-checking testbench |
| `tb/int_arith/add_sub/run.sh` | Reproducible lint + sim (both widths) |
| `generator/fabric_gen/__init__.py` | Package exports |
| `generator/fabric_gen/errors.py` | Error types + categories |
| `generator/fabric_gen/parser.py` | `parse_op_string` |
| `generator/fabric_gen/sharegroups.py` | 19-group table + `validate` |
| `generator/fabric_gen/registry.py` | Load `registry.yaml`, lookup by ops |
| `generator/fabric_gen/generator.py` | `generate()` orchestration |
| `generator/fabric_gen/__main__.py` | CLI |
| `generator/templates/fu_add_sub.sv.j2` | Group-1 RTL template |
| `generator/pyproject.toml` | Package metadata + deps |
| `tests/conftest.py` | Put `generator/` on `sys.path` |
| `tests/test_parser.py`, `test_sharegroups.py`, `test_generator.py` | Unit + golden tests |
| `demo.sh` | End-to-end demo (generate → lint → sim → PASS) |
| `README.md` | Project overview + usage |

---

## Group A — RTL + Testbench

### Task 1: Scaffold + failing testbench (TDD red)

**Files:**
- Create: `ops/int_arith/add_sub/fu_add_sub.sv` (interface stub — wrong datapath)
- Create: `tb/int_arith/add_sub/tb_fu_add_sub.sv`

- [ ] **Step 1: Initialize git (optional but enables the commit workflow)**

```bash
cd /edata1/will/fabric_op_gen
git init -q && printf 'build/\n*.vcd\n*.log\nobj_dir*/\nsimv*\ncsrc/\n__pycache__/\n*.pyc\n.superpowers/\n' > .gitignore
git add -A && git commit -q -m "chore: baseline scaffold + docs"
```
(If you track changes another way, skip git steps throughout.)

- [ ] **Step 2: Write the interface STUB (compiles, intentionally wrong output)**

Create `ops/int_arith/add_sub/fu_add_sub.sv`:

```systemverilog
// fu_add_sub.sv -- Fabric FU for share group add_sub.
// STUB: interface only, datapath intentionally wrong (replaced in Task 2).

module fu_add_sub #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,

  input  logic [WIDTH-1:0]  in_data_0,
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // verilator lint_off UNUSEDSIGNAL
  logic unused_op_sel;
  assign unused_op_sel = op_sel;
  // verilator lint_on UNUSEDSIGNAL
  assign out_data = {WIDTH{1'b0}};   // STUB wrong

endmodule : fu_add_sub
```

- [ ] **Step 3: Write the self-checking testbench**

Create `tb/int_arith/add_sub/tb_fu_add_sub.sv`:

```systemverilog
// tb_fu_add_sub.sv -- Self-checking testbench for fu_add_sub (share group 1).
// Combinational DUT: drive operands + op_sel, settle, compare to an independent
// golden model (uses +/- directly). Directed corners + randomized. Parameterized
// by WIDTH; override per run (verilator -GWIDTH=8, VCS -pvalue+...WIDTH=8).
// Testbench only.

`timescale 1ns/1ps

module tb_fu_add_sub #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned NRAND = 10000
);

  logic              clk;
  logic              rst_n;
  logic              op_sel;
  logic [WIDTH-1:0]  in_data_0, in_data_1;
  logic              in_valid_0, in_valid_1;
  logic              in_ready_0, in_ready_1;
  logic [WIDTH-1:0]  out_data;
  logic              out_valid;
  logic              out_ready;
  integer            error_count;

  fu_add_sub #(.WIDTH(WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [WIDTH-1:0] golden(input logic [WIDTH-1:0] a,
                                              input logic [WIDTH-1:0] b,
                                              input logic             sel);
    begin : golden_body
      golden = sel ? (a - b) : (a + b);
    end : golden_body
  endfunction

  task automatic check_vec(input logic [WIDTH-1:0] a,
                           input logic [WIDTH-1:0] b,
                           input logic             sel);
    logic [WIDTH-1:0] exp;
    begin : check_vec_body
      op_sel = sel; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(a, b, sel);
      if (out_data !== exp) begin : data_mismatch
        $display("FAIL data: op_sel=%0b a=%h b=%h got=%h exp=%h", sel, a, b, out_data, exp);
        error_count = error_count + 1;
      end : data_mismatch
      if (out_valid !== 1'b1) begin : valid_low
        $display("FAIL out_valid low with both operands valid (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : valid_low
      if ((in_ready_0 !== 1'b1) || (in_ready_1 !== 1'b1)) begin : ready_low
        $display("FAIL in_ready low with out_ready & out_valid high (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : ready_low
    end : check_vec_body
  endtask

  task automatic check_backpressure(input logic [WIDTH-1:0] a,
                                    input logic [WIDTH-1:0] b,
                                    input logic             sel);
    begin : check_bp_body
      op_sel = sel; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      #1;
      if (out_valid !== 1'b1) begin : bp_valid
        $display("FAIL backpressure: out_valid must stay high (indep of out_ready)");
        error_count = error_count + 1;
      end : bp_valid
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin : bp_ready
        $display("FAIL backpressure: in_ready must be low when out_ready=0");
        error_count = error_count + 1;
      end : bp_ready
    end : check_bp_body
  endtask

  task automatic check_input_invalid;
    begin : check_inv_body
      op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : inv_valid
        $display("FAIL: out_valid high when in_valid_0 low");
        error_count = error_count + 1;
      end : inv_valid
      if (in_ready_1 !== 1'b0) begin : inv_ready
        $display("FAIL: in_ready_1 high when join incomplete");
        error_count = error_count + 1;
      end : inv_ready
    end : check_inv_body
  endtask

  initial begin : main
    integer            iter_var0;
    logic [WIDTH-1:0]  ra, rb;
    logic [31:0]       rt0, rt1, rts;
    logic              rs;

    error_count = 0;
    op_sel = 1'b0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Directed: addition (op_sel = 0)
    check_vec({WIDTH{1'b0}},             {WIDTH{1'b0}}, 1'b0); // 0 + 0
    check_vec({WIDTH{1'b1}},             {WIDTH{1'b0}}, 1'b0); // a + 0
    check_vec({{(WIDTH-1){1'b0}}, 1'b1}, {WIDTH{1'b1}}, 1'b0); // 1 + max -> wrap
    check_vec({WIDTH{1'b1}},             {WIDTH{1'b1}}, 1'b0); // max + max

    // Directed: subtraction (op_sel = 1)
    check_vec(WIDTH'(32'd5), WIDTH'(32'd3),             1'b1); // 5 - 3
    check_vec(WIDTH'(32'd3), WIDTH'(32'd5),             1'b1); // 3 - 5 -> wrap
    check_vec({WIDTH{1'b0}}, {{(WIDTH-1){1'b0}}, 1'b1}, 1'b1); // 0 - 1 -> all ones
    check_vec({1'b1, {(WIDTH-1){1'b0}}}, {{(WIDTH-1){1'b0}}, 1'b1}, 1'b1); // min - 1
    check_vec({WIDTH{1'b1}}, {WIDTH{1'b1}},            1'b1); // a - a -> 0

    // op_sel toggle on identical operands
    check_vec(WIDTH'(32'hDEAD_BEEF), WIDTH'(32'h0000_0001), 1'b0);
    check_vec(WIDTH'(32'hDEAD_BEEF), WIDTH'(32'h0000_0001), 1'b1);

    // Handshake corners
    check_backpressure(WIDTH'(32'd7), WIDTH'(32'd2), 1'b0);
    check_input_invalid();

    // Randomized
    for (iter_var0 = 0; iter_var0 < NRAND; iter_var0 = iter_var0 + 1) begin : rand_loop
      rt0 = $random; rt1 = $random; rts = $random;
      ra = WIDTH'(rt0); rb = WIDTH'(rt1); rs = rts[0];
      check_vec(ra, rb, rs);
    end : rand_loop

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_add_sub WIDTH=%0d, %0d random vectors, 0 mismatches", WIDTH, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_add_sub WIDTH=%0d, %0d mismatches", WIDTH, error_count);
      $fatal(1);
    end : fail_blk

    $finish;
  end : main

endmodule : tb_fu_add_sub
```

- [ ] **Step 4: Run the TB against the stub — verify it FAILS**

```bash
cd /edata1/will/fabric_op_gen
module load verilator/5.044
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
  --top-module tb_fu_add_sub -GWIDTH=32 --Mdir build/obj_w32 -o sim_w32 \
  ops/int_arith/add_sub/fu_add_sub.sv tb/int_arith/add_sub/tb_fu_add_sub.sv
./build/obj_w32/sim_w32 ; echo "exit=$?"
```
Expected: many `FAIL data:` lines, then `FAIL: ... mismatches`, non-zero exit (the `$fatal`). This proves the TB actually checks the datapath.

- [ ] **Step 5: Commit**

```bash
git add ops/int_arith/add_sub/fu_add_sub.sv tb/int_arith/add_sub/tb_fu_add_sub.sv
git commit -q -m "test(rtl): add self-checking TB + fu_add_sub interface stub (red)"
```

---

### Task 2: Implement the shared-adder datapath (TDD green)

**Files:**
- Modify: `ops/int_arith/add_sub/fu_add_sub.sv`

- [ ] **Step 1: Replace the stub with the real module**

Overwrite `ops/int_arith/add_sub/fu_add_sub.sv` with the final, generator-canonical text (the template in Task 8 must render byte-identical to this):

```systemverilog
// fu_add_sub.sv -- Fabric FU for share group add_sub.
// op_list: arith.addi, arith.subi
//   op_sel = 0 -> out = a + b   (arith.addi)
//   op_sel = 1 -> out = a - b   (arith.subi)  [add with operand B inverted + carry-in]
//
// One shared adder; op_sel is a held config input (no handshake).
// Combinational, intrinsic latency 0.

module fu_add_sub #(
  parameter int unsigned WIDTH = 32
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,

  input  logic [WIDTH-1:0]  in_data_0,
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // Shared datapath: subtract = add with operand B inverted and carry-in = 1.
  logic [WIDTH-1:0] b_eff;
  assign b_eff    = op_sel ? ~in_data_1 : in_data_1;
  assign out_data = in_data_0 + b_eff + {{(WIDTH-1){1'b0}}, op_sel};

endmodule : fu_add_sub
```

- [ ] **Step 2: Run the TB — verify it PASSES**

```bash
module load verilator/5.044
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
  --top-module tb_fu_add_sub -GWIDTH=32 --Mdir build/obj_w32 -o sim_w32 \
  ops/int_arith/add_sub/fu_add_sub.sv tb/int_arith/add_sub/tb_fu_add_sub.sv
./build/obj_w32/sim_w32 ; echo "exit=$?"
```
Expected: `PASS: fu_add_sub WIDTH=32, 10000 random vectors, 0 mismatches`, exit 0.

- [ ] **Step 3: Verify the design lints clean (strict)**

```bash
verilator --lint-only -Wall ops/int_arith/add_sub/fu_add_sub.sv ; echo "exit=$?"
```
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add ops/int_arith/add_sub/fu_add_sub.sv
git commit -q -m "feat(rtl): shared-adder fu_add_sub (op_sel add/sub), TB passes (green)"
```

---

### Task 3: Width coverage + reproducible run script

**Files:**
- Create: `tb/int_arith/add_sub/run.sh`

- [ ] **Step 1: Verify the narrow-width case passes**

```bash
module load verilator/5.044
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
  --top-module tb_fu_add_sub -GWIDTH=8 --Mdir build/obj_w8 -o sim_w8 \
  ops/int_arith/add_sub/fu_add_sub.sv tb/int_arith/add_sub/tb_fu_add_sub.sv
./build/obj_w8/sim_w8 ; echo "exit=$?"
```
Expected: `PASS: fu_add_sub WIDTH=8, 10000 random vectors, 0 mismatches`, exit 0.

- [ ] **Step 2: Write the run script**

Create `tb/int_arith/add_sub/run.sh`:

```bash
#!/usr/bin/env bash
# Lint + simulate fu_add_sub at WIDTH 32 and 8. Requires verilator on PATH
# (run `module load verilator/5.044` first, or this script loads it if available).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

RTL="ops/int_arith/add_sub/fu_add_sub.sv"
TB="tb/int_arith/add_sub/tb_fu_add_sub.sv"

echo "== lint =="
verilator --lint-only -Wall "$RTL"

for W in 32 8; do
  echo "== sim WIDTH=$W =="
  verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
    --top-module tb_fu_add_sub -GWIDTH="$W" --Mdir "build/obj_w$W" -o "sim_w$W" \
    "$RTL" "$TB"
  "build/obj_w$W/sim_w$W" | tee "build/sim_w$W.log"
  grep -q "^PASS:" "build/sim_w$W.log"
done
echo "ALL RTL CHECKS PASSED"
```

- [ ] **Step 3: Run it end to end**

```bash
chmod +x tb/int_arith/add_sub/run.sh
./tb/int_arith/add_sub/run.sh ; echo "exit=$?"
```
Expected: lint clean, both widths `PASS`, final `ALL RTL CHECKS PASSED`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add tb/int_arith/add_sub/run.sh
git commit -q -m "test(rtl): width=8 coverage + run.sh lint/sim script"
```

---

### Task 4: VCS sign-off (secondary simulator)

**Files:** none (verification only)

- [ ] **Step 1: Compile + run under VCS at WIDTH=32**

```bash
module load synopsys/vcs/X-2025.06-SP1
vcs -full64 -sverilog -timescale=1ns/1ps -top tb_fu_add_sub \
  -pvalue+tb_fu_add_sub.WIDTH=32 \
  ops/int_arith/add_sub/fu_add_sub.sv tb/int_arith/add_sub/tb_fu_add_sub.sv \
  -o build/simv_w32 2>&1 | tee build/vcs_w32.log
./build/simv_w32 | tee build/vcs_sim_w32.log
grep -q "^PASS:" build/vcs_sim_w32.log
```
Expected: `PASS: fu_add_sub WIDTH=32, ...`.

- [ ] **Step 2: If VCS fails with `libelf.so.1: wrong ELF class: ELFCLASS64`**

This is the known 32/64-bit lib mismatch on this host. Try, in order:
1. Ensure `-full64` is present (it forces the 64-bit binary).
2. `export VCS_HOME` is set by the module; verify `which vcs` resolves under the module.
3. Prepend a 64-bit libelf to the path: `export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH` before invoking.

If it still cannot run, **record VCS as blocked in the commit message and rely on the Verilator gate (Tasks 2–3) as the authoritative result.** Do not block the rest of the plan on VCS.

- [ ] **Step 3: Commit the result note**

```bash
git add -A
git commit -q -m "test(rtl): VCS sign-off run (or documented libelf blocker)" --allow-empty
```

---

## Group B — `fabric_gen` Python package

### Task 5: Package scaffold + parser (TDD)

**Files:**
- Create: `generator/pyproject.toml`, `generator/fabric_gen/__init__.py`, `generator/fabric_gen/errors.py`, `generator/fabric_gen/parser.py`
- Create: `tests/conftest.py`, `tests/test_parser.py`

- [ ] **Step 1: Write package metadata**

Create `generator/pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "fabric_gen"
version = "0.1.0"
description = "Fabric FU RTL generator (share-group aware)"
requires-python = ">=3.10"
dependencies = ["jinja2>=3.0", "pyyaml>=6.0"]

[project.optional-dependencies]
test = ["pytest>=7.0"]

[project.scripts]
fabric-gen = "fabric_gen.__main__:main"

[tool.setuptools]
packages = ["fabric_gen"]
```

- [ ] **Step 2: Write error types**

Create `generator/fabric_gen/errors.py`:

```python
"""Error types for fabric_gen. `category` mirrors loom's gen-sv error contract."""


class FabricGenError(Exception):
    category = "error"


class ParseError(FabricGenError):
    category = "parse"


class ShareGroupError(FabricGenError):
    category = "share-group"


class TemplateNotImplemented(FabricGenError):
    category = "unsupported-op"
```

- [ ] **Step 3: Write the failing parser test**

Create `tests/conftest.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "generator"))
```

Create `tests/test_parser.py`:

```python
import pytest

from fabric_gen.parser import parse_op_string
from fabric_gen.errors import ParseError


def test_single_member_no_at():
    assert parse_op_string("fabric.op[arith.addi]").op_list == ["arith.addi"]


def test_two_members_mixed_at():
    p = parse_op_string("fabric.op[@arith.addi, arith.subi]")
    assert p.op_list == ["arith.addi", "arith.subi"]


def test_two_members_both_at_and_spaces():
    p = parse_op_string("fabric.op[ @arith.addi ,  @arith.subi ]")
    assert p.op_list == ["arith.addi", "arith.subi"]


def test_missing_shell_raises():
    with pytest.raises(ParseError):
        parse_op_string("arith.addi")


def test_empty_list_raises():
    with pytest.raises(ParseError):
        parse_op_string("fabric.op[]")


def test_bad_member_raises():
    with pytest.raises(ParseError):
        parse_op_string("fabric.op[Arith.AddI!]")
```

- [ ] **Step 4: Run the tests — verify they FAIL**

```bash
cd /edata1/will/fabric_op_gen
PYTHONPATH=generator python -m pytest tests/test_parser.py -v
```
Expected: collection error / `ModuleNotFoundError: fabric_gen.parser` (parser.py does not exist yet).

- [ ] **Step 5: Implement the parser**

Create `generator/fabric_gen/parser.py`:

```python
"""Parse a `fabric.op[...]` string into an op list."""

import re
from dataclasses import dataclass

from .errors import ParseError

_MEMBER_RE = re.compile(r"^[a-z]+\.[a-z0-9_]+$")


@dataclass
class ParsedOp:
    op_list: list


def parse_op_string(s: str) -> ParsedOp:
    text = s.strip()
    if not (text.startswith("fabric.op[") and text.endswith("]")):
        raise ParseError(f"expected 'fabric.op[...]', got {s!r}")
    inner = text[len("fabric.op["):-1]
    members = []
    for raw in inner.split(","):
        m = raw.strip()
        if m.startswith("@"):
            m = m[1:].strip()
        if not m:
            continue
        if not _MEMBER_RE.match(m):
            raise ParseError(f"invalid op member {m!r}")
        members.append(m)
    if not members:
        raise ParseError("empty op_list")
    return ParsedOp(op_list=members)
```

Create `generator/fabric_gen/__init__.py`:

```python
from .errors import (
    FabricGenError,
    ParseError,
    ShareGroupError,
    TemplateNotImplemented,
)
from .parser import ParsedOp, parse_op_string

__all__ = [
    "FabricGenError",
    "ParseError",
    "ShareGroupError",
    "TemplateNotImplemented",
    "ParsedOp",
    "parse_op_string",
]
```

- [ ] **Step 6: Run the tests — verify they PASS**

```bash
PYTHONPATH=generator python -m pytest tests/test_parser.py -v
```
Expected: 6 passed.

- [ ] **Step 7: Commit**

```bash
git add generator/pyproject.toml generator/fabric_gen/ tests/conftest.py tests/test_parser.py
git commit -q -m "feat(gen): fabric_gen scaffold + op-string parser"
```

---

### Task 6: Share-group validator (TDD)

**Files:**
- Create: `generator/fabric_gen/sharegroups.py`, `tests/test_sharegroups.py`

- [ ] **Step 1: Write the failing validator test**

Create `tests/test_sharegroups.py`:

```python
import pytest

from fabric_gen.sharegroups import validate
from fabric_gen.errors import ShareGroupError


def test_group1_add_sub():
    g = validate(["arith.addi", "arith.subi"])
    assert g.index == 1


def test_group2_div_rem_signed():
    g = validate(["arith.divsi", "arith.remsi"])
    assert g.index == 2


def test_singleton_in_group_ok():
    g = validate(["arith.addi"])
    assert g.index == 1


def test_singleton_standalone_ok():
    g = validate(["arith.muli"])
    assert g.index == 0


def test_not_in_any_group_raises():
    with pytest.raises(ShareGroupError):
        validate(["arith.addi", "arith.muli"])


def test_cross_group_raises():
    with pytest.raises(ShareGroupError):
        validate(["arith.addi", "arith.subf"])
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
PYTHONPATH=generator python -m pytest tests/test_sharegroups.py -v
```
Expected: `ModuleNotFoundError: fabric_gen.sharegroups`.

- [ ] **Step 3: Implement the validator**

Create `generator/fabric_gen/sharegroups.py`:

```python
"""Hardware share groups, mirroring docs/fabric_hardware_share_groups.md."""

from dataclasses import dataclass

from .errors import ShareGroupError

SHARE_GROUPS = [
    {"arith.addi", "arith.subi"},                                      # 1
    {"arith.divsi", "arith.remsi"},                                    # 2
    {"arith.divui", "arith.remui"},                                    # 3
    {"arith.shli", "arith.shrsi", "arith.shrui"},                      # 4
    {"arith.andi", "arith.ori", "arith.xori"},                         # 5
    {"arith.minsi", "arith.maxsi"},                                    # 6
    {"arith.minui", "arith.maxui"},                                    # 7
    {"arith.sitofp", "arith.uitofp"},                                  # 8
    {"arith.fptosi", "arith.fptoui"},                                  # 9
    {"arith.addf", "arith.subf"},                                      # 10
    {"arith.divf", "arith.remf"},                                      # 11
    {"arith.minimumf", "arith.maximumf"},                              # 12
    {"math.sin", "math.cos"},                                          # 13
    {"math.sinh", "math.cosh"},                                        # 14
    {"math.exp", "math.exp2", "math.expm1"},                           # 15
    {"math.log", "math.log2", "math.log10", "math.log1p"},             # 16
    {"math.floor", "math.ceil", "math.round", "math.trunc", "math.roundeven"},  # 17
    {"math.sqrt", "math.rsqrt"},                                       # 18
    {"math.tanh", "math.erf"},                                         # 19
]


@dataclass
class ShareGroup:
    index: int            # 1..19, or 0 for a synthetic singleton
    members: frozenset


def _group_of(op):
    for i, members in enumerate(SHARE_GROUPS, start=1):
        if op in members:
            return i
    return None


def validate(op_list) -> ShareGroup:
    if len(op_list) == 1:
        idx = _group_of(op_list[0])
        if idx is not None:
            return ShareGroup(index=idx, members=frozenset(SHARE_GROUPS[idx - 1]))
        return ShareGroup(index=0, members=frozenset(op_list))

    groups = {op: _group_of(op) for op in op_list}
    missing = [op for op, g in groups.items() if g is None]
    if missing:
        raise ShareGroupError(
            f"ops {missing} are not in any multi-member share group; a "
            f"multi-member op_list requires every member to share one group"
        )
    distinct = set(groups.values())
    if len(distinct) != 1:
        raise ShareGroupError(
            f"ops {op_list} span multiple share groups {sorted(distinct)}; all "
            f"members of a multi-member op_list must be in the same group"
        )
    idx = distinct.pop()
    return ShareGroup(index=idx, members=frozenset(SHARE_GROUPS[idx - 1]))
```

Append to `generator/fabric_gen/__init__.py` exports:

```python
from .sharegroups import ShareGroup, validate  # add this import line
```
and add `"ShareGroup"`, `"validate"` to `__all__`.

- [ ] **Step 4: Run it — verify it PASSES**

```bash
PYTHONPATH=generator python -m pytest tests/test_sharegroups.py -v
```
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add generator/fabric_gen/sharegroups.py generator/fabric_gen/__init__.py tests/test_sharegroups.py
git commit -q -m "feat(gen): share-group validator (19-group table + verifier rules)"
```

---

### Task 7: Registry loader (TDD)

**Files:**
- Create: `generator/fabric_gen/registry.py`; add a test to `tests/test_generator.py`

- [ ] **Step 1: Write the failing registry test**

Create `tests/test_generator.py` (first test only for now):

```python
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def test_registry_lookup_add_sub():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.addi", "arith.subi"], reg)
    assert grp["name"] == "add_sub"
    assert grp["rtl_module"] == "fu_add_sub.sv"
    assert grp["params"]["width"] == 32
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py::test_registry_lookup_add_sub -v
```
Expected: `ModuleNotFoundError: fabric_gen.registry`.

- [ ] **Step 3: Implement the registry loader**

Create `generator/fabric_gen/registry.py`:

```python
"""Load and query registry.yaml."""

import yaml

from .errors import FabricGenError


def load_registry(path):
    with open(path) as f:
        data = yaml.safe_load(f)
    return data["groups"]


def lookup_by_ops(op_list, registry):
    target = set(op_list)
    for grp in registry:
        if set(grp["ops"]) == target:
            return grp
    raise FabricGenError(f"no registry group matches ops {sorted(target)}")
```

- [ ] **Step 4: Run it — verify it PASSES**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py::test_registry_lookup_add_sub -v
```
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add generator/fabric_gen/registry.py tests/test_generator.py
git commit -q -m "feat(gen): registry.yaml loader + lookup-by-ops"
```

---

### Task 8: Generator + template + golden-file test (TDD)

**Files:**
- Create: `generator/fabric_gen/generator.py`, `generator/templates/fu_add_sub.sv.j2`
- Modify: `tests/test_generator.py`, `generator/fabric_gen/__init__.py`

- [ ] **Step 1: Write the failing generator tests**

Append to `tests/test_generator.py`:

```python
def test_generate_group1_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addi, @arith.subi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_add_sub.sv"
    text = out.read_text()
    assert "module fu_add_sub" in text
    assert "input  logic              op_sel," in text
    assert "in_data_0 + b_eff" in text


def test_generate_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addi, @arith.subi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/add_sub/fu_add_sub.sv"
    assert out.read_text() == ref.read_text()


def test_generate_unimplemented_group_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import TemplateNotImplemented

    with pytest.raises(TemplateNotImplemented):
        generate("fabric.op[@arith.divsi, @arith.remsi]", tmp_path,
                 registry_path=ROOT / "registry.yaml")


def test_generate_illegal_op_list_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import ShareGroupError

    with pytest.raises(ShareGroupError):
        generate("fabric.op[@arith.addi, @arith.muli]", tmp_path,
                 registry_path=ROOT / "registry.yaml")
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py -v
```
Expected: `ModuleNotFoundError: fabric_gen.generator` for the new tests.

- [ ] **Step 3: Write the Jinja2 template**

Create `generator/templates/fu_add_sub.sv.j2`:

```jinja
// {{ module_name }}.sv -- Fabric FU for share group add_sub.
// op_list: {{ op_list | join(', ') }}
//   op_sel = 0 -> out = a + b   ({{ op_list[0] }})
//   op_sel = 1 -> out = a - b   ({{ op_list[1] }})  [add with operand B inverted + carry-in]
//
// One shared adder; op_sel is a held config input (no handshake).
// Combinational, intrinsic latency 0.

module {{ module_name }} #(
  parameter int unsigned WIDTH = {{ width }}
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic              clk,
  input  logic              rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic              op_sel,

  input  logic [WIDTH-1:0]  in_data_0,
  input  logic              in_valid_0,
  output logic              in_ready_0,

  input  logic [WIDTH-1:0]  in_data_1,
  input  logic              in_valid_1,
  output logic              in_ready_1,

  output logic [WIDTH-1:0]  out_data,
  output logic              out_valid,
  input  logic              out_ready
);

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // Shared datapath: subtract = add with operand B inverted and carry-in = 1.
  logic [WIDTH-1:0] b_eff;
  assign b_eff    = op_sel ? ~in_data_1 : in_data_1;
  assign out_data = in_data_0 + b_eff + {{ carry_term }};

endmodule : {{ module_name }}
```

(The `carry_term` context variable carries the literal `{{(WIDTH-1){1'b0}}, op_sel}` so the SV replication braces don't collide with Jinja's `{{ }}`.)

- [ ] **Step 4: Implement the generator**

Create `generator/fabric_gen/generator.py`:

```python
"""Orchestrate: parse -> validate -> registry lookup -> render template -> write."""

from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from .parser import parse_op_string
from .sharegroups import validate
from .registry import load_registry, lookup_by_ops
from .errors import TemplateNotImplemented

_TEMPLATES = Path(__file__).resolve().parents[1] / "templates"
_DEFAULT_REGISTRY = Path(__file__).resolve().parents[2] / "registry.yaml"

# Group name -> template file. Only group 1 is wired for now.
_TEMPLATE_MAP = {
    "add_sub": "fu_add_sub.sv.j2",
}

_CARRY_TERM = "{{(WIDTH-1){1'b0}}, op_sel}"


def generate(op_string, out_dir, width=None, registry_path=None):
    parsed = parse_op_string(op_string)
    validate(parsed.op_list)  # raises ShareGroupError on illegal combinations

    registry = load_registry(registry_path or _DEFAULT_REGISTRY)
    grp = lookup_by_ops(parsed.op_list, registry)
    name = grp["name"]
    if name not in _TEMPLATE_MAP:
        raise TemplateNotImplemented(
            f"RTL template for share group '{name}' is not yet implemented"
        )

    rtl_module = grp["rtl_module"]
    module_name = rtl_module[:-3] if rtl_module.endswith(".sv") else rtl_module
    eff_width = width if width is not None else grp.get("params", {}).get("width", 32)

    env = Environment(
        loader=FileSystemLoader(str(_TEMPLATES)),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    tmpl = env.get_template(_TEMPLATE_MAP[name])
    text = tmpl.render(
        module_name=module_name,
        width=eff_width,
        op_list=parsed.op_list,
        carry_term=_CARRY_TERM,
    )

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / rtl_module
    out_path.write_text(text)
    return out_path
```

Add to `generator/fabric_gen/__init__.py`:

```python
from .generator import generate  # add this import line
```
and add `"generate"` to `__all__`.

- [ ] **Step 5: Run the generator tests — verify they PASS**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py -v
```
Expected: all pass. If `test_generate_golden_matches_committed_rtl` fails on a
diff, the template text and the committed `fu_add_sub.sv` differ — reconcile them
byte-for-byte (they are intentionally identical) and re-run.

- [ ] **Step 6: Sanity-check the rendered file lints clean**

```bash
PYTHONPATH=generator python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/gencheck 2>/dev/null || true
module load verilator/5.044
verilator --lint-only -Wall build/gencheck/fu_add_sub.sv ; echo "exit=$?"
```
(`__main__` lands in Task 9; if it errors here, skip — the golden test already
proved render correctness. Expected once Task 9 lands: exit 0.)

- [ ] **Step 7: Commit**

```bash
git add generator/fabric_gen/generator.py generator/templates/fu_add_sub.sv.j2 \
        generator/fabric_gen/__init__.py tests/test_generator.py
git commit -q -m "feat(gen): Jinja2 template + generate() with golden-file test"
```

---

### Task 9: CLI (TDD)

**Files:**
- Create: `generator/fabric_gen/__main__.py`; add a test to `tests/test_generator.py`

- [ ] **Step 1: Write the failing CLI test**

Append to `tests/test_generator.py`:

```python
def test_cli_generates_file(tmp_path, monkeypatch):
    from fabric_gen.__main__ import main

    monkeypatch.chdir(ROOT)  # so default registry.yaml resolves
    rc = main(["fabric.op[@arith.addi, @arith.subi]", "-o", str(tmp_path)])
    assert rc == 0
    assert (tmp_path / "fu_add_sub.sv").exists()


def test_cli_illegal_returns_nonzero(tmp_path, monkeypatch, capsys):
    from fabric_gen.__main__ import main

    monkeypatch.chdir(ROOT)
    rc = main(["fabric.op[@arith.addi, @arith.muli]", "-o", str(tmp_path)])
    assert rc == 1
    err = capsys.readouterr().err
    assert "fabric-gen error: share-group:" in err
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py::test_cli_generates_file -v
```
Expected: `ModuleNotFoundError`/`ImportError` for `fabric_gen.__main__`.

- [ ] **Step 3: Implement the CLI**

Create `generator/fabric_gen/__main__.py`:

```python
"""CLI: python -m fabric_gen '<op-string>' -o <dir> [--width N]."""

import argparse
import sys

from .generator import generate
from .errors import FabricGenError


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="fabric_gen",
        description="Generate Fabric FU SystemVerilog from a fabric.op[...] string.",
    )
    p.add_argument("op_string", help="e.g. 'fabric.op[@arith.addi, @arith.subi]'")
    p.add_argument("-o", "--out-dir", default=".", help="output directory")
    p.add_argument("--width", type=int, default=None, help="override data width")
    args = p.parse_args(argv)

    try:
        out = generate(args.op_string, args.out_dir, width=args.width)
    except FabricGenError as e:
        print(f"fabric-gen error: {e.category}: {e}", file=sys.stderr)
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the CLI tests — verify they PASS**

```bash
PYTHONPATH=generator python -m pytest tests/test_generator.py -v
```
Expected: all pass.

- [ ] **Step 5: Smoke-test the CLI by hand**

```bash
PYTHONPATH=generator python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/cli
PYTHONPATH=generator python -m fabric_gen "fabric.op[@arith.addi, @arith.muli]" -o build/cli ; echo "exit=$?"
```
Expected: first prints `build/cli/fu_add_sub.sv`; second prints
`fabric-gen error: share-group: ...` to stderr, exit 1.

- [ ] **Step 6: Commit**

```bash
git add generator/fabric_gen/__main__.py tests/test_generator.py
git commit -q -m "feat(gen): CLI entrypoint with loom-style error contract"
```

---

### Task 10: Demo runner + README + full e2e

**Files:**
- Create: `demo.sh`, `README.md`

- [ ] **Step 1: Write the demo runner**

Create `demo.sh` (repo root):

```bash
#!/usr/bin/env bash
# End-to-end demo: generate group-1 RTL, lint it, simulate the TB, expect PASS.
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/demo
rm -rf "$OUT"

echo "[demo] generate ..."
PYTHONPATH=generator python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  if type module >/dev/null 2>&1; then module load verilator/5.044; fi
fi

echo "[demo] lint ..."
verilator --lint-only -Wall "$OUT/fu_add_sub.sv"

echo "[demo] build + run TB ..."
verilator --binary --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
  --top-module tb_fu_add_sub -GWIDTH=32 --Mdir "$OUT/obj_dir" -o sim_w32 \
  "$OUT/fu_add_sub.sv" tb/int_arith/add_sub/tb_fu_add_sub.sv
"$OUT/obj_dir/sim_w32" | tee "$OUT/sim.log"
grep -q "^PASS:" "$OUT/sim.log"

echo "DEMO OK"
```

- [ ] **Step 2: Run the demo — verify end to end**

```bash
chmod +x demo.sh
./demo.sh ; echo "exit=$?"
```
Expected: prints the generated path, lint clean, `PASS: fu_add_sub WIDTH=32, ...`,
final `DEMO OK`, exit 0.

- [ ] **Step 3: Write the README**

Create `README.md` (repo root):

```markdown
# fabric_op_gen

Registry-driven generator of synthesizable, simulatable SystemVerilog Function
Units (FUs) for the loom `fabric` dialect. Each FU implements one hardware
**share group** — a set of software ops that share one physical datapath,
selected at runtime by an `op_sel` config knob.

## Layout

- `registry.yaml` — source of truth: the 19 share groups → module/params.
- `ops/<family>/<group>/` — generated/hand-authored RTL (e.g. `fu_add_sub.sv`).
- `tb/<family>/<group>/` — self-checking testbenches + `run.sh`.
- `generator/` — the `fabric_gen` Python package + Jinja2 `templates/`.
- `tests/` — pytest suite for the generator.
- `docs/` — specs (`fabric_hardware_share_groups.md`,
  `fabric_reconfigurable_ops.md`, `specs/`, `plans/`).

## Install

```bash
pip install -e generator        # provides the `fabric-gen` console script
# or run from source without installing:
export PYTHONPATH=generator
```

## Usage

```bash
# CLI
python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/rtl
# -> build/rtl/fu_add_sub.sv

# Python API
python -c "from fabric_gen import generate; print(generate('fabric.op[arith.addi]', 'build/rtl'))"
```

The parser and share-group validator are general (any op string, all 19 groups).
RTL emission is currently implemented for **share group 1 (`add_sub`)** only;
other valid groups report `template not yet implemented`.

## Tests

```bash
PYTHONPATH=generator python -m pytest tests/ -v
```

## Simulation / lint (Verilator, primary gate)

```bash
module load verilator/5.044
./tb/int_arith/add_sub/run.sh      # lint + sim at WIDTH 32 and 8
```

## End-to-end demo

```bash
./demo.sh        # generate -> lint -> simulate -> PASS -> "DEMO OK"
```

## Verification gate

- **Primary:** `verilator --lint-only -Wall` clean + TB `PASS` (WIDTH 32 and 8).
- **Sign-off:** VCS (`module load synopsys/vcs/...`, `vcs -full64 ...`) once the
  host `libelf` ELF-class issue is resolved.

## Extending to more groups

1. Add a synthesizable template under `generator/templates/`.
2. Register it in `_TEMPLATE_MAP` in `generator/fabric_gen/generator.py`.
3. Hand-author the matching self-checking TB under `tb/<family>/<group>/`.
4. Add a golden-file test. See `docs/specs/` for the design pattern.
```

- [ ] **Step 4: Run the whole suite once more (final gate)**

```bash
PYTHONPATH=generator python -m pytest tests/ -v
./tb/int_arith/add_sub/run.sh
./demo.sh
```
Expected: all pytest pass; `ALL RTL CHECKS PASSED`; `DEMO OK`.

- [ ] **Step 5: Commit**

```bash
git add demo.sh README.md
git commit -q -m "feat: end-to-end demo runner + README"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 RTL → Tasks 1–2; §4 TB → Task 1; §5 gate → Tasks 2–4;
§8.2 layout → Tasks 5–9; §8.3 parser → Task 5; §8.4 validator → Task 6; §8.5
registry → Task 7; §8.6 generate + §8.8 template → Task 8; §8.7 CLI → Task 9;
§9 tests → Tasks 5–9 (incl. golden file); §10 demo/e2e → Task 10; §11 README →
Task 10; §12 deps → Task 5 `pyproject.toml`. No gaps.

**Placeholder scan:** none — all code/commands are concrete.

**Type/name consistency:** `parse_op_string`/`ParsedOp.op_list`, `validate`/
`ShareGroup.index`, `load_registry`/`lookup_by_ops`, `generate(op_string, out_dir,
width, registry_path)`, error `category` attrs, and the `carry_term` template var
are consistent across tasks. The template renders byte-identical to the Task-2
RTL (enforced by the golden-file test in Task 8).
