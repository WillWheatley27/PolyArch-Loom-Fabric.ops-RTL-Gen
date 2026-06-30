# Share Group 18 RTL (`fu_sqrt_rsqrt`) — Implementation Plan

> FINAL group. sqrt/rsqrt via shared LUT + exponent split (e=2q+r, sqrt2 factor
> for odd e). Approximate, tolerance-verified, latency-1, 1-bit op_sel.

**Spec:** `docs/specs/2026-06-19-fu-sqrt-rsqrt-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_sqrt_rsqrt.sv.j2` | Group-18 RTL template (2 ROMs) |
| `ops/math/sqrt_rsqrt/fu_sqrt_rsqrt.sv` | Committed golden |
| `tb/math/sqrt_rsqrt/tb_fu_sqrt_rsqrt.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["sqrt_rsqrt"]` |
| `registry.yaml` | Group 18 `status: not_started → verified` |
| `tests/test_generator.py` | Group-18 lookup + golden; replace stale test |
| `demos/demo_sqrt_rsqrt.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_sqrt_rsqrt.sv.j2`: decode, e=2q+r, SQRT_M/RSQRT_M interp,
      sqrt2/invsqrt2 odd factor, normalize mf -> [1,2), clz/RNE encode with
      exponent q/-q, specials, latency-1.
- [ ] A2. Add `"sqrt_rsqrt"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.sqrt, @math.rsqrt]" -o ops/math/sqrt_rsqrt`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_sqrt_rsqrt.sv`: directed (perfect squares + specials by bits)
      + random vs $sqrt / 1/$sqrt within rel TOL; report max rel error.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`.

## Group C — Python tests + registry + demo
- [ ] C1. Add group-18 lookup + writes + golden tests.
- [ ] C2. Replace `test_generate_unimplemented_group_raises` with a cross-group
      ShareGroupError test (no unimplemented valid group remains).
- [ ] C3. `pytest` green. C4. registry group 18 `verified`. C5. `demos/demo_sqrt_rsqrt.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean. ALL 19 GROUPS COMPLETE.
