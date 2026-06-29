# Share Group 15 RTL (`fu_exp_series`) — Implementation Plan

> exp/exp2/expm1 via a shared 2^f LUT core. n->exponent, overflow->Inf,
> underflow->0. expm1 = V + (-1.0) using an inline copy of the group-10 FP adder.
> Approximate, tolerance-verified, latency-1, 2-bit op_sel.

**Spec:** `docs/specs/2026-06-19-fu-exp-series-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `generator/templates/fu_exp_series.sv.j2` | Group-15 RTL template (ROM + inline fp_add) |
| `ops/math/exp_series/fu_exp_series.sv` | Committed golden |
| `tb/math/exp_series/tb_fu_exp_series.sv` | Self-checking TB (tolerance) |
| `generator/fabric_gen/generator.py` | Add `_TEMPLATE_MAP["exp_series"]` |
| `registry.yaml` | Group 15 `status: not_started → verified` |
| `tests/test_generator.py` | Group-15 lookup + golden; fix stale test |
| `demos/demo_exp_series.sh` | End-to-end demo |

---

## Group A — Template + generator wiring
- [ ] A1. Write `fu_exp_series.sv.j2`: decode->Q10.22, log2e prescale (exp/expm1),
      n/f split, 2^f LUT+interp, assemble V (clamp Inf/0), expm1 = fp_add(V,-1.0)
      (inline group-10 adder + lzc27), op_sel mux, latency-1.
- [ ] A2. Add `"exp_series"` to `_TEMPLATE_MAP`.
- [ ] A3. Generate golden: `... "fabric.op[@math.exp, @math.exp2, @math.expm1]" -o ops/math/exp_series`.

## Group B — Testbench + simulation
- [ ] B1. Write `tb_fu_exp_series.sv`: directed + random x in [-30,30] vs
      $exp/2.0**x/($exp-1) within combined rel+abs TOL; overflow/underflow
      corners; report max rel error.
- [ ] B2. `module load verilator/5.044`; lint (`--lint-only -Wall`).
- [ ] B3. Build + run TB; require `PASS:`. Debug exp core then expm1 subtract.

## Group C — Python tests + registry + demo
- [ ] C1. Add group-15 lookup + writes + golden tests.
- [ ] C2. Repoint `test_generate_unimplemented_group_raises` to group 16
      (`fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]`).
- [ ] C3. `pytest` green. C4. registry group 15 `verified`. C5. `demos/demo_exp_series.sh`; run.

## Verification gate
- [ ] pytest passes; verilator TB `PASS:` (within TOL); golden byte-identical;
      lint `-Wall` clean.
