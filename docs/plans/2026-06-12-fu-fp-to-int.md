# Share Group 9 RTL (`fu_fp_to_int`) — Implementation Plan

> Reverse of group 8 (binary32 -> int32). Structural (Verilator can't sim loom's
> shortreal model), unary, latency-1, RISC-V FCVT saturation, truncate toward zero.

**Spec:** `docs/specs/2026-06-12-fu-fp-to-int-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_fp_to_int.sv.j2` | Group-9 RTL template |
| `ops/int_arith/fp_to_int/fu_fp_to_int.sv` | Committed golden |
| `tb/int_arith/fp_to_int/tb_fu_fp_to_int.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["fp_to_int"]` |
| `registry.yaml` | Group 9 `status: not_started → verified` |
| `tests/test_generator.py` | Group-9 lookup + golden tests; fix stale test |
| `demos/demo_fp_to_int.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_fp_to_int.sv.j2`: decode/extract, magnitude shift (truncate),
      RISC-V saturation per op_sel, latency-1 pipe. Params `FP_WIDTH`/`INT_WIDTH`.
- [ ] A2. Add `"fp_to_int"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@arith.fptosi, @arith.fptoui]" -o ops/int_arith/fp_to_int`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_fp_to_int.sv`: directed exact + random independent oracle
      (decode+classify; $rtoi/$floor) + handshake corners.
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_fp_to_int`, `test_generate_group9_writes_file`,
      `test_generate_group9_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 10
      (`fabric.op[@arith.addf, @arith.subf]`).
- [ ] C3. `pytest` green. C4. registry group 9 `verified`. C5. `demos/demo_fp_to_int.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:`; golden byte-identical; lint `-Wall` clean.
