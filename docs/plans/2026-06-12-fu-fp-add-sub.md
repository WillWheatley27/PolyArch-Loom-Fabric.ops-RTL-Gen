# Share Group 10 RTL (`fu_fp_add_sub`) — Implementation Plan

> First FP arithmetic. Structural binary32 adder/subtractor, FTZ subnormals, RNE,
> 2-input join, latency-1. New `fp_arith` family path.

**Spec:** `docs/specs/2026-06-12-fu-fp-add-sub-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_fp_add_sub.sv.j2` | Group-10 RTL template |
| `ops/fp_arith/fp_add_sub/fu_fp_add_sub.sv` | Committed golden |
| `tb/fp_arith/fp_add_sub/tb_fu_fp_add_sub.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["fp_add_sub"]` |
| `registry.yaml` | Group 10 `status: not_started → verified` |
| `tests/test_generator.py` | Group-10 lookup + golden tests; fix stale test |
| `demos/demo_fp_add_sub.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_fp_add_sub.sv.j2`: subf sign-flip, unpack, special cases,
      align (guard/sticky), add/sub, normalize (leading-one count), RNE, range
      (Inf/FTZ). leading-one-detector function. Latency-1 2-input pipe.
- [ ] A2. Add `"fp_add_sub"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@arith.addf, @arith.subf]" -o ops/fp_arith/fp_add_sub`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_fp_add_sub.sv`: directed exact + random correct-rounding
      property (real oracle) + handshake corners.
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`); add
      targeted UNUSEDSIGNAL waivers for implicit-leading-1 / carry bits.
- [ ] B3. Build + run TB; require `PASS:`. Debug datapath against the oracle.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_fp_add_sub`, `test_generate_group10_writes_file`,
      `test_generate_group10_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 11
      (`fabric.op[@arith.divf, @arith.remf]`).
- [ ] C3. `pytest` green. C4. registry group 10 `verified`. C5. `demos/demo_fp_add_sub.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:`; golden byte-identical; lint `-Wall` clean.
