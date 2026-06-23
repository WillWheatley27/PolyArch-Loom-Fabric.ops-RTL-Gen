# Share Group 19 RTL (`fu_approx_tanh_erf`) — Implementation Plan

> tanh/erf via shared LUT + linear interpolation. Approximate, tolerance-verified,
> range-limited (table over [0,4], saturate beyond). Odd symmetry. Latency-1.

**Spec:** `docs/specs/2026-06-19-fu-approx-tanh-erf-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_approx_tanh_erf.sv.j2` | Group-19 RTL template (embeds ROMs) |
| `ops/math/approx_tanh_erf/fu_approx_tanh_erf.sv` | Committed golden |
| `tb/math/approx_tanh_erf/tb_fu_approx_tanh_erf.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["approx_tanh_erf"]` |
| `registry.yaml` | Group 19 `status: not_started → verified` |
| `tests/test_generator.py` | Group-19 lookup + golden; repoint stale test |
| `demos/demo_approx_tanh_erf.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_approx_tanh_erf.sv.j2`: TANH_T/ERF_T ROMs (129 entries, Q1.23),
      decode |x|->Q8.16 index/frac, op_sel table mux, linear interp, saturate,
      Q1.23->binary32 encode, sign, latency-1.
- [ ] A2. Add `"approx_tanh_erf"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.tanh, @math.erf]" -o ops/math/approx_tanh_erf`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_approx_tanh_erf.sv`: tanh vs $tanh, erf vs A&S formula;
      directed + random x in [-5,5] within TOL; report max error; handshake.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Tune TOL; debug.

## Group C — Python tests + registry + demo
- [ ] C1. Add group-19 lookup + writes + golden tests.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 15
      (`fabric.op[@math.exp, @math.exp2, @math.expm1]`).
- [ ] C3. `pytest` green. C4. registry group 19 `verified`. C5. `demos/demo_approx_tanh_erf.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean.
