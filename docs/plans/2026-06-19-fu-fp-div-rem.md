# Share Group 11 RTL (`fu_fp_div_rem`) — Implementation Plan

> Hardest unit. Structural multi-cycle FP divider sharing a restoring-division
> core: divf (RNE) + remf (fmod). FTZ, 2-input join, variable latency FSM.

**Spec:** `docs/specs/2026-06-19-fu-fp-div-rem-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_fp_div_rem.sv.j2` | Group-11 RTL template |
| `ops/fp_arith/fp_div_rem/fu_fp_div_rem.sv` | Committed golden |
| `tb/fp_arith/fp_div_rem/tb_fu_fp_div_rem.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["fp_div_rem"]` |
| `registry.yaml` | Group 11 `status: not_started → verified` |
| `tests/test_generator.py` | Group-11 lookup + golden; fix stale test |
| `demos/demo_fp_div_rem.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_fp_div_rem.sv.j2`: clz function, special-case logic, FSM
      (IDLE/CALC/DONE), shared shift-subtract, divf normalize+RNE, remf
      normalize. FTZ, signed exp.
- [ ] A2. Add `"fp_div_rem"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@arith.divf, @arith.remf]" -o ops/fp_arith/fp_div_rem`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_fp_div_rem.sv`: directed (divf + remf) + random oracle
      (divf half-ULP; remf exact fmod via $rtoi for modest exponent gaps) +
      handshake. Multi-cycle (wait for out_valid).
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Debug divf then remf vs oracle.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_fp_div_rem`, `test_generate_group11_writes_file`,
      `test_generate_group11_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 12
      (`fabric.op[@arith.minimumf, @arith.maximumf]`).
- [ ] C3. `pytest` green. C4. registry group 11 `verified`. C5. `demos/demo_fp_div_rem.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:`; golden byte-identical; lint `-Wall` clean.
