# Share Group 7 RTL (`fu_min_max_unsigned`) — Implementation Plan

> Steps use checkbox (`- [ ]`) syntax. Combinational FU (unsigned twin of group
> 6); the generator pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_min_max_unsigned.sv` (one shared unsigned comparator, 1-bit
`op_sel` selects min vs max) + self-checking testbench, wire the group-7 template
into `fabric_gen`, prove it end-to-end (generate → lint → simulate → PASS),
golden-file test exact.

**Spec:** `docs/specs/2026-06-12-fu-min-max-unsigned-design.md`
**Tech:** SystemVerilog (Verilator 5.044 via `module load`); Python (jinja2, pyyaml, pytest).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_min_max_unsigned.sv.j2` | Group-7 RTL template |
| `ops/int_arith/min_max_unsigned/fu_min_max_unsigned.sv` | Committed golden |
| `tb/int_arith/min_max_unsigned/tb_fu_min_max_unsigned.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["min_max_unsigned"]` |
| `registry.yaml` | Group 7 `status: not_started → verified` |
| `tests/test_generator.py` | Group-7 lookup + golden tests; fix stale test |
| `demos/demo_min_max_unsigned.sh` | End-to-end demo (in demos/ folder) |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_min_max_unsigned.sv.j2` per spec §3 (combinational; 1-bit
      op_sel; unsigned comparator `in_data_0 < in_data_1` + output mux;
      clk/rst_n lint_off UNUSEDSIGNAL).
- [ ] A2. Add `"min_max_unsigned": "fu_min_max_unsigned.sv.j2"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.minui, @arith.maxui]" -o ops/int_arith/min_max_unsigned`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_min_max_unsigned.sv` (unsigned golden; ordered/ties/
      extremes + MSB-set vectors + handshake + randomized).
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at WIDTH=32 and WIDTH=8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_min_max_unsigned`,
      `test_generate_group7_writes_file`, `test_generate_group7_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 8
      (`fabric.op[@arith.sitofp, @arith.uitofp]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 7 `status: verified`.
- [ ] C5. Write `demos/demo_min_max_unsigned.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at WIDTH 32 and 8; golden-file
      test confirms byte-identical render; lint clean under `-Wall`.
