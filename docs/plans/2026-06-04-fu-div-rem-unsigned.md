# Share Group 3 RTL (`fu_div_rem_unsigned`) — Implementation Plan

> Steps use checkbox (`- [ ]`) syntax. Unsigned counterpart of group 2; the
> generator pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_div_rem_unsigned.sv` (shared restoring-division datapath,
`op_sel` selects quotient vs remainder, no sign handling) + self-checking
multi-cycle testbench, wire the group-3 template into `fabric_gen`, and prove it
end-to-end (generate → lint → simulate → PASS), golden-file test exact.

**Spec:** `docs/specs/2026-06-04-fu-div-rem-unsigned-design.md`
**Tech:** SystemVerilog (Verilator 5.044 via `module load`); Python (jinja2, pyyaml, pytest).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_div_rem_unsigned.sv.j2` | Group-3 RTL template |
| `ops/int_arith/div_rem_unsigned/fu_div_rem_unsigned.sv` | Committed golden |
| `tb/int_arith/div_rem_unsigned/tb_fu_div_rem_unsigned.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["div_rem_unsigned"]` |
| `registry.yaml` | Group 3 `status: not_started → verified` |
| `tests/test_generator.py` | Group-3 lookup + golden tests; fix stale test |
| `demo_div_rem_unsigned.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_div_rem_unsigned.sv.j2` per spec §3 (restoring-division FSM,
      no abs/no sign fix-up; `b==0` fast-path → quotient all-ones, remainder = a).
- [ ] A2. Add `"div_rem_unsigned": "fu_div_rem_unsigned.sv.j2"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.divui, @arith.remui]" -o ops/int_arith/div_rem_unsigned`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_div_rem_unsigned.sv` (unsigned golden = native `/` and `%`
      with `b==0` substitution; directed + handshake + randomized).
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at WIDTH=32 and WIDTH=8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_div_rem_unsigned`,
      `test_generate_group3_writes_file`, `test_generate_group3_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 4
      (`fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 3 `status: verified`.
- [ ] C5. Write `demo_div_rem_unsigned.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at WIDTH 32 and 8; golden-file
      test confirms byte-identical render.
