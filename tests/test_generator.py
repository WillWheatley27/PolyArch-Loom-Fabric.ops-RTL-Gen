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


def test_generate_group1_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addi, @arith.subi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_add_sub.sv"
    text = out.read_text()
    assert "module fu_add_sub" in text
    assert "input  logic              op_sel," in text
    assert "in_data_0 + b_eff" in text


def test_generate_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addi, @arith.subi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/add_sub/fu_add_sub.sv"
    assert out.read_text() == ref.read_text()


def test_generate_unimplemented_group_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import TemplateNotImplemented

    with pytest.raises(TemplateNotImplemented):
        generate("fabric.op[@arith.divsi, @arith.remsi]", tmp_path,
                 registry_path=ROOT / "registry.yaml")


def test_generate_illegal_op_list_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import ShareGroupError

    with pytest.raises(ShareGroupError):
        generate("fabric.op[@arith.addi, @arith.muli]", tmp_path,
                 registry_path=ROOT / "registry.yaml")
