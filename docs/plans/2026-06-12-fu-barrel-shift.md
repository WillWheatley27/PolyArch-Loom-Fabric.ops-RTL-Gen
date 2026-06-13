# Share Group 4 RTL (`fu_barrel_shift`) — Implementation Plan

> Steps use checkbox (`- [ ]`) syntax. Combinational FU (like group 1); the
> generator pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_barrel_shift.sv` (one shared barrel shifter, 2-bit `op_sel`
selects shli/shrsi/shrui, RISC-V shift-amount masking) + self-checking
testbench, wire the group-4 template into `fabric_gen`, prove it end-to-end
(generate → lint → simulate → PASS), golden-file test exact.

**Spec:** `docs/specs/2026-06-12-fu-barrel-shift-design.md`
**Tech:** SystemVerilog (Verilator 5.044 via `module load`); Python (jinja2, pyyaml, pytest).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_barrel_shift.sv.j2` | Group-4 RTL template |
| `ops/int_arith/barrel_shift/fu_barrel_shift.sv` | Committed golden |
| `tb/int_arith/barrel_shift/tb_fu_barrel_shift.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["barrel_shift"]` |
| `registry.yaml` | Group 4 `status: not_started → verified` |
| `tests/test_generator.py` | Group-4 lookup + golden tests; fix stale test |
| `demo_barrel_shift.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_barrel_shift.sv.j2` per spec §3 (combinational; 2-bit op_sel;
      `shamt = in_data_1 & (WIDTH-1)`; case mux shli/shrsi/shrui; clk/rst_n
      lint_off UNUSEDSIGNAL).
- [ ] A2. Add `"barrel_shift": "fu_barrel_shift.sv.j2"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]" -o ops/int_arith/barrel_shift`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_barrel_shift.sv` (combinational golden with same mask;
      per-op directed + masking corners + sign cases + handshake + randomized).
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`) — must
      be warning-free (no UNUSEDSIGNAL/WIDTH issues).
- [ ] B3. Build + run TB at WIDTH=32 and WIDTH=8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_barrel_shift`,
      `test_generate_group4_writes_file`, `test_generate_group4_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 5
      (`fabric.op[@arith.andi, @arith.ori, @arith.xori]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 4 `status: verified`.
- [ ] C5. Write `demo_barrel_shift.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at WIDTH 32 and 8; golden-file
      test confirms byte-identical render; lint clean under `-Wall`.
