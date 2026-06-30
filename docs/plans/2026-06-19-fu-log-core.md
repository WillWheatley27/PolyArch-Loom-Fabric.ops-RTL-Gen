# Share Group 16 RTL (`fu_log_core`) — Implementation Plan

> log/log2/log10/log1p via a shared log2 core: log2(x)=e+log2(m), m via LUT,
> scale by ln2 / (1/log2(10)); log1p pre-adds 1.0 (inline group-10 fp_add).
> Approximate, tolerance-verified, latency-1, 2-bit op_sel.

**Spec:** `docs/specs/2026-06-19-fu-log-core-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_log_core.sv.j2` | Group-16 RTL template (ROM + inline fp_add) |
| `ops/math/log_core/fu_log_core.sv` | Committed golden |
| `tb/math/log_core/tb_fu_log_core.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["log_core"]` |
| `registry.yaml` | Group 16 `status: not_started → verified` |
| `tests/test_generator.py` | Group-16 lookup + golden; fix stale test |
| `demos/demo_log_core.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_log_core.sv.j2`: specials, decode -> e + LUT_log2(m) (signed
      fixed-pt), scale mux (1/ln2/invlog2_10) via fixed-pt multiply, log1p =
      fp_add(x,1.0)->log path, signed encode -> binary32, latency-1.
- [ ] A2. Add `"log_core"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]" -o ops/math/log_core`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_log_core.sv`: directed specials + random vs $ln/$log10/
      ($ln/ln2)/$ln(1+x) within rel+abs TOL; report max rel error.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Debug core then scaling then log1p.

## Group C — Python tests + registry + demo
- [ ] C1. Add group-16 lookup + writes + golden tests.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 17
      (`fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]`).
- [ ] C3. `pytest` green. C4. registry group 16 `verified`. C5. `demos/demo_log_core.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean.
