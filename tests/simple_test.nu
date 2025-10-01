# Simple test file to test nutest integration
use std assert

#[test]
def test_simple_addition [] {
    let result = 2 + 2
    assert equal $result 4
}

#[test]
def test_string_operations [] {
    let text = "hello world"
    assert ($text | str contains "hello")
}