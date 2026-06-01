import pytest

from fabric_gen.sharegroups import validate
from fabric_gen.errors import ShareGroupError


def test_group1_add_sub():
    g = validate(["arith.addi", "arith.subi"])
    assert g.index == 1


def test_group2_div_rem_signed():
    g = validate(["arith.divsi", "arith.remsi"])
    assert g.index == 2


def test_singleton_in_group_ok():
    g = validate(["arith.addi"])
    assert g.index == 1


def test_singleton_standalone_ok():
    g = validate(["arith.muli"])
    assert g.index == 0


def test_not_in_any_group_raises():
    with pytest.raises(ShareGroupError):
        validate(["arith.addi", "arith.muli"])


def test_cross_group_raises():
    with pytest.raises(ShareGroupError):
        validate(["arith.addi", "arith.subf"])
