# Share Group 17 RTL (`fu_rounding`) — Implementation Plan

> The last group and the only remaining EXACT one. floor/ceil/round/trunc/
> roundeven via exponent/mantissa manipulation (no LUT). 3-bit op_sel, latency-1.

**Spec:** `docs/specs/2026-06-19-fu-rounding-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_rounding.sv.j2` | Group-17 RTL template |
| `ops/math/rounding/fu_rounding.sv` | Committed golden |
| `tb/math/rounding/tb_fu_rounding.sv` | Self-checking TB (exact) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["rounding"]` |
| `registry.yaml` | Group 17 `status: not_started → verified` |
| `tests/test_generator.py` | Group-17 lookup + golden; fix stale test |
| `demos/demo_rounding.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_rounding.sv.j2`: cases (FTZ / passthrough E>=150 / |x|<1 table
      / fractional fb=150-E drop+conditional-add), per-mode roundup, carry
      renormalize, latency-1.
- [ ] A2. Add `"rounding"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]" -o ops/math/rounding`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_rounding.sv`: value-oracle random (|x|<1e6, all modes,
      exact equality) + exact-bit directed (signed zero, +/-1, ties, passthrough,
      Inf/NaN) + handshake.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:` (0 mismatches, exact).

## Group C — Python tests + registry + demo
- [ ] C1. Add group-17 lookup + writes + golden tests.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 18
      (`fabric.op[@math.sqrt, @math.rsqrt]`).
- [ ] C3. `pytest` green. C4. registry group 17 `verified`. C5. `demos/demo_rounding.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (exact, 0 mismatches); golden
      byte-identical; lint `-Wall` clean.
