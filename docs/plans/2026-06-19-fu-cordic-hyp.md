# Share Group 14 RTL (`fu_cordic_hyp`) — Implementation Plan

> Hyperbolic CORDIC sinh/cosh. Approximate (~16-bit), tolerance-verified,
> range-limited (|x| <= ~1.118). Group-13 structure, hyperbolic recurrence,
> repeated iterations 4 & 13, no fold, latency-1.

**Spec:** `docs/specs/2026-06-19-fu-cordic-hyp-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_cordic_hyp.sv.j2` | Group-14 RTL template |
| `ops/math/cordic_hyp/fu_cordic_hyp.sv` | Committed golden |
| `tb/math/cordic_hyp/tb_fu_cordic_hyp.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["cordic_hyp"]` |
| `registry.yaml` | Group 14 `status: not_started → verified` |
| `tests/test_generator.py` | Group-14 lookup + golden; fix stale test |
| `demos/demo_cordic_hyp.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_cordic_hyp.sv.j2`: binary32->Q4.28 decode, 16-step hyperbolic
      CORDIC (SHIFT + ATANH localparam tables, x0=324135026, repeats 4 & 13),
      select cosh/sinh, Q4.28->binary32 encode, latency-1.
- [ ] A2. Add `"cordic_hyp"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.sinh, @math.cosh]" -o ops/math/cordic_hyp`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_cordic_hyp.sv`: directed + random x in [-1.118,1.118] vs
      $sinh/$cosh within TOL; report max error; handshake.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Tune TOL; debug.

## Group C — Python tests + registry + demo
- [ ] C1. Add group-14 lookup + writes + golden tests.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 15
      (`fabric.op[@math.exp, @math.exp2, @math.expm1]`).
- [ ] C3. `pytest` green. C4. registry group 14 `verified`. C5. `demos/demo_cordic_hyp.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean.
