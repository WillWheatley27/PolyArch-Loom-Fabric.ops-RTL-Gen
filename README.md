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
RTL emission is currently implemented for **share group 1 (`add_sub`)**,
**share group 2 (`div_rem_signed`)**, and **share group 3 (`div_rem_unsigned`)**;
other valid groups report `template not yet implemented`.

## Tests

```bash
PYTHONPATH=generator ./.venv/bin/python -m pytest tests/ -v
```

## Simulation / lint (Verilator, primary gate)

```bash
module load verilator/5.044
./tb/int_arith/add_sub/run.sh      # lint + sim at WIDTH 32 and 8
```

## End-to-end demo

```bash
./demo.sh        # generate -> lint -> simulate -> PASS -> "DEMO OK"
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
