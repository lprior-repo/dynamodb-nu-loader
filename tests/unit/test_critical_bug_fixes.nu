#!/usr/bin/env nu

# Test suite for critical bug fixes
# Tests dynamic key schema discovery, improved data type mapping, and error handling
use std/testing *
use ../helpers/test_utils.nu *

@test
def test_convert_to_dynamodb_value_handles_null [] {
    let result = convert_to_dynamodb_value null
    assert_eq $result {"NULL": true} "Null values should convert to DynamoDB NULL type"
}

@test
def test_convert_to_dynamodb_value_handles_nested_records [] {
    let test_record = {
        name: "John",
        age: 30,
        active: true
    }
    let result = convert_to_dynamodb_value $test_record
    
    assert (($result | get "M" | get "name" | get "S") == "John") "Nested record name should be string"
    assert (($result | get "M" | get "age" | get "N") == "30") "Nested record age should be number string"
    assert (($result | get "M" | get "active" | get "BOOL") == true) "Nested record active should be boolean"
}

@test
def test_convert_to_dynamodb_value_handles_homogeneous_string_list [] {
    let test_list = ["apple", "banana", "cherry"]
    let result = convert_to_dynamodb_value $test_list
    
    assert (($result | get "SS") == $test_list) "Homogeneous string list should use SS (String Set)"
}

@test
def test_convert_to_dynamodb_value_handles_homogeneous_number_list [] {
    let test_list = [1, 2, 3]
    let result = convert_to_dynamodb_value $test_list
    
    assert (($result | get "NS") == ["1", "2", "3"]) "Homogeneous number list should use NS (Number Set)"
}

@test
def test_convert_to_dynamodb_value_handles_mixed_type_list [] {
    let test_list = ["apple", 42, true]
    let result = convert_to_dynamodb_value $test_list
    
    let list_items = $result | get "L"
    assert (($list_items | length) == 3) "Mixed type list should use L (List) format"
    assert (($list_items | first | get "S") == "apple") "First item should be string"
    assert (($list_items | get 1 | get "N") == "42") "Second item should be number"
    assert (($list_items | get 2 | get "BOOL") == true) "Third item should be boolean"
}

@test
def test_convert_to_dynamodb_value_handles_empty_list [] {
    let result = convert_to_dynamodb_value []
    
    assert (($result | get "L") == []) "Empty list should use L (List) format with empty array"
}

@test
def test_convert_from_dynamodb_value_handles_null [] {
    let dynamodb_value = {"NULL": true}
    let result = convert_from_dynamodb_value $dynamodb_value
    
    assert ($result == null) "DynamoDB NULL should convert to null"
}

@test
def test_convert_from_dynamodb_value_handles_string_set [] {
    let dynamodb_value = {"SS": ["apple", "banana", "cherry"]}
    let result = convert_from_dynamodb_value $dynamodb_value
    
    assert ($result == ["apple", "banana", "cherry"]) "DynamoDB SS should convert to string list"
}

@test
def test_convert_from_dynamodb_value_handles_number_set [] {
    let dynamodb_value = {"NS": ["1", "2", "3"]}
    let result = convert_from_dynamodb_value $dynamodb_value
    
    assert ($result == [1, 2, 3]) "DynamoDB NS should convert to number list"
}

@test
def test_convert_from_dynamodb_value_handles_number_conversion [] {
    # Test integer
    let int_value = {"N": "42"}
    let int_result = convert_from_dynamodb_value $int_value
    assert ($int_result == 42) "DynamoDB N should convert to int when possible"
    
    # Test float
    let float_value = {"N": "42.5"}
    let float_result = convert_from_dynamodb_value $float_value
    assert ($float_result == 42.5) "DynamoDB N should convert to float when needed"
}

@test
def test_convert_from_dynamodb_value_handles_nested_map [] {
    let dynamodb_value = {
        "M": {
            "name": {"S": "John"},
            "age": {"N": "30"},
            "active": {"BOOL": true}
        }
    }
    let result = convert_from_dynamodb_value $dynamodb_value
    
    assert ($result.name == "John") "Nested map name should be string"
    assert ($result.age == 30) "Nested map age should be number"
    assert ($result.active == true) "Nested map active should be boolean"
}

@test
def test_convert_from_dynamodb_value_handles_list [] {
    let dynamodb_value = {
        "L": [
            {"S": "apple"},
            {"N": "42"},
            {"BOOL": true}
        ]
    }
    let result = convert_from_dynamodb_value $dynamodb_value
    
    assert (($result | length) == 3) "List should have 3 items"
    assert (($result | first) == "apple") "First item should be string"
    assert (($result | get 1) == 42) "Second item should be number"
    assert (($result | get 2) == true) "Third item should be boolean"
}

@test
def test_get_key_attributes_for_item_with_string_keys [] {
    let item = {
        user_id: "user123",
        timestamp: "2024-01-01",
        data: "some value"
    }
    
    let key_schema = [
        {AttributeName: "user_id", KeyType: "HASH"},
        {AttributeName: "timestamp", KeyType: "RANGE"}
    ]
    
    let attribute_definitions = [
        {AttributeName: "user_id", AttributeType: "S"},
        {AttributeName: "timestamp", AttributeType: "S"}
    ]
    
    let result = get_key_attributes_for_item $item $key_schema $attribute_definitions
    
    assert (($result.user_id.S) == "user123") "Hash key should be extracted as string"
    assert (($result.timestamp.S) == "2024-01-01") "Range key should be extracted as string"
    assert (($result | columns | length) == 2) "Only key attributes should be included"
}

@test
def test_get_key_attributes_for_item_with_number_keys [] {
    let item = {
        pk: 123,
        sk: 456,
        data: "some value"
    }
    
    let key_schema = [
        {AttributeName: "pk", KeyType: "HASH"},
        {AttributeName: "sk", KeyType: "RANGE"}
    ]
    
    let attribute_definitions = [
        {AttributeName: "pk", AttributeType: "N"},
        {AttributeName: "sk", AttributeType: "N"}
    ]
    
    let result = get_key_attributes_for_item $item $key_schema $attribute_definitions
    
    assert (($result.pk.N) == "123") "Numeric hash key should be converted to string"
    assert (($result.sk.N) == "456") "Numeric range key should be converted to string"
    assert (($result | columns | length) == 2) "Only key attributes should be included"
}

@test
def test_get_key_attributes_for_item_with_single_key [] {
    let item = {
        id: "item123",
        data: "some value"
    }
    
    let key_schema = [
        {AttributeName: "id", KeyType: "HASH"}
    ]
    
    let attribute_definitions = [
        {AttributeName: "id", AttributeType: "S"}
    ]
    
    let result = get_key_attributes_for_item $item $key_schema $attribute_definitions
    
    assert (($result.id.S) == "item123") "Single hash key should be extracted"
    assert (($result | columns | length) == 1) "Only hash key should be included"
}

# All tests completed - no print needed in module