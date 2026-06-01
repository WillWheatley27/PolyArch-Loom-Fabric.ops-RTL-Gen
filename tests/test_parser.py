import pytest

from fabric_gen.parser import parse_op_string
from fabric_gen.errors import ParseError


def test_single_member_no_at():
    assert parse_op_string("fabric.op[arith.addi]").op_list == ["arith.addi"]


def test_two_members_mixed_at():
    p = parse_op_string("fabric.op[@arith.addi, arith.subi]")
    assert p.op_list == ["arith.addi", "arith.subi"]


def test_two_members_both_at_and_spaces():
    p = parse_op_string("fabric.op[ @arith.addi ,  @arith.subi ]")
    assert p.op_list == ["arith.addi", "arith.subi"]


def test_missing_shell_raises():
    with pytest.raises(ParseError):
        parse_op_string("arith.addi")


def test_empty_list_raises():
    with pytest.raises(ParseError):
        parse_op_string("fabric.op[]")


def test_bad_member_raises():
    with pytest.raises(ParseError):
        parse_op_string("fabric.op[Arith.AddI!]")
