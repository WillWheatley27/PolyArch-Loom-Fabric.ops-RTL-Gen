# Design: Share Group 17 RTL (`fu_rounding`) + Generator Wiring

**Date:** 2026-06-19
**Status:** Approved (exact, structural), pending impl
**Scope:** Share group 17 (`rounding` = `math.floor` / `math.ceil` / `math.round`
/ `math.trunc` / `math.roundeven`). The LAST group and the only remaining
**bit-exact** one. 5 members → 3-bit `op_sel`.

---

## 1. Goal
Round a binary32 to an integer-valued binary32, per mode:
- `op_sel = 0` → `math.floor`     (toward −Inf)
- `op_sel = 1` → `math.ceil`      (toward +Inf)
- `op_sel = 2` → `math.round`     (nearest, ties **away** from zero — C `round`)
- `op_sel = 3` → `math.trunc`     (toward zero)
- `op_sel = 4` → `math.roundeven` (nearest, ties **to even** — C `rint`/`roundeven`)
- 5–7 reserved → trunc.

Rationale (group 17): *"One rounding network with mode-select control."*

## 2. Approach — exact, exponent/mantissa manipulation (no LUT)
For x with biased exponent `E` (e = E−127), significand `sig = {1, mantissa}`
(24-bit, value = sig·2^(E−150)):
- **E == 0** (zero/subnormal): FTZ → signed zero `{s, 0}`. *(Documented FTZ
  deviation: e.g. floor of a tiny negative subnormal gives −0 instead of −1.)*
- **E ≥ 150** (|x| ≥ 2²³, already integer; also Inf/NaN): result = x (passthrough;
  floor(Inf)=Inf, *(any)*(NaN)=NaN).
- **E < 127** (|x| < 1): result ∈ {±0, ±1} by mode/sign (table below).
- **127 ≤ E ≤ 149** (mixed integer+fraction): `fb = 150−E` fractional bits.
  `frac = sig & (2^fb−1)`, `sigt = sig & ~(2^fb−1)` (truncate toward zero),
  `half = 2^(fb−1)`, integer-LSB = `sig[fb]`. Add one integer-ULP (`+2^fb`) iff
  the mode rounds the magnitude up:
  - trunc: never. floor: `s & frac≠0`. ceil: `~s & frac≠0`.
  - round: `frac ≥ half` (ties away). roundeven: `frac>half | (frac==half & sig[fb])`.
  `sigr = sigt + roundup·2^fb`; if `sigr[24]` (carry) → exponent `E+1`, mant 0;
  else exponent `E`, mant `sigr[22:0]`. Sign preserved.

**|x| < 1 table** (E in [1,126]; `ge_half` = E==126, `gt_half` = E==126 & m≠0):
| mode | result |
|---|---|
| floor | s ? −1.0 : +0 |
| ceil | s ? −0 : +1.0 |
| trunc | {s, 0} |
| round | ge_half ? ±1.0 : ±0 |
| roundeven | gt_half ? ±1.0 : ±0 |

Hand-verified: round(1.5)=2, roundeven(1.5)=2, roundeven(2.5)=2, ceil(0.3)=1,
floor(−0.3)=−1, trunc(−0.7)=−0, round(0.5)=1, roundeven(0.5)=0.

## 3. Verification (exact — no tolerance)
- **Value oracle** (random |x| < ~1e6, all modes): decode dut and a real
  reference (`$floor`/`$ceil` and real-computed round/trunc/roundeven) to real,
  assert **exact equality** (rounding results are exactly representable).
- **Exact-bit directed** vectors (hand-computed) covering signed zero (trunc(−0.3)
  = −0), ±1 boundaries, ties (1.5, 2.5, 0.5), already-integer passthrough
  (2²³, 2²⁴, large), and Inf/NaN passthrough.

## 4. Generator + template
- `generator/templates/fu_rounding.sv.j2` (uses `params.width`, `op_list`; no
  LUT, no `{{`-collision). Add `"rounding"` to `_TEMPLATE_MAP`. Golden = output
  for `fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]`.
  Path `ops/math/rounding/`.
- `registry.yaml`: group 17 `status: not_started → verified`.

## 5. Testbench — `tb/math/rounding/tb_fu_rounding.sv`
Unary, latency-1, 3-bit `op_sel`. Value-oracle random + exact-bit directed (above)
+ handshake corners.

## 6. Python tests
- Add lookup + writes + golden for `rounding`.
- This completes all 19 groups; the stale `test_generate_unimplemented_group_raises`
  is repointed to group 18 (`fabric.op[@math.sqrt, @math.rsqrt]`), the last
  remaining unimplemented group.
