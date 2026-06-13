# Share Group 5 RTL (`fu_bitwise_alu`) — Implementation Plan

> Steps use checkbox (`- [ ]`) syntax. Combinational FU (like groups 1/4); the
> generator pipeline is unchanged except for one `_TEMPLATE_MAP` entry.

**Goal:** Build `fu_bitwise_alu.sv` (one shared bitwise ALU, 2-bit `op_sel`
selects andi/ori/xori) + self-checking testbench, wire the group-5 template into
`fabric_gen`, prove it end-to-end (generate → lint → simulate → PASS),
golden-file test exact.

**Spec:** `docs/specs/2026-06-12-fu-bitwise-alu-design.md`
**Tech:** SystemVerilog (Verilator 5.044 via `module load`); Python (jinja2, pyyaml, pytest).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_bitwise_alu.sv.j2` | Group-5 RTL template |
| `ops/int_arith/bitwise_alu/fu_bitwise_alu.sv` | Committed golden |
| `tb/int_arith/bitwise_alu/tb_fu_bitwise_alu.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["bitwise_alu"]` |
| `registry.yaml` | Group 5 `status: not_started → verified` |
| `tests/test_generator.py` | Group-5 lookup + golden tests; fix stale test |
| `demo_bitwise_alu.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_bitwise_alu.sv.j2` per spec §3 (combinational; 2-bit op_sel;
      case mux and/or/xor; clk/rst_n lint_off UNUSEDSIGNAL).
- [ ] A2. Add `"bitwise_alu": "fu_bitwise_alu.sv.j2"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.andi, @arith.ori, @arith.xori]" -o ops/int_arith/bitwise_alu`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_bitwise_alu.sv` (combinational golden &/|/^; per-op directed
      + handshake + randomized).
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at WIDTH=32 and WIDTH=8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_bitwise_alu`,
      `test_generate_group5_writes_file`, `test_generate_group5_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 6
      (`fabric.op[@arith.minsi, @arith.maxsi]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 5 `status: verified`.
- [ ] C5. Write `demo_bitwise_alu.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at WIDTH 32 and 8; golden-file
      test confirms byte-identical render; lint clean under `-Wall`.
