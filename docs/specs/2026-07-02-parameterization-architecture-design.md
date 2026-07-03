# Design: Parameterize All Fabric FUs by Width/Format (compile-time generated)

**Date:** 2026-07-02
**Status:** Approved in brainstorming; pending spec review
**Scope:** Make all 19 share-group generators emit **parameterizable** RTL —
integer FUs by bit-width, floating-point FUs by IEEE-754 **format** (fp32 + fp64
required, bf16 optional). All format/precision-specific data (widths, biases,
rounding positions, polynomial coefficients, CORDIC constants) is computed by the
**generator at generation ("compile") time**. Location note: kept in the repo's
existing `docs/specs/` (not `docs/superpowers/specs/`) to match the 19 prior
per-group specs.

---

## 1. Goal
Today the generator emits fixed-shape RTL: integer FUs carry a `WIDTH` parameter
(mostly generic), but the FP FUs are hardwired binary32 and the transcendentals
embed hand-pasted 32-bit ROMs. Target end state:
- **Integer FUs**: runtime `parameter WIDTH ∈ {8, 16, 32, 64}`.
- **FP FUs**: IEEE-754 format = `(EXP_W, MANT_W)` — **fp32 (8,23)** and
  **fp64 (11,52)** required, **bf16 (8,7)** optional.
- **Transcendentals**: same FP formats, approximated by **compile-time-generated
  minimax polynomials** (no large ROMs); CORDIC retained for trig/hyperbolic;
  rounding stays exact.

## 2. Format model (`generator/fabric_gen/formats.py`)
Single source of truth for shape.
- **Integer**: `WIDTH`.
- **FP**: descriptor `(EXP_W, MANT_W)` → derived: `TOTAL_W = 1+EXP_W+MANT_W`,
  `BIAS = 2^(EXP_W−1)−1`, `SIG_W = MANT_W+1`; bit patterns for `+Inf`, `−Inf`,
  `qNaN`, `±0`; guard/round/sticky positions.
  - `bf16=(8,7)`, `fp32=(8,23)`, `fp64=(11,52)`.
- `generate()` / CLI gains `--format {fp32,fp64,bf16}` (FP/transcendental groups)
  and `--width N` (integer groups). `registry.yaml` lists the formats each group
  supports. **Default = current behavior** (fp32 / width-32) so committed goldens
  stay byte-identical (zero-regression guard).

## 3. Three FU categories, each handled the way that fits

**A. Integer FUs (1–7) — runtime `parameter WIDTH`.**
Already largely generic (`$clog2(WIDTH+1)` counters, `b & (WIDTH-1)` masks).
Work: replace the few hardcoded 32-bit constants (e.g. signed-div INT_MIN
overflow → `WIDTH'(1) << (WIDTH-1)`, stray `32'd…` literals) and verify at
8/16/32/64. Exact; no format concept.

**B. FP arithmetic FUs (8–12) — genuinely parameterized SV by `(EXP_W, MANT_W)`.**
(`int_to_fp`/`fp_to_int` also keep a separate `INT_WIDTH ∈ {32,64}`.) Field
slices, `SIG_W`, alignment/guard/round/sticky positions, rounding, divider
iteration count, and special-case constants all derive from the params. RNE,
FTZ, correctly-rounded. **Refinement of the earlier "generator-specialized"
idea:** because these units have no tables, genuine SV parameters are the truest
form of "parameterizable" — one module works at any format; the generator selects
the format (sets params, emits a matching testbench/instance). Generator-side
*specialization* is therefore reserved for data that can't be an SV parameter —
the transcendental coefficients in category C. *(Confirm during spec review; if
you'd rather have one hardwired `.sv` per format for FP too, we switch to that.)*

**C. Transcendentals (13–19) — compile-time-generated approximations.**
- **exp/exp2/expm1, log family, sqrt/rsqrt, tanh, erf (15, 16, 18, 19):**
  replace LUTs with **compile-time-generated minimax (or Chebyshev) polynomial
  coefficients** over the reduced range (exponent extracted; mantissa/[1,2) or
  [−π/4,π/4] covered by the polynomial). RTL = a parameterized **Horner MAC
  evaluator**; **degree scales with the format's precision** (low for fp32,
  higher for fp64). No ROM (tiny hybrid table only where it clearly wins).
- **sin/cos, sinh/cosh (13, 14):** keep **CORDIC** (multiplier-free; iteration
  count + atan/atanh constants generated per precision).
- **rounding (17):** exact bit-manipulation, parameterized by format (works at
  any `(EXP_W, MANT_W)`).
- **Accuracy tier for fp64:** approximate/tolerance-verified (~1e-5–1e-6
  relative), **not** full fp64 ULP — documented. Wider fixed-point container,
  generated coefficients; a giant fp64 ROM is explicitly avoided (the reason for
  going polynomial).

## 4. Generator changes
- `formats.py` — format descriptors + derived-parameter computation.
- `approx.py` — minimax/Chebyshev coefficient generation and CORDIC constant
  generation (replaces hand-pasted ROMs). *(Phase 3 dependency: needs numpy or a
  small pure-Python Remez — verify the venv before starting Phase 3.)*
- `generate()` builds a richer template context: `EXP_W, MANT_W, BIAS, TOTAL_W,
  SIG_W`, derived constants, and coefficient arrays; templates render
  format-appropriate RTL. Beware the known Jinja `{{` vs SV `{N{…}}` replication
  collision (use size-casts / spacing).

## 5. Verification
- Testbenches parameterized by format/width.
- **FP arithmetic:** Verilator's `real` **is** IEEE double, so it is an *exact*
  oracle for fp64 add/sub/mul/div (≤0.5 ULP checks); fp32 references are rounded.
- **Transcendentals:** tolerance (~1e-5–1e-6 relative), per format.
- **Integer:** exact, run at 8/16/32/64.
- **Goldens:** commit fp32 (regression) **and** fp64 for FP/transcendental groups;
  integer at width 32. Extend pytest to generate + golden-match per
  (group, format). Every module lint-clean under `verilator --lint-only -Wall`.

## 6. Phasing (each phase gets its own implementation plan)
- **Phase 1 — START HERE ("the floating-point ones"):** build `formats.py` +
  format context plumbing, then parameterize **FP arithmetic FUs 8–12** for
  **fp32 + fp64** (bf16 optional). Prove fp32 goldens regenerate **byte-identical**;
  add fp64 goldens + parameterized testbenches.
- **Phase 2 — integer FUs 1–7:** fix hardcoded constants; verify at 8/16/32/64.
- **Phase 3 — transcendentals 13–19:** `approx.py` + polynomial Horner evaluators
  (exp/log/sqrt/tanh/erf), CORDIC precision-scaling, rounding format-parameterized;
  fp32 + fp64.
- bf16 added wherever formats are supported, as an optional pass.

## 7. Risks / notes
- Jinja `{{` collides with SV replication `{N{…}}` — use size-casts/spacing (known).
- Fully-parameterized fp64 divider: iteration count and FSM counter widths must
  scale with `MANT_W` — verify carefully.
- fp64 transcendentals are approximate only (documented), not fp64 ULP.
- Deliverable stays Verilator-simulated + lint-clean; not synthesis-proven here.
