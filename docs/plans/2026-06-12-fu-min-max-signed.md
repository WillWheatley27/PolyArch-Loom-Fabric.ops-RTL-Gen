# Share Group 6 RTL (`fu_min_max_signed`) — Implementation Plan

> Steps use checkbox (`- [ ]`) syntax. Combinational FU (like groups 1/4/5); the
> generator pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_min_max_signed.sv` (one shared signed comparator, 1-bit
`op_sel` selects min vs max) + self-checking testbench, wire the group-6 template
into `fabric_gen`, prove it end-to-end (generate → lint → simulate → PASS),
golden-file test exact.

**Spec:** `docs/specs/2026-06-12-fu-min-max-signed-design.md`
**Tech:** SystemVerilog (Verilator 5.044 via `module load`); Python (jinja2, pyyaml, pytest).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_min_max_signed.sv.j2` | Group-6 RTL template |
| `ops/int_arith/min_max_signed/fu_min_max_signed.sv` | Committed golden |
| `tb/int_arith/min_max_signed/tb_fu_min_max_signed.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["min_max_signed"]` |
| `registry.yaml` | Group 6 `status: not_started → verified` |
| `tests/test_generator.py` | Group-6 lookup + golden tests; fix stale test |
| `demo_min_max_signed.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_min_max_signed.sv.j2` per spec §3 (combinational; 1-bit op_sel;
      `$signed` comparator + output mux; clk/rst_n lint_off UNUSEDSIGNAL).
- [ ] A2. Add `"min_max_signed": "fu_min_max_signed.sv.j2"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.minsi, @arith.maxsi]" -o ops/int_arith/min_max_signed`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_min_max_signed.sv` (golden via `$signed` min/max; sign
      quadrants + equal + INT_MIN/MAX + handshake + randomized).
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at WIDTH=32 and WIDTH=8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_min_max_signed`,
      `test_generate_group6_writes_file`, `test_generate_group6_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 7
      (`fabric.op[@arith.minui, @arith.maxui]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 6 `status: verified`.
- [ ] C5. Write `demo_min_max_signed.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at WIDTH 32 and 8; golden-file
      test confirms byte-identical render; lint clean under `-Wall`.
