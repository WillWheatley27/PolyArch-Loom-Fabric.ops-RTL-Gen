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


def test_registry_lookup_div_rem_signed():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.divsi", "arith.remsi"], reg)
    assert grp["name"] == "div_rem_signed"
    assert grp["rtl_module"] == "fu_div_rem_signed.sv"
    assert grp["params"]["width"] == 32


def test_generate_group2_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divsi, @arith.remsi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_div_rem_signed.sv"
    text = out.read_text()
    assert "module fu_div_rem_signed" in text
    assert "input  logic              op_sel," in text
    assert "out_data = op_sel ? rem_signed : quo_signed" in text


def test_generate_group2_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divsi, @arith.remsi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/div_rem_signed/fu_div_rem_signed.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_div_rem_unsigned():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.divui", "arith.remui"], reg)
    assert grp["name"] == "div_rem_unsigned"
    assert grp["rtl_module"] == "fu_div_rem_unsigned.sv"
    assert grp["params"]["width"] == 32


def test_generate_group3_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divui, @arith.remui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_div_rem_unsigned.sv"
    text = out.read_text()
    assert "module fu_div_rem_unsigned" in text
    assert "input  logic              op_sel," in text
    assert "out_data = op_sel ? rem_out : quo_out" in text


def test_generate_group3_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divui, @arith.remui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/div_rem_unsigned/fu_div_rem_unsigned.sv"
    assert out.read_text() == ref.read_text()


def test_generate_unimplemented_group_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import TemplateNotImplemented

    # Group 4 (barrel_shift) is a valid share group with no template yet.
    with pytest.raises(TemplateNotImplemented):
        generate("fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]", tmp_path,
                 registry_path=ROOT / "registry.yaml")


def test_generate_illegal_op_list_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import ShareGroupError

    with pytest.raises(ShareGroupError):
        generate("fabric.op[@arith.addi, @arith.muli]", tmp_path,
                 registry_path=ROOT / "registry.yaml")


def test_cli_generates_file(tmp_path, monkeypatch):
    from fabric_gen.__main__ import main

    monkeypatch.chdir(ROOT)  # so default registry.yaml resolves
    rc = main(["fabric.op[@arith.addi, @arith.subi]", "-o", str(tmp_path)])
    assert rc == 0
    assert (tmp_path / "fu_add_sub.sv").exists()


def test_cli_illegal_returns_nonzero(tmp_path, monkeypatch, capsys):
    from fabric_gen.__main__ import main

    monkeypatch.chdir(ROOT)
    rc = main(["fabric.op[@arith.addi, @arith.muli]", "-o", str(tmp_path)])
    assert rc == 1
    err = capsys.readouterr().err
    assert "fabric-gen error: share-group:" in err


def test_generate_singleton_unmatched_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import RegistryError

    with pytest.raises(RegistryError):
        generate("fabric.op[arith.addi]", tmp_path,
                 registry_path=ROOT / "registry.yaml")
