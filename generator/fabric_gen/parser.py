"""Parse a `fabric.op[...]` string into an op list."""

import re
from dataclasses import dataclass

from .errors import ParseError

_MEMBER_RE = re.compile(r"^[a-z]+\.[a-z0-9_]+$")


@dataclass
class ParsedOp:
    op_list: list


def parse_op_string(s: str) -> ParsedOp:
    text = s.strip()
    if not (text.startswith("fabric.op[") and text.endswith("]")):
        raise ParseError(f"expected 'fabric.op[...]', got {s!r}")
    inner = text[len("fabric.op["):-1]
    members = []
    for raw in inner.split(","):
        m = raw.strip()
        if m.startswith("@"):
            m = m[1:].strip()
        if not m:
            continue
        if not _MEMBER_RE.match(m):
            raise ParseError(f"invalid op member {m!r}")
        members.append(m)
    if not members:
        raise ParseError("empty op_list")
    return ParsedOp(op_list=members)
