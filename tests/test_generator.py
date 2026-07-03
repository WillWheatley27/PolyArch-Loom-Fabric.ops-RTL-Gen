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
    assert "INT_WIDTH = 32" in text
    assert "EXP_W     = 8" in text          # fp32 default format
    assert "MANT_W    = 23" in text
    assert "round_up = guard & (sticky | frac[0])" in text


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
    assert "EXP_W     = 8" in text          # fp32 default format
    assert "MANT_W    = 23" in text
    assert "INT_WIDTH = 32" in text
    assert "result = sign ? (-mag) : mag;" in text


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


def test_registry_lookup_cordic_trig():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.sin", "math.cos"], reg)
    assert grp["name"] == "cordic_trig"
    assert grp["rtl_module"] == "fu_cordic_trig.sv"
    assert grp["params"]["iterations"] == 16


def test_generate_group13_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sin, @math.cos]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_cordic_trig.sv"
    text = out.read_text()
    assert "module fu_cordic_trig" in text
    assert "32'sd163008219" in text   # CORDIC gain K (Q4.28)


def test_generate_group13_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sin, @math.cos]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/cordic_trig/fu_cordic_trig.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_cordic_hyp():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.sinh", "math.cosh"], reg)
    assert grp["name"] == "cordic_hyp"
    assert grp["rtl_module"] == "fu_cordic_hyp.sv"
    assert grp["params"]["iterations"] == 16


def test_generate_group14_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sinh, @math.cosh]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_cordic_hyp.sv"
    text = out.read_text()
    assert "module fu_cordic_hyp" in text
    assert "32'sd324135026" in text   # x0 = 1/A_h (Q4.28)


def test_generate_group14_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sinh, @math.cosh]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/cordic_hyp/fu_cordic_hyp.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_approx_tanh_erf():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.tanh", "math.erf"], reg)
    assert grp["name"] == "approx_tanh_erf"
    assert grp["rtl_module"] == "fu_approx_tanh_erf.sv"
    assert grp["params"]["width"] == 32


def test_generate_group19_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.tanh, @math.erf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_approx_tanh_erf.sv"
    text = out.read_text()
    assert "module fu_approx_tanh_erf" in text
    assert "localparam logic [23:0] TANH_T [0:128]" in text
    assert "localparam logic [23:0] ERF_T [0:128]" in text


def test_generate_group19_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.tanh, @math.erf]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/approx_tanh_erf/fu_approx_tanh_erf.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_exp_series():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.exp", "math.exp2", "math.expm1"], reg)
    assert grp["name"] == "exp_series"
    assert grp["rtl_module"] == "fu_exp_series.sv"
    assert grp["params"]["width"] == 32


def test_generate_group15_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.exp, @math.exp2, @math.expm1]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_exp_series.sv"
    text = out.read_text()
    assert "module fu_exp_series" in text
    assert "32'sd1549082005" in text   # log2(e) in Q2.30
    assert "localparam logic [23:0] TWO_F [0:128]" in text


def test_generate_group15_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.exp, @math.exp2, @math.expm1]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/exp_series/fu_exp_series.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_log_core():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.log", "math.log2", "math.log10", "math.log1p"], reg)
    assert grp["name"] == "log_core"
    assert grp["rtl_module"] == "fu_log_core.sv"
    assert grp["params"]["width"] == 32


def test_generate_group16_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_log_core.sv"
    text = out.read_text()
    assert "module fu_log_core" in text
    assert "32'sd5814540" in text   # ln2 in Q.23
    assert "localparam logic signed [31:0] LOG2_M [0:128]" in text


def test_generate_group16_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.log, @math.log2, @math.log10, @math.log1p]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/log_core/fu_log_core.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_rounding():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.floor", "math.ceil", "math.round", "math.trunc", "math.roundeven"], reg)
    assert grp["name"] == "rounding"
    assert grp["rtl_module"] == "fu_rounding.sv"
    assert grp["params"]["width"] == 32


def test_generate_group17_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]",
                   tmp_path, registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_rounding.sv"
    text = out.read_text()
    assert "module fu_rounding" in text
    assert "input  logic [2:0]        op_sel," in text


def test_generate_group17_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.floor, @math.ceil, @math.round, @math.trunc, @math.roundeven]",
                   tmp_path, registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/rounding/fu_rounding.sv"
    assert out.read_text() == ref.read_text()


def test_registry_lookup_sqrt_rsqrt():
    from fabric_gen.registry import load_registry, lookup_by_ops

    reg = load_registry(ROOT / "registry.yaml")
    grp = lookup_by_ops(["math.sqrt", "math.rsqrt"], reg)
    assert grp["name"] == "sqrt_rsqrt"
    assert grp["rtl_module"] == "fu_sqrt_rsqrt.sv"
    assert grp["params"]["width"] == 32


def test_generate_group18_writes_file(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sqrt, @math.rsqrt]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    assert out.name == "fu_sqrt_rsqrt.sv"
    text = out.read_text()
    assert "module fu_sqrt_rsqrt" in text
    # compile-time minimax polynomial (Horner), not a LUT
    assert "SQRT_C  [0:SQRT_DEG]" in text
    assert "RSQRT_C [0:RSQRT_DEG]" in text
    assert "EXP_W  = 8" in text and "MANT_W = 23" in text   # fp32 default


def test_generate_group18_golden_matches_committed_rtl(tmp_path):
    from fabric_gen.generator import generate

    out = generate("fabric.op[@math.sqrt, @math.rsqrt]", tmp_path,
                   registry_path=ROOT / "registry.yaml")
    ref = ROOT / "ops/math/sqrt_rsqrt/fu_sqrt_rsqrt.sv"
    assert out.read_text() == ref.read_text()


def test_generate_cross_group_raises(tmp_path):
    # All 19 share groups are implemented. A cross-group op_list is still illegal.
    from fabric_gen.generator import generate
    from fabric_gen.errors import ShareGroupError

    with pytest.raises(ShareGroupError):
        generate("fabric.op[@math.sqrt, @math.sin]", tmp_path,
                 registry_path=ROOT / "registry.yaml")


def test_generate_integer_width_override(tmp_path):
    # Integer FUs are runtime WIDTH-parameterized; the generator honors --width.
    from fabric_gen.generator import generate

    for w in (8, 16, 64):
        out = generate("fabric.op[@arith.addi, @arith.subi]", tmp_path, width=w,
                       registry_path=ROOT / "registry.yaml")
        assert f"WIDTH = {w}" in out.read_text()


def test_generate_fp_format_override(tmp_path):
    # FP FUs are parameterized by (EXP_W, MANT_W); the generator honors --format.
    from fabric_gen.generator import generate

    out = generate("fabric.op[@arith.minimumf, @arith.maximumf]", tmp_path, fmt="fp64",
                   registry_path=ROOT / "registry.yaml")
    text = out.read_text()
    assert "MANT_W = 52" in text and "EXP_W  = 11" in text


def test_generate_unknown_format_raises(tmp_path):
    from fabric_gen.generator import generate

    with pytest.raises(ValueError):
        generate("fabric.op[@arith.addf, @arith.subf]", tmp_path, fmt="fp128",
                 registry_path=ROOT / "registry.yaml")


def test_approx_polynomial_fits():
    # Compile-time minimax-ish fitter (pure Python) for the transcendental FUs.
    import math
    from fabric_gen.approx import fit_for_precision, poly_eval, fixed_coeffs

    # fp32-tier fits over the reduced ranges.
    for func, a, b, max_deg in [
        (lambda f: math.sqrt(1.0 + f), 0.0, 1.0, 8),
        (lambda f: 2.0 ** f,           0.0, 1.0, 8),
        (lambda f: math.log2(1.0 + f), 0.0, 1.0, 10),
    ]:
        deg, coeffs, err = fit_for_precision(func, a, b, 3e-7, max_degree=max_deg)
        assert err < 3e-7
        assert deg <= max_deg
        # quantizing to Q2.28 preserves accuracy to well under a fp32 ULP
        q = fixed_coeffs(coeffs, 28)
        qc = [c / (1 << 28) for c in q]
        assert abs(poly_eval(qc, 0.5) - func(0.5)) < 1e-6


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
