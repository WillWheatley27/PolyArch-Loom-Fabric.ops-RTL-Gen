# Share Group 13 RTL (`fu_cordic_trig`) — Implementation Plan

> First transcendental. Approximate (~16-bit), tolerance-verified, range-limited
> (|x| <= pi). CORDIC rotator (16 iters), binary32 <-> Q4.28, base-range fold,
> latency-1. No loom reference.

**Spec:** `docs/specs/2026-06-19-fu-cordic-trig-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_cordic_trig.sv.j2` | Group-13 RTL template |
| `ops/math/cordic_trig/fu_cordic_trig.sv` | Committed golden |
| `tb/math/cordic_trig/tb_fu_cordic_trig.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["cordic_trig"]` |
| `registry.yaml` | Group 13 `status: not_started → verified` |
| `tests/test_generator.py` | Group-13 lookup + golden; fix stale test |
| `demos/demo_cordic_trig.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_cordic_trig.sv.j2`: binary32->Q4.28 decode, quadrant fold,
      16-iter unrolled CORDIC (atan/K/pi localparams), quadrant correct,
      Q4.28->binary32 encode (clz + RNE), latency-1 pipe.
- [ ] A2. Add `"cordic_trig"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.sin, @math.cos]" -o ops/math/cordic_trig`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_cordic_trig.sv`: directed + random x in [-pi,pi] vs
      $sin/$cos within TOL; report max error; handshake.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Tune TOL to measured worst case; debug.

## Group C — Python tests + registry + demo
- [ ] C1. Add `test_registry_lookup_cordic_trig`, `test_generate_group13_writes_file`,
      `test_generate_group13_golden_matches`.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 14
      (`fabric.op[@math.sinh, @math.cosh]`).
- [ ] C3. `pytest` green. C4. registry group 13 `verified`. C5. `demos/demo_cordic_trig.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean.
