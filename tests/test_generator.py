from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def test_registry_lookup_add_sub():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.addi", "arith.subi"], reg)
    assert grp["name"] == "add_sub"
    assert grp["rtl_module"] == "fu_add_sub.sv"
    assert grp["params"]["width"] == 32
