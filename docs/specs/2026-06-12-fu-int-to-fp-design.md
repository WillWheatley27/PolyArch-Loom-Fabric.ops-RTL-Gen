# Design: Share Group 8 RTL (`fu_int_to_fp`) + Generator Wiring

**Date:** 2026-06-12
**Status:** Approved (user chose the structural, sim-verified approach), pending impl
**Scope:** Add share group 8 (`int_to_fp` = `arith.sitofp` / `arith.uitofp`) as a
full end-to-end slice. First **floating-point** group and first **unary** op.

---

## 1. Goal

Convert a 32-bit integer to an IEEE-754 binary32 float, selectable via 1-bit
`op_sel`:

- `op_sel = 0` → `arith.sitofp` (signed int → f32)
- `op_sel = 1` → `arith.uitofp` (unsigned int → f32)

Rationale (`docs/fabric_hardware_share_groups.md`, group 8): *"Same mantissa /
exponent generator; signedness affects only the absolute-value preprocessor."*

## 2. Why this diverges from loom (key decision)

loom's `fu_op_sitofp.sv`/`fu_op_uitofp.sv` are **behavioral**: `$itor` +
`$shortrealtobits` (f32) under `ifndef SYNTH_FP_IP`, with a vendor-IP placeholder
otherwise. **Verilator 5.044 does not support `shortreal`** ("shortreal being
promoted to real"), so loom's f32 model cannot be *simulated* in our flow (loom
only `--lint`s it). We therefore implement a **structural** int→binary32 encoder:
leading-zero count → normalize → round-to-nearest-even. This is synthesizable AND
Verilator-simulatable, at the cost of more logic than loom's placeholder.

This is the first group with **no faithful loom RTL to mirror** for simulation.

## 3. Interface & handshake (new shapes)

- **Unary:** one data input `in_data_0` (the integer) + `in_valid_0`/`in_ready_0`;
  one output `out_data` (f32 bits) + `out_valid`/`out_ready`. No `in_data_1`.
- **Latency-1 pipeline** (mirrors loom's handshake): `fire = in_valid_0 &
  (~out_valid | out_ready)`, `in_ready_0 = fire`; on `fire` register the
  conversion result and set `out_valid`; drain when `out_ready`. `clk`/`rst_n`
  are real (used).
- Params: registry `int_width: 32, fp_width: 32`. The encoder targets
  `INT_WIDTH=32 → binary32` (exp 8, mantissa 23, bias 127). The generator now
  passes the full `params` dict to templates; the module's `INT_WIDTH` parameter
  is rendered from `params.int_width`.

## 4. Structural datapath — `ops/int_arith/int_to_fp/fu_int_to_fp.sv`

Combinational `conv_result`, then the latency-1 register.

1. **Signedness preprocessor:** `op_sel=0` (sitofp): `sign = in[31]`,
   `mag = sign ? -in : in`. `op_sel=1` (uitofp): `sign = 0`, `mag = in`.
   (`mag` is the unsigned magnitude; `|INT_MIN| = 2^31` is represented as
   `0x8000_0000`, which is correct.)
2. **Zero:** `mag == 0` → result `0x0000_0000` (+0.0).
3. **Normalize:** `lz = clz32(mag)`; `shifted = mag << lz` (leading 1 at bit 31).
4. **Fraction / round bits:** `frac = shifted[30:8]`; `lsb = shifted[8]`;
   `guard = shifted[7]`; `sticky = |shifted[6:0]`.
5. **Round-to-nearest-even:** `round_up = guard & (sticky | lsb)`;
   `mant24 = {1'b0,frac} + round_up`.
6. **Exponent:** `exp9 = 158 - lz` (= (31-lz)+127). If `mant24[23]` (rounding
   overflow): `exp = exp9+1`, `mant = 0`; else `exp = exp9[7:0]`, `mant =
   mant24[22:0]`.
7. **Assemble:** `{sign, exp[7:0], mant[22:0]}`.

int32 never overflows to Inf in f32 (max ~4.29e9 ≪ 3.4e38) and never produces
NaN/subnormals, so no special-case encoding is needed.

Hand-verified: `sitofp(5)=0x40A00000`, `sitofp(-1)=0xBF800000`,
`uitofp(0xFFFFFFFF)=0x4F800000` (→2^32), `uitofp(2^24+1)=0x4B800000` (tie→even
down), `uitofp(2^24+3)=0x4B800002` (tie→even up), `sitofp(INT_MIN)=0xCF000000`.

## 5. Generator + template
- New template `generator/templates/fu_int_to_fp.sv.j2` (plain substitution;
  `module_name`, `params.int_width`, `op_list`). No `{{`-replication.
- `generator.py`: pass `params=grp.get("params", {})` to `render()` (additive;
  groups 1-7 ignore it). Add `"int_to_fp": "fu_int_to_fp.sv.j2"` to `_TEMPLATE_MAP`.
- Committed golden = generator output for `fabric.op[@arith.sitofp, @arith.uitofp]`.
- `registry.yaml`: group 8 `status: not_started → verified`.

## 6. Testbench — `tb/int_arith/int_to_fp/tb_fu_int_to_fp.sv`
Self-checking, latency-1, parameterized by `INT_WIDTH` (tested at 32 — FP is
format-specific, so no 8/32 sweep). Three layers:
1. **Directed exact vectors** with hand-computed binary32 bit patterns (zero, ±1,
   ±2, ±5, powers of two, INT_MIN, `0x8000_0000` unsigned, `0xFFFFFFFF`, and RNE
   tie cases `2^24+1`/`2^24+3`). Includes the signedness distinguisher: input
   `0xFFFFFFFF` → `sitofp = -1.0` vs `uitofp = 4294967295.0`.
2. **Randomized correct-rounding property:** for random `x`, decode the DUT's f32
   output to `real` and check `|decoded − true_value| ≤ half_ULP`, where
   `true_value = $itor` of the (un)signed input and `half_ULP = 2^(msb(|x|)−24)`
   — both computed independently with `real` arithmetic (no `shortreal`, no DPI).
3. **Handshake corners:** latency-1 timing, backpressure (output holds, no accept
   while stalled), no fire when input invalid.

## 7. Verification
`demos/demo_int_to_fp.sh` (in `demos/`): generate → `verilator --lint-only -Wall`
→ build+run TB at `INT_WIDTH=32` → assert `PASS:`.

## 8. Python tests
- Add: registry lookup `int_to_fp`; `generate(...)` writes the file; golden-file
  match.
- **Fix stale test:** repoint `test_generate_unimplemented_group_raises` to
  group 9 (`fabric.op[@arith.fptosi, @arith.fptoui]`, fp_to_int).
