"""Load and query registry.yaml."""

import yaml

from .errors import FabricGenError


def load_registry(path):
    with open(path) as f:
        data = yaml.safe_load(f)
    return data["groups"]


def lookup_by_ops(op_list, registry):
    target = set(op_list)
    for grp in registry:
        if set(grp["ops"]) == target:
            return grp
    raise FabricGenError(f"no registry group matches ops {sorted(target)}")
