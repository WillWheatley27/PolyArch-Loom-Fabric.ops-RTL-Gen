# Design: Share Group 9 RTL (`fu_fp_to_int`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (structural, sim-verified — same rationale as group 8), pending impl
**Scope:** Add share group 9 (`fp_to_int` = `arith.fptosi` / `arith.fptoui`).
Reverse of group 8: IEEE-754 binary32 → 32-bit integer. Unary, latency-1.

---

## 1. Goal
Convert a binary32 float to a 32-bit integer (truncate toward zero), op_sel:
- `op_sel = 0` → `arith.fptosi` (float → signed int)
- `op_sel = 1` → `arith.fptoui` (float → unsigned int)

Rationale (group 9): *"Same mantissa / exponent extractor; signedness affects
only the post-rounding sign attach."*

## 2. Why structural (same as group 8)
loom's `fu_op_fptosi/fptoui` are behavioral: `$bitstoshortreal` + `$rtoi` (f32).
Verilator 5.044 can't run `shortreal`, so we implement a **structural** binary32
→ int32 extractor (decode exponent/mantissa → shift → truncate). loom uses a bare
`$rtoi` with no out-of-range handling (UB); we define deterministic **RISC-V
FCVT** saturation (consistent with our divider/shift edge-case choices).

## 3. Semantics (RISC-V FCVT.W.S / FCVT.WU.S), truncate toward zero

**fptosi (signed):**
| input | result |
|---|---|
| NaN | `0x7FFF_FFFF` (INT_MAX) |
| +Inf or value ≥ 2³¹ | `0x7FFF_FFFF` |
| −Inf or value < −2³¹ | `0x8000_0000` (INT_MIN) |
| \|value\| < 1 | 0 |
| else | truncate toward zero |

**fptoui (unsigned):**
| input | result |
|---|---|
| NaN | `0xFFFF_FFFF` (UINT_MAX) |
| negative (incl −Inf, −0) | 0 |
| +Inf or value ≥ 2³² | `0xFFFF_FFFF` |
| value < 1 (≥0) | 0 |
| else | truncate toward zero |

## 4. Datapath — `ops/int_arith/fp_to_int/fu_fp_to_int.sv`
Decode `sign=f[31]`, `exp=f[30:23]`, `mant=f[22:0]`; `signif = {1'b1, mant}`
(24-bit); `is_nan = (exp==0xFF) & |mant`. Let `E = exp − 127`.
- `exp < 127` → magnitude < 1 → `mag = 0`.
- else `mag = (E ≥ 23) ? signif << (E−23) : signif >> (23−E)` (right-shift drops
  the fractional bits = truncate toward zero on the magnitude).
- **Signed:** NaN/Inf per table; `E ≥ 31` → saturate (`sign ? INT_MIN : INT_MAX`);
  else `sign ? −mag : mag` (E ≤ 30 ⇒ `mag < 2³¹`).
- **Unsigned:** NaN → UINT_MAX; `sign` → 0; +Inf → UINT_MAX; `E ≥ 32` → UINT_MAX;
  else `mag` (E ≤ 31 ⇒ `mag < 2³²`).

Hand-verified: `fptosi(2.5)=2`, `fptosi(-2.5)=-2`, `fptosi(2³¹)=INT_MAX`,
`fptosi(-2³¹)=INT_MIN`, `fptosi(NaN)=INT_MAX`, `fptoui(-5)=0`, `fptoui(2³²)=UINT_MAX`.

Latency-1 registered output (same handshake as group 8). Unary (one input). All
input bits read (no `UNUSEDSIGNAL`).

## 5. Generator + template
- New template `generator/templates/fu_fp_to_int.sv.j2` (uses `params.fp_width`
  for input width, `params.int_width` for output; `params` already threaded by
  generator since group 8). Add `"fp_to_int"` to `_TEMPLATE_MAP`.
- Golden = output for `fabric.op[@arith.fptosi, @arith.fptoui]`.
- `registry.yaml`: group 9 `status: not_started → verified`.

## 6. Testbench — `tb/int_arith/fp_to_int/tb_fu_fp_to_int.sv`
Latency-1, INT_WIDTH=FP_WIDTH=32. Layers:
1. **Directed exact** hand-computed vectors covering truncation, sign, the
   signed/unsigned distinguisher (`-5.0` → `-5` vs `0`), saturation, NaN, ±Inf.
2. **Independent oracle on random inputs:** decode the input bits to `real`,
   classify (NaN/Inf/overflow/negative/in-range), and compute the exact expected
   int (`$rtoi` for signed in-range, `$floor` for unsigned in-range, exact
   constants for special/overflow). Two random batches: exponent-biased in-range
   floats (heavy truncation coverage) + full-random 32-bit (special/overflow).
3. **Handshake corners:** latency-1 timing, backpressure, no-accept.

## 7. Verification
`demos/demo_fp_to_int.sh`: generate → `verilator --lint-only -Wall` → build+run
TB → `PASS:`.

## 8. Python tests
- Add lookup + writes + golden for `fp_to_int`.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 10 (`fabric.op[@arith.addf, @arith.subf]`, fp_add_sub).
