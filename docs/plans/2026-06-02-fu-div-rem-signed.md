# Share Group 2 RTL (`fu_div_rem_signed`) — Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. This
> extends the existing `fabric_gen` slice to a second share group; the generator
> pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_div_rem_signed.sv` (one shared restoring-division datapath,
`op_sel` selects quotient vs remainder) + self-checking multi-cycle testbench,
wire the group-2 Jinja2 template into `fabric_gen`, and prove it end-to-end
(generate → lint → simulate → PASS), with the golden-file test exact by
construction.

**Tech Stack:** SystemVerilog (Verilator 5.044 via `module load verilator/5.044`);
Python 3.11 (`jinja2`, `pyyaml`, `pytest`).

**Spec:** `docs/specs/2026-06-02-fu-div-rem-signed-design.md`

**Conventions:** Match group 1 and loom — named `begin/end` blocks, sync reset,
single clock, synth subset in design (no `/`/`%`, no latches/tristate); `initial`/
`#delay`/`$display` only in TB.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_div_rem_signed.sv.j2` | Group-2 RTL template |
| `ops/int_arith/div_rem_signed/fu_div_rem_signed.sv` | Committed golden (generator output) |
| `tb/int_arith/div_rem_signed/tb_fu_div_rem_signed.sv` | Self-checking multi-cycle TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["div_rem_signed"]` |
| `registry.yaml` | Group 2 `status: not_started → verified` |
| `tests/test_generator.py` | Group-2 lookup + golden tests; fix stale unimplemented test |
| `demo_div_rem_signed.sh` | End-to-end demo (generate → lint → sim → PASS) |

---

## Group A — Template + generator wiring

- [ ] A1. Write `generator/templates/fu_div_rem_signed.sv.j2` — restoring-division
      FSM per spec §4 (`{{ module_name }}`, `{{ width }}`, `op_sel` comment from
      `op_list`). Real `clk`/`rst_n` (no UNUSEDSIGNAL waiver). `b==0` fast-path;
      `INT_MIN/-1` left to the natural datapath.
- [ ] A2. Add `"div_rem_signed": "fu_div_rem_signed.sv.j2"` to `_TEMPLATE_MAP` in
      `generator/fabric_gen/generator.py`.
- [ ] A3. Generate the committed golden:
      `python -m fabric_gen "fabric.op[@arith.divsi, @arith.remsi]" -o ops/int_arith/div_rem_signed`.

## Group B — Testbench + simulation

- [ ] B1. Write `tb/int_arith/div_rem_signed/tb_fu_div_rem_signed.sv` per spec §6
      (clocked, waits on `out_valid`, golden = native `$signed` `/` and `%` with
      `b==0` substitution; directed + handshake + randomized coverage).
- [ ] B2. `module load verilator/5.044`; lint the golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at `WIDTH=32` and `WIDTH=8`; require `PASS:` (no
      mismatches). Fix RTL/template and regenerate golden if any vector fails.

## Group C — Python tests + registry + demo

- [ ] C1. `tests/test_generator.py`: add `test_registry_lookup_div_rem_signed`,
      `test_generate_group2_writes_file`, `test_generate_group2_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 3
      (`fabric.op[@arith.divui, @arith.remui]`).
- [ ] C3. Run `pytest` — all green.
- [ ] C4. `registry.yaml`: set group 2 `status: verified`.
- [ ] C5. Write `demo_div_rem_signed.sh` (generate → lint → sim → grep PASS); run it.

## Verification gate

- [ ] All `pytest` tests pass.
- [ ] `verilator` TB run prints `PASS:` at WIDTH=32 and WIDTH=8.
- [ ] Golden-file test confirms rendered SV is byte-identical to the committed RTL.
