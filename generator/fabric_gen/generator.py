"""Orchestrate: parse -> validate -> registry lookup -> render template -> write."""

import math
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from .parser import parse_op_string
from .sharegroups import validate
from .registry import load_registry, lookup_by_ops
from .errors import TemplateNotImplemented
from .formats import fp_format, DEFAULT_FP_FORMAT
from . import approx

_TEMPLATES = Path(__file__).resolve().parents[1] / "templates"
_DEFAULT_REGISTRY = Path(__file__).resolve().parents[2] / "registry.yaml"

# Group name -> template file.
_TEMPLATE_MAP = {
    "add_sub": "fu_add_sub.sv.j2",
    "div_rem_signed": "fu_div_rem_signed.sv.j2",
    "div_rem_unsigned": "fu_div_rem_unsigned.sv.j2",
    "barrel_shift": "fu_barrel_shift.sv.j2",
    "bitwise_alu": "fu_bitwise_alu.sv.j2",
    "min_max_signed": "fu_min_max_signed.sv.j2",
    "min_max_unsigned": "fu_min_max_unsigned.sv.j2",
    "int_to_fp": "fu_int_to_fp.sv.j2",
    "fp_to_int": "fu_fp_to_int.sv.j2",
    "fp_add_sub": "fu_fp_add_sub.sv.j2",
    "fp_div_rem": "fu_fp_div_rem.sv.j2",
    "fp_min_max": "fu_fp_min_max.sv.j2",
    "cordic_trig": "fu_cordic_trig.sv.j2",
    "cordic_hyp": "fu_cordic_hyp.sv.j2",
    "approx_tanh_erf": "fu_approx_tanh_erf.sv.j2",
    "exp_series": "fu_exp_series.sv.j2",
    "log_core": "fu_log_core.sv.j2",
    "rounding": "fu_rounding.sv.j2",
    "sqrt_rsqrt": "fu_sqrt_rsqrt.sv.j2",
}

_CARRY_TERM = "{{(WIDTH-1){1'b0}}, op_sel}"

# Groups whose transcendental core is a compile-time-generated minimax polynomial.
# NOTE: tanh/erf are intentionally NOT here -- as stiff sigmoids they need
# high-degree polynomials with huge, ill-conditioned coefficients (max|c|~7.6e4,
# i.e. ~2^43 in Q.FRAC), so a compile-time-generated LUT is the right form for
# them; only the well-conditioned [0,1) functions use the polynomial core.
_POLY_GROUPS = {"sqrt_rsqrt", "exp_series", "log_core"}


def _poly_context(name, fmt):
    """Compute per-(function, format) polynomial coefficients for the Horner
    evaluator: fractional bits, coeff width, degrees, and coeffs rendered as
    sized signed SV literals (handles widths > 32 for fp64)."""
    mant_w = fmt["mant_w"]
    frac = mant_w + 4                       # datapath fractional bits (guard incl.)
    cw = frac + 4                           # coeff width: sign + 3 int + frac
    scale = 1 << frac
    target = max(2.0 ** -(mant_w + 1), 1e-11)  # ~half ULP, floored so fp64 stays sane

    def lits(coeffs):
        ints = approx.fixed_coeffs(coeffs, frac)
        return [f"{cw}'sd{v}" if v >= 0 else f"-{cw}'sd{-v}" for v in ints]

    ctx = {"frac": frac, "cw": cw}
    if name == "sqrt_rsqrt":
        ds, cs, _ = approx.fit_for_precision(lambda f: math.sqrt(1.0 + f), 0.0, 1.0, target, max_degree=14)
        dr, cr, _ = approx.fit_for_precision(lambda f: 1.0 / math.sqrt(1.0 + f), 0.0, 1.0, target, max_degree=14)
        w = frac + 2   # width of SQRT2_Q / INVSQRT2_Q
        ctx.update(
            sqrt_deg=ds, sqrt_coef_lits=lits(cs),
            rsqrt_deg=dr, rsqrt_coef_lits=lits(cr),
            sqrt2_lit=f"{w}'d{round(math.sqrt(2.0) * scale)}",
            invsqrt2_lit=f"{w}'d{round((1.0 / math.sqrt(2.0)) * scale)}",
        )
    elif name == "exp_series":
        de, ce, _ = approx.fit_for_precision(lambda f: 2.0 ** f, 0.0, 1.0, target, max_degree=12)
        ctx.update(exp2f_deg=de, exp2f_coef_lits=lits(ce))
    elif name == "log_core":
        dl, cl, _ = approx.fit_for_precision(lambda f: math.log2(1.0 + f), 0.0, 1.0, target, max_degree=12)
        sw = frac + 2   # width of scale constants (ONE needs frac+1 bits)
        ctx.update(
            log2m_deg=dl, log2m_coef_lits=lits(cl),
            ln2_lit=f"{sw}'d{round(math.log(2.0) * scale)}",
            invlog2_10_lit=f"{sw}'d{round((1.0 / math.log2(10.0)) * scale)}",
            one_lit=f"{sw}'d{scale}",
        )
    return ctx


def generate(op_string, out_dir, width=None, fmt=None, registry_path=None):
    parsed = parse_op_string(op_string)
    validate(parsed.op_list)  # raises ShareGroupError on illegal combinations

    registry = load_registry(registry_path or _DEFAULT_REGISTRY)
    grp = lookup_by_ops(parsed.op_list, registry)
    name = grp["name"]
    if name not in _TEMPLATE_MAP:
        raise TemplateNotImplemented(
            f"RTL template for share group '{name}' is not yet implemented"
        )

    rtl_module = grp["rtl_module"]
    module_name = rtl_module[:-3] if rtl_module.endswith(".sv") else rtl_module
    eff_width = width if width is not None else grp.get("params", {}).get("width", 32)

    env = Environment(
        loader=FileSystemLoader(str(_TEMPLATES)),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    fmt_desc = fp_format(fmt or DEFAULT_FP_FORMAT)
    poly = _poly_context(name, fmt_desc) if name in _POLY_GROUPS else {}

    tmpl = env.get_template(_TEMPLATE_MAP[name])
    text = tmpl.render(
        module_name=module_name,
        width=eff_width,
        op_list=parsed.op_list,
        carry_term=_CARRY_TERM,
        params=grp.get("params", {}),
        fmt=fmt_desc,
        poly=poly,
    )

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / rtl_module
    out_path.write_text(text)
    return out_path
