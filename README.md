# fabric_op_gen

Registry-driven generator of synthesizable, simulatable SystemVerilog Function
Units (FUs) for the loom `fabric` dialect. Each FU implements one hardware
**share group** — a set of software ops that share one physical datapath,
selected at runtime by an `op_sel` config knob.

## Layout

- `registry.yaml` — source of truth: the 19 share groups -> module/params.
- `ops/<family>/<group>/` — RTL (e.g. `ops/int_arith/add_sub/fu_add_sub.sv`).
- `tb/<family>/<group>/` — self-checking testbenches + `run.sh`.
- `generator/` — the `fabric_gen` Python package + Jinja2 `templates/`.
- `tests/` — pytest suite for the generator.
- `docs/` — specs (`fabric_hardware_share_groups.md`,
  `fabric_reconfigurable_ops.md`) and `specs/`, `plans/`.

## Setup

The generator needs `jinja2`, `pyyaml`, `pytest`. Use a project venv:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install jinja2 pyyaml pytest
# optional: install the package + `fabric-gen` console script
./.venv/bin/python -m pip install -e generator
```

## Usage

```bash
# CLI
PYTHONPATH=generator ./.venv/bin/python -m fabric_gen "fabric.op[@arith.addi, @arith.subi]" -o build/rtl
# -> build/rtl/fu_add_sub.sv

# Python API
PYTHONPATH=generator ./.venv/bin/python -c \
  "from fabric_gen import generate; print(generate('fabric.op[@arith.addi, @arith.subi]', 'build/rtl'))"
```

The parser and share-group validator are general (any op string, all 19 groups).
RTL emission is implemented and verified for **all 19 share groups** — integer
arithmetic/logic (1–7), int↔FP conversion and IEEE-754 FP arithmetic (8–12), and
the `math`-dialect transcendentals (13–19). Each emitted module has a committed
golden `.sv`, a self-checking Verilator testbench, and a runnable demo under
`demos/`. Groups 1–12 and 17 are bit-exact / correctly-rounded; the
transcendental groups (13–16, 18, 19) are tolerance-verified approximations.

**Parameterizable formats.** Every FU is parameterized and verified at multiple
formats: integer FUs by `WIDTH` (8/16/32/64); floating-point and transcendental
FUs by IEEE-754 format `(EXP_W, MANT_W)` — **fp32 and fp64** (bf16-capable) — via
`--format {fp32,fp64,bf16}`. Format-specific data is generated at generation
("compile") time: `formats.py` derives the shape constants, `approx.py` fits
compile-time minimax polynomials for exp/log/sqrt (Horner, no ROM), and the
tanh/erf LUT and CORDIC constant tables are generated per format. The structural
FP units are genuinely parameterized SystemVerilog (one source, any format).

## Tests

```bash
PYTHONPATH=generator ./.venv/bin/python -m pytest tests/ -v
```

## Simulation / lint (Verilator, primary gate)

```bash
module load verilator/5.044
./tb/int_arith/add_sub/run.sh      # lint + sim at WIDTH 32 and 8
```

## End-to-end demos

One runnable demo per implemented share group lives in `demos/` (each:
generate -> lint -> simulate at WIDTH 32 and 8 -> PASS -> "DEMO OK"). Run from
anywhere; each script cd's to the repo root itself.

```bash
./demos/demo.sh                  # group 1: add_sub
./demos/demo_div_rem_signed.sh   # group 2: div_rem_signed
./demos/demo_div_rem_unsigned.sh # group 3: div_rem_unsigned
./demos/demo_barrel_shift.sh     # group 4: barrel_shift
./demos/demo_bitwise_alu.sh      # group 5: bitwise_alu
./demos/demo_min_max_signed.sh   # group 6: min_max_signed
```

## Verification gate

- **Primary:** `verilator --lint-only -Wall` clean + TB `PASS` (WIDTH 32 and 8).
- **Sign-off:** VCS (`module load synopsys/vcs/X-2025.06-SP1`, `vcs -full64 ...`).
  `fu_add_sub` passes 10k random vectors under both Verilator and VCS.

## Extending to more groups

1. Add a synthesizable template under `generator/templates/`.
2. Register it in `_TEMPLATE_MAP` in `generator/fabric_gen/generator.py`.
3. Hand-author the matching self-checking TB under `tb/<family>/<group>/`.
4. Add a golden-file test. See `docs/specs/` for the design pattern.
