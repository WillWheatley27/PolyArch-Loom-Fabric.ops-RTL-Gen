# Share Group 8 RTL (`fu_int_to_fp`) — Implementation Plan

> First FP group, first unary op, latency-1 pipeline. Structural IEEE-754
> binary32 encoder (Verilator can't sim loom's behavioral shortreal model).

**Goal:** Build `fu_int_to_fp.sv` (structural int32→binary32 with RNE; op_sel
selects signed/unsigned) + self-checking latency-1 testbench, wire the group-8
template into `fabric_gen` (now passing `params`), prove it end-to-end
(generate → lint → simulate → PASS), golden-file test exact.

**Spec:** `docs/specs/2026-06-12-fu-int-to-fp-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_int_to_fp.sv.j2` | Group-8 RTL template |
| `ops/int_arith/int_to_fp/fu_int_to_fp.sv` | Committed golden |
| `tb/int_arith/int_to_fp/tb_fu_int_to_fp.sv` | Self-checking TB |
| `generator/fabric_gen/generator.py` | Pass `params`; add `_TEMPLATE_MAP["int_to_fp"]` |
| `registry.yaml` | Group 8 `status: not_started → verified` |
| `tests/test_generator.py` | Group-8 lookup + golden tests; fix stale test |
| `demos/demo_int_to_fp.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_int_to_fp.sv.j2`: clz32 function, signedness preprocessor,
      normalize + RNE encoder, latency-1 pipeline. Parameter `INT_WIDTH` from
      `params.int_width`.
- [ ] A2. `generator.py`: add `params=grp.get("params", {})` to render(); add
      `"int_to_fp"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden:
      `python -m fabric_gen "fabric.op[@arith.sitofp, @arith.uitofp]" -o ops/int_arith/int_to_fp`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_int_to_fp.sv`: directed exact (hardcoded IEEE bits) +
      random half-ULP property (real arithmetic) + handshake corners.
- [ ] B2. `module load verilator/5.044`; lint golden (`--lint-only -Wall`).
- [ ] B3. Build + run TB at INT_WIDTH=32; require `PASS:`. Debug encoder if any
      directed vector fails.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_int_to_fp`, `test_generate_group8_writes_file`,
      `test_generate_group8_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 9
      (`fabric.op[@arith.fptosi, @arith.fptoui]`).
- [ ] C3. `pytest` — all green.
- [ ] C4. `registry.yaml`: group 8 `status: verified`.
- [ ] C5. Write `demos/demo_int_to_fp.sh`; run it.

## Verification gate
- [ ] pytest passes; verilator TB prints `PASS:` at INT_WIDTH=32; golden-file
      test byte-identical; lint clean under `-Wall`.
