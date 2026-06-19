# Share Group 12 RTL (`fu_fp_min_max`) — Implementation Plan

> Combinational FP min/max (like int min/max), monotonic-key compare, NaN-
> propagating, −0<+0. 2-input join, latency 0. No FTZ (selects an operand verbatim).

**Spec:** `docs/specs/2026-06-19-fu-fp-min-max-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_fp_min_max.sv.j2` | Group-12 RTL template |
| `ops/fp_arith/fp_min_max/fu_fp_min_max.sv` | Committed golden |
| `tb/fp_arith/fp_min_max/tb_fu_fp_min_max.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["fp_min_max"]` |
| `registry.yaml` | Group 12 `status: not_started → verified` |
| `tests/test_generator.py` | Group-12 lookup + golden; fix stale test |
| `demos/demo_fp_min_max.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_fp_min_max.sv.j2`: monotonic-key compare + NaN propagate +
      op_sel mux. clk/rst_n lint_off UNUSEDSIGNAL.
- [ ] A2. Add `"fp_min_max"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@arith.minimumf, @arith.maximumf]" -o ops/fp_arith/fp_min_max`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_fp_min_max.sv`: directed (quadrants, ±0, NaN, ±Inf, ties)
      + random (normal operands, real-decode oracle) + handshake.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB at WIDTH 32 and 8; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_fp_min_max`, `test_generate_group12_writes_file`,
      `test_generate_group12_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 13
      (`fabric.op[@math.sin, @math.cos]`).
- [ ] C3. `pytest` green. C4. registry group 12 `verified`. C5. `demos/demo_fp_min_max.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:`; golden byte-identical; lint `-Wall` clean.
