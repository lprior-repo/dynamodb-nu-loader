# Basic functionality tests for DynamoDB Nu-Loader - verifying nutest works
use std/testing *

@test
def "test basic math" [] {
  let result = (2 + 2)
  assert ($result == 4) "Basic math should work"
}

@test
def "test list operations" [] {
  let items = [1, 2, 3]
  assert (($items | length) == 3) "List should have 3 items"
}

@test
def "test record operations" [] {
  let person = { name: "Alice", age: 30 }
  assert ($person.name == "Alice") "Record field access should work"
  assert ($person.age == 30) "Record numeric field should work"
}

@test
def "test string operations" [] {
  let text = "hello world"
  assert (($text | str length) == 11) "String length should be correct"
  assert ($text | str starts-with "hello") "String should start with hello"
}

@test
def "test file path operations" [] {
  let temp_path = "/tmp/test_file.json"
  assert ($temp_path | str ends-with ".json") "Path should end with .json"
}

# Test helper function
def assert [condition: bool, message: string]: nothing -> nothing {
  if not $condition {
    error make { msg: $"Assertion failed: ($message)" }
  }
}