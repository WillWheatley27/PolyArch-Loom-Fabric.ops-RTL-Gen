"""Hardware share groups, mirroring docs/fabric_hardware_share_groups.md."""

from dataclasses import dataclass

from .errors import ShareGroupError

SHARE_GROUPS = [
    {"arith.addi", "arith.subi"},                                      # 1
    {"arith.divsi", "arith.remsi"},                                    # 2
    {"arith.divui", "arith.remui"},                                    # 3
    {"arith.shli", "arith.shrsi", "arith.shrui"},                      # 4
    {"arith.andi", "arith.ori", "arith.xori"},                         # 5
    {"arith.minsi", "arith.maxsi"},                                    # 6
    {"arith.minui", "arith.maxui"},                                    # 7
    {"arith.sitofp", "arith.uitofp"},                                  # 8
    {"arith.fptosi", "arith.fptoui"},                                  # 9
    {"arith.addf", "arith.subf"},                                      # 10
    {"arith.divf", "arith.remf"},                                      # 11
    {"arith.minimumf", "arith.maximumf"},                              # 12
    {"math.sin", "math.cos"},                                          # 13
    {"math.sinh", "math.cosh"},                                        # 14
    {"math.exp", "math.exp2", "math.expm1"},                           # 15
    {"math.log", "math.log2", "math.log10", "math.log1p"},             # 16
    {"math.floor", "math.ceil", "math.round", "math.trunc", "math.roundeven"},  # 17
    {"math.sqrt", "math.rsqrt"},                                       # 18
    {"math.tanh", "math.erf"},                                         # 19
]


@dataclass
class ShareGroup:
    index: int            # 1..19, or 0 for a synthetic singleton
    members: frozenset


def _group_of(op):
    for i, members in enumerate(SHARE_GROUPS, start=1):
        if op in members:
            return i
    return None


def validate(op_list) -> ShareGroup:
    if len(op_list) == 1:
        idx = _group_of(op_list[0])
        if idx is not None:
            return ShareGroup(index=idx, members=frozenset(SHARE_GROUPS[idx - 1]))
        return ShareGroup(index=0, members=frozenset(op_list))

    groups = {op: _group_of(op) for op in op_list}
    missing = [op for op, g in groups.items() if g is None]
    if missing:
        raise ShareGroupError(
            f"ops {missing} are not in any multi-member share group; a "
            f"multi-member op_list requires every member to share one group"
        )
    distinct = set(groups.values())
    if len(distinct) != 1:
        raise ShareGroupError(
            f"ops {op_list} span multiple share groups {sorted(distinct)}; all "
            f"members of a multi-member op_list must be in the same group"
        )
    idx = distinct.pop()
    return ShareGroup(index=idx, members=frozenset(SHARE_GROUPS[idx - 1]))
