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


def test_registry_lookup_barrel_shift():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.shli", "arith.shrsi", "arith.shrui"], reg)
    assert grp["name"] == "barrel_shift"
    assert grp["rtl_module"] == "fu_barrel_shift.sv"
    assert grp["params"]["width"] == 32


def test_generate_group4_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_barrel_shift.sv"
    text = out.read_text()
    assert "module fu_barrel_shift" in text
    assert "input  logic [1:0]        op_sel," in text
    assert "in_data_1 & WIDTH'(WIDTH - 1)" in text


def test_generate_group4_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.shli, @arith.shrsi, @arith.shrui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/barrel_shift/fu_barrel_shift.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_bitwise_alu():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.andi", "arith.ori", "arith.xori"], reg)
    assert grp["name"] == "bitwise_alu"
    assert grp["rtl_module"] == "fu_bitwise_alu.sv"
    assert grp["params"]["width"] == 32


def test_generate_group5_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.andi, @arith.ori, @arith.xori]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_bitwise_alu.sv"
    text = out.read_text()
    assert "module fu_bitwise_alu" in text
    assert "input  logic [1:0]        op_sel," in text
    assert "out_data = in_data_0 & in_data_1" in text


def test_generate_group5_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.andi, @arith.ori, @arith.xori]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/bitwise_alu/fu_bitwise_alu.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_min_max_signed():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.minsi", "arith.maxsi"], reg)
    assert grp["name"] == "min_max_signed"
    assert grp["rtl_module"] == "fu_min_max_signed.sv"
    assert grp["params"]["width"] == 32


def test_generate_group6_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minsi, @arith.maxsi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_min_max_signed.sv"
    text = out.read_text()
    assert "module fu_min_max_signed" in text
    assert "input  logic              op_sel," in text
    assert "$signed(in_data_0) < $signed(in_data_1)" in text


def test_generate_group6_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minsi, @arith.maxsi]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/min_max_signed/fu_min_max_signed.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_min_max_unsigned():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.minui", "arith.maxui"], reg)
    assert grp["name"] == "min_max_unsigned"
    assert grp["rtl_module"] == "fu_min_max_unsigned.sv"
    assert grp["params"]["width"] == 32


def test_generate_group7_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minui, @arith.maxui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_min_max_unsigned.sv"
    text = out.read_text()
    assert "module fu_min_max_unsigned" in text
    assert "input  logic              op_sel," in text
    assert "a_lt_b   = in_data_0 < in_data_1;" in text


def test_generate_group7_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minui, @arith.maxui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/min_max_unsigned/fu_min_max_unsigned.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_int_to_fp():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.sitofp", "arith.uitofp"], reg)
    assert grp["name"] == "int_to_fp"
    assert grp["rtl_module"] == "fu_int_to_fp.sv"
    assert grp["params"]["int_width"] == 32
    assert grp["params"]["fp_width"] == 32


def test_generate_group8_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.sitofp, @arith.uitofp]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_int_to_fp.sv"
    text = out.read_text()
    assert "module fu_int_to_fp" in text
    assert "parameter int unsigned INT_WIDTH = 32" in text
    assert "round_up = guard & (sticky | lsb)" in text


def test_generate_group8_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.sitofp, @arith.uitofp]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/int_to_fp/fu_int_to_fp.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_fp_to_int():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.fptosi", "arith.fptoui"], reg)
    assert grp["name"] == "fp_to_int"
    assert grp["rtl_module"] == "fu_fp_to_int.sv"
    assert grp["params"]["fp_width"] == 32
    assert grp["params"]["int_width"] == 32


def test_generate_group9_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.fptosi, @arith.fptoui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_fp_to_int.sv"
    text = out.read_text()
    assert "module fu_fp_to_int" in text
    assert "parameter int unsigned FP_WIDTH  = 32" in text
    assert "result = sign ? (~mag + 32'd1) : mag;" in text


def test_generate_group9_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.fptosi, @arith.fptoui]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/int_arith/fp_to_int/fu_fp_to_int.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_fp_add_sub():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.addf", "arith.subf"], reg)
    assert grp["name"] == "fp_add_sub"
    assert grp["rtl_module"] == "fu_fp_add_sub.sv"
    assert grp["params"]["width"] == 32


def test_generate_group10_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addf, @arith.subf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_fp_add_sub.sv"
    text = out.read_text()
    assert "module fu_fp_add_sub" in text
    assert "round_up = guard & (sticky | mant23[0])" in text


def test_generate_group10_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.addf, @arith.subf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/fp_arith/fp_add_sub/fu_fp_add_sub.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_fp_div_rem():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.divf", "arith.remf"], reg)
    assert grp["name"] == "fp_div_rem"
    assert grp["rtl_module"] == "fu_fp_div_rem.sv"
    assert grp["params"]["width"] == 32


def test_generate_group11_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divf, @arith.remf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_fp_div_rem.sv"
    text = out.read_text()
    assert "module fu_fp_div_rem" in text
    assert "rem_sub = ge ? (rem_sh - {1'b0, sig_b_r}) : rem_sh;" in text


def test_generate_group11_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.divf, @arith.remf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/fp_arith/fp_div_rem/fu_fp_div_rem.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_fp_min_max():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["arith.minimumf", "arith.maximumf"], reg)
    assert grp["name"] == "fp_min_max"
    assert grp["rtl_module"] == "fu_fp_min_max.sv"
    assert grp["params"]["width"] == 32


def test_generate_group12_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minimumf, @arith.maximumf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_fp_min_max.sv"
    text = out.read_text()
    assert "module fu_fp_min_max" in text
    assert "a_lt_b = key_a < key_b;" in text


def test_generate_group12_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minimumf, @arith.maximumf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/fp_arith/fp_min_max/fu_fp_min_max.sv"
    assert out.read_text() == ref.read_text()


def test_generate_unimplemented_group_raises(tmp_path):
    from fabric_gen.generator import generate
    from fabric_gen.errors import TemplateNotImplemented

    # Group 13 (cordic_trig) is a valid share group with no template yet.
    with pytest.raises(TemplateNotImplemented):
        generate("fabric.op[@math.sin, @math.cos]", tmp_path,
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
