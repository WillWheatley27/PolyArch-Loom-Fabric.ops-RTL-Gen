"""Orchestrate: parse -> validate -> registry lookup -> render template -> write."""

from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from .parser import parse_op_string
from .sharegroups import validate
from .registry import load_registry, lookup_by_ops
from .errors import TemplateNotImplemented

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
}

_CARRY_TERM = "{{(WIDTH-1){1'b0}}, op_sel}"


def generate(op_string, out_dir, width=None, registry_path=None):
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
    tmpl = env.get_template(_TEMPLATE_MAP[name])
    text = tmpl.render(
        module_name=module_name,
        width=eff_width,
        op_list=parsed.op_list,
        carry_term=_CARRY_TERM,
    )

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / rtl_module
    out_path.write_text(text)
    return out_path
