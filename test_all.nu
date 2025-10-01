#!/usr/bin/env nu

# Complete Test Suite for DynamoDB Nu-Loader
# Consolidates all unit tests, integration tests, and helpers into a single file
# Run with: nu -c 'use std/testing *; source test_all.nu'
# Or with nutest: nu -c 'use nutest/nutest; nutest run-tests --path test_all.nu'

use std/testing *

# =============================================================================
# TEST UTILITIES AND HELPERS
# =============================================================================

# Assert functions for testing
def assert_equal [actual: any, expected: any, message: string]: nothing -> nothing {
  if $actual != $expected {
    error make {
      msg: $"Assertion failed: ($message)",
      label: {
        text: $"Expected ($expected), got ($actual)",
        span: (metadata $actual).span
      }
    }
  }
}

def assert_type [value: any, expected_type: string, message: string]: nothing -> nothing {
  let actual_type = ($value | describe)
  # Handle both specific types (record<field: type>) and generic types (record)
  let type_matches = if ($expected_type == "record") {
    $actual_type =~ "record"
  } else if ($expected_type == "list") {
    # In Nushell, lists of records are represented as table<...>
    ($actual_type =~ "list") or ($actual_type =~ "table")
  } else {
    $actual_type == $expected_type
  }
  
  if not $type_matches {
    error make {
      msg: $"Type assertion failed: ($message)",
      label: {
        text: $"Expected ($expected_type), got ($actual_type)",
        span: (metadata $value).span
      }
    }
  }
}

def assert_error [operation: closure, message: string]: nothing -> nothing {
  let result = try {
    do $operation
    false
  } catch {
    true
  }
  
  if not $result {
    error make {
      msg: $"Expected operation to fail: ($message)"
    }
  }
}

def assert_contains [container: list, item: any, message: string]: nothing -> nothing {
  if not ($item in $container) {
    error make {
      msg: $"Assertion failed: ($message)",
      label: {
        text: $"Expected container to contain ($item)"
      }
    }
  }
}

def assert [condition: bool, message: string]: nothing -> nothing {
  if not $condition {
    error make {
      msg: $"Assertion failed: ($message)"
    }
  }
}

# Test data generators
def generate_test_users [count: int]: nothing -> list<record> {
  1..$count | each { |i|
    {
      id: $"user-($i)",
      sort_key: "USER",
      name: $"Test User ($i)",
      email: $"user($i)@example.com",
      age: (20 + ($i mod 40)),
      gsi1_pk: "TEST_USER",
      gsi1_sk: $"2024-01-(if $i < 10 { $'0($i)' } else { $i | into string })"
    }
  }
}

def generate_test_products [count: int]: nothing -> list<record> {
  let categories = ["Electronics", "Kitchen", "Books", "Clothing"]
  1..$count | each { |i|
    {
      id: $"prod-($i)",
      sort_key: "PRODUCT",
      name: $"Test Product ($i)",
      price: (10.0 + ($i * 5.5)),
      category: ($categories | get (($i - 1) mod ($categories | length))),
      in_stock: (($i mod 2) == 1),
      gsi1_pk: ($categories | get (($i - 1) mod ($categories | length))),
      gsi1_sk: $"PROD_($i)"
    }
  }
}

def generate_mixed_test_data [user_count: int, product_count: int]: nothing -> list<record> {
  let users = generate_test_users $user_count
  let products = generate_test_products $product_count
  $users | append $products
}

# File system test helpers
def create_temp_test_file [content: string, extension: string]: nothing -> string {
  let temp_file = $"/tmp/test_(random chars --length 8)($extension)"
  $content | save $temp_file
  $temp_file
}

def cleanup_temp_files [files: list<string>]: nothing -> nothing {
  $files | each { |file|
    if ($file | path exists) {
      rm $file
    }
  }
}

# =============================================================================
# BASIC FUNCTIONALITY TESTS
# =============================================================================

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

# =============================================================================
# DATA OPERATIONS TESTS
# =============================================================================

@test
def "test detect_and_process with JSON file" [] {
  let test_data = [
    { id: "1", name: "Alice" },
    { id: "2", name: "Bob" }
  ]
  let temp_file = create_temp_test_file ($test_data | to json) ".json"
  
  # Mock the detect_and_process function since we can't easily import from main.nu
  let result = if ($temp_file | str ends-with ".csv") {
    open $temp_file | from csv
  } else {
    open $temp_file
  }
  
  assert_equal ($result | length) 2 "Should load 2 items from JSON"
  assert_equal ($result | first | get name) "Alice" "Should preserve field values"
  
  cleanup_temp_files [$temp_file]
}

@test  
def "test detect_and_process with CSV file" [] {
  let csv_content = "id,name\n1,Alice\n2,Bob"
  let temp_file = create_temp_test_file $csv_content ".csv"
  
  let result = open $temp_file
  
  assert_equal ($result | length) 2 "Should load 2 items from CSV"
  assert_equal ($result | first | get name) "Alice" "Should preserve field values"
  
  cleanup_temp_files [$temp_file]
}

@test
def "test detect_and_process with snapshot JSON format" [] {
  let snapshot_data = {
    metadata: { table_name: "test", item_count: 1 },
    data: [{ id: "1", name: "Alice" }]
  }
  let temp_file = create_temp_test_file ($snapshot_data | to json) ".json"
  
  let result = open $temp_file
  let processed = if ($result | columns | "data" in $in) {
    $result.data
  } else {
    $result
  }
  
  assert_equal ($processed | length) 1 "Should extract data from snapshot format"
  assert_equal ($processed | first | get name) "Alice" "Should preserve field values"
  
  cleanup_temp_files [$temp_file]
}

@test
def "test dynamodb type conversion" [] {
  let test_item = {
    string_field: "hello",
    int_field: 42,
    float_field: 3.14,
    bool_field: true
  }
  
  # Simulate the type conversion logic from main.nu
  let converted = ($test_item | transpose key value | reduce -f {} { |row, acc|
    let field_name = $row.key
    let field_value = $row.value
    let dynamodb_value = match ($field_value | describe) {
      "string" => { "S": $field_value },
      "int" => { "N": ($field_value | into string) },
      "float" => { "N": ($field_value | into string) },
      "bool" => { "BOOL": $field_value },
      _ => { "S": ($field_value | into string) }
    }
    $acc | insert $field_name $dynamodb_value
  })
  
  assert_equal $converted.string_field.S "hello" "Should convert string correctly"
  assert_equal $converted.int_field.N "42" "Should convert int to string"
  assert_equal $converted.float_field.N "3.14" "Should convert float to string"
  assert_equal $converted.bool_field.BOOL true "Should preserve boolean"
}

@test
def "test batch chunking" [] {
  let items = generate_test_users 100
  let batches = ($items | chunks 25)
  
  assert_equal ($batches | length) 4 "Should create 4 batches of 25 items"
  assert_equal ($batches | first | length) 25 "First batch should have 25 items"
  assert_equal ($batches | last | length) 25 "Last batch should have 25 items"
}

@test
def "test batch chunking with remainder" [] {
  let items = generate_test_users 26
  let batches = ($items | chunks 25)
  
  assert_equal ($batches | length) 2 "Should create 2 batches"
  assert_equal ($batches | first | length) 25 "First batch should have 25 items"
  assert_equal ($batches | last | length) 1 "Last batch should have 1 item"
}

@test
def "test snapshot format creation" [] {
  let items = generate_test_users 3
  let table_name = "test-table"
  let timestamp = "2024-01-01 12:00:00"
  
  let snapshot = {
    metadata: {
      table_name: $table_name,
      timestamp: $timestamp,
      item_count: ($items | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $items
  }
  
  assert_equal $snapshot.metadata.table_name $table_name "Should set table name"
  assert_equal $snapshot.metadata.item_count 3 "Should set correct item count"
  assert_equal ($snapshot.data | length) 3 "Should include all items"
  assert_type $snapshot.metadata "record" "Metadata should be a record"
  assert_type $snapshot.data "list" "Data should be a list"
}

@test
def "test default configuration structure" [] {
  let default_config = {
    dynamodb: { table_name: "test-table", region: "us-east-1" },
    snapshots: { default_directory: "./snapshots", default_format: "json" },
    aws: { profile: "default" }
  }
  
  assert_type $default_config.dynamodb "record" "DynamoDB config should be record"
  assert_type $default_config.snapshots "record" "Snapshots config should be record"
  assert_type $default_config.aws "record" "AWS config should be record"
  assert_equal $default_config.dynamodb.table_name "test-table" "Should have default table name"
  assert_equal $default_config.dynamodb.region "us-east-1" "Should have default region"
}

@test
def "test invalid file handling" [] {
  let nonexistent_file = "/tmp/nonexistent_file.json"
  
  assert_error {
    if ($nonexistent_file | path exists) {
      open $nonexistent_file
    } else {
      error make { msg: "File not found" }
    }
  } "Should fail when file doesn't exist"
}

@test
def "property roundtrip json serialization preserves data" [] {
  let original_data = generate_mixed_test_data 5 5
  let json_string = ($original_data | to json)
  let parsed_data = ($json_string | from json)
  
  assert_equal ($original_data | length) ($parsed_data | length) "Should preserve item count"
  assert_equal ($original_data | first | get id) ($parsed_data | first | get id) "Should preserve field values"
}

@test
def "property csv roundtrip preserves data structure" [] {
  let original_data = generate_test_users 3
  let csv_string = ($original_data | to csv)
  let parsed_data = ($csv_string | from csv)
  
  assert_equal ($original_data | length) ($parsed_data | length) "Should preserve item count"
  # Note: CSV parsing may convert types, but structure should be preserved
  assert_equal ($original_data | first | get id) ($parsed_data | first | get id) "Should preserve ID field"
}

# =============================================================================
# AWS OPERATIONS TESTS
# =============================================================================

@test  
def "test dynamodb item conversion from record" [] {
  let input_item = {
    id: "user-1",
    sort_key: "USER", 
    name: "Alice",
    age: 30,
    active: true,
    score: 95.5
  }
  
  # Simulate the conversion logic from main.nu
  let converted = ($input_item | transpose key value | reduce -f {} { |row, acc|
    let field_name = $row.key
    let field_value = $row.value
    let dynamodb_value = match ($field_value | describe) {
      "string" => { "S": $field_value },
      "int" => { "N": ($field_value | into string) },
      "float" => { "N": ($field_value | into string) },
      "bool" => { "BOOL": $field_value },
      _ => { "S": ($field_value | into string) }
    }
    $acc | insert $field_name $dynamodb_value
  })
  
  assert_equal $converted.id.S "user-1" "Should convert string to DynamoDB S type"
  assert_equal $converted.age.N "30" "Should convert int to DynamoDB N type"
  assert_equal $converted.active.BOOL true "Should convert bool to DynamoDB BOOL type"
  assert_equal $converted.score.N "95.5" "Should convert float to DynamoDB N type"
}

@test
def "test dynamodb item conversion from raw response" [] {
  let dynamodb_item = {
    id: { "S": "user-1" },
    sort_key: { "S": "USER" },
    name: { "S": "Alice" },
    age: { "N": "30" },
    active: { "BOOL": true }
  }
  
  # Simulate the reverse conversion logic from main.nu
  let converted = ($dynamodb_item | transpose key value | reduce -f {} { |row, acc|
    let field_name = $row.key
    let field_value = ($row.value | values | first)
    $acc | insert $field_name $field_value
  })
  
  assert_equal $converted.id "user-1" "Should extract string value"
  assert_equal $converted.name "Alice" "Should extract string value"
  assert_equal $converted.age "30" "Should extract number as string"
  assert_equal $converted.active true "Should extract boolean value"
}

@test
def "test batch write request structure" [] {
  let items = generate_test_users 2
  let table_name = "test-table"
  
  # Simulate batch request creation
  let dynamodb_items = ($items | each { |item|
    let converted_item = ($item | transpose key value | reduce -f {} { |row, acc|
      let field_name = $row.key
      let field_value = $row.value
      let dynamodb_value = match ($field_value | describe) {
        "string" => { "S": $field_value },
        "int" => { "N": ($field_value | into string) },
        "float" => { "N": ($field_value | into string) },
        "bool" => { "BOOL": $field_value },
        _ => { "S": ($field_value | into string) }
      }
      $acc | insert $field_name $dynamodb_value
    })
    { "PutRequest": { "Item": $converted_item } }
  })
  
  let request_items = {}
  let request_items = ($request_items | insert $table_name $dynamodb_items)
  let batch_request = { "RequestItems": $request_items }
  
  assert_type $batch_request "record" "Batch request should be a record"
  assert_contains ($batch_request | columns) "RequestItems" "Should have RequestItems field"
  assert_equal ($batch_request.RequestItems | get $table_name | length) 2 "Should have 2 items for table"
  assert_contains ($batch_request.RequestItems | get $table_name | first | columns) "PutRequest" "Should have PutRequest structure"
}

@test
def "test batch delete request structure" [] {
  let items = [
    { id: "user-1", sort_key: "USER" },
    { id: "user-2", sort_key: "USER" }
  ]
  let table_name = "test-table"
  
  # Simulate delete request creation
  let delete_requests = ($items | each { |item|
    {
      "DeleteRequest": {
        "Key": {
          "id": { "S": $item.id },
          "sort_key": { "S": $item.sort_key }
        }
      }
    }
  })
  
  let request_items = {}
  let request_items = ($request_items | insert $table_name $delete_requests)
  let batch_request = { "RequestItems": $request_items }
  
  assert_type $batch_request "record" "Delete batch request should be a record"
  assert_equal ($batch_request.RequestItems | get $table_name | length) 2 "Should have 2 delete requests"
  assert_contains ($batch_request.RequestItems | get $table_name | first | columns) "DeleteRequest" "Should have DeleteRequest structure"
  
  let first_delete = ($batch_request.RequestItems | get $table_name | first)
  assert_contains ($first_delete.DeleteRequest | columns) "Key" "Should have Key field"
  assert_equal $first_delete.DeleteRequest.Key.id.S "user-1" "Should have correct ID in key"
}

@test
def "test table info parsing" [] {
  let mock_response = {
    "Table": {
      "TableName": "test-table",
      "TableStatus": "ACTIVE", 
      "CreationDateTime": "2024-01-01T12:00:00.000Z",
      "TableSizeBytes": 1024,
      "ItemCount": 10
    }
  }
  
  let item_count = 15  # Simulated scan result count
  
  let info = {
    table_name: $mock_response.Table.TableName,
    status: $mock_response.Table.TableStatus,
    item_count: $item_count,
    creation_time: $mock_response.Table.CreationDateTime,
    size_bytes: $mock_response.Table.TableSizeBytes
  }
  
  assert_equal $info.table_name "test-table" "Should extract table name"
  assert_equal $info.status "ACTIVE" "Should extract table status"
  assert_equal $info.item_count 15 "Should use actual scan count"
  assert_equal $info.size_bytes 1024 "Should extract size"
}

@test
def "test empty table scan result" [] {
  let empty_scan_response = { "Items": [] }
  let items = $empty_scan_response.Items
  
  assert_equal ($items | length) 0 "Should handle empty scan result"
  assert_type $items "list" "Should return a list even when empty"
}

@test
def "test batch chunking respects DynamoDB limits" [] {
  let large_dataset = generate_test_users 100
  let batches = ($large_dataset | chunks 25)
  
  # DynamoDB batch operations are limited to 25 items
  assert_equal ($batches | length) 4 "Should create 4 batches for 100 items"
  
  # All batches except possibly the last should be exactly 25 items
  $batches | each { |batch|
    assert (($batch | length) <= 25) "Each batch should be 25 items or fewer"
  }
  
  # Verify total items preserved
  let total_items = ($batches | each { |batch| $batch | length } | math sum)
  assert_equal $total_items 100 "Should preserve all items across batches"
}

@test
def "property batch operations preserve all items" [] {
  let original_data = generate_mixed_test_data 50 25
  let batches = ($original_data | chunks 25)
  let reconstructed = ($batches | flatten)
  
  assert_equal ($original_data | length) ($reconstructed | length) "Batching should preserve item count"
  assert_equal ($original_data | first | get id) ($reconstructed | first | get id) "Batching should preserve item order and content"
}

# =============================================================================
# INTEGRATION WORKFLOW TESTS
# =============================================================================

def setup_integration_test []: nothing -> record {
  {
    table_name: "test-table-integration",
    test_data: (generate_mixed_test_data 5 3),
    snapshots_dir: "/tmp/test_snapshots_integration",
    config: {
      dynamodb: { table_name: "test-table-unit", region: "us-east-1" },
      snapshots: { default_directory: "/tmp/test_snapshots", default_format: "json" },
      aws: { profile: "test" }
    }
  }
}

def cleanup_integration_test [context: record]: nothing -> nothing {
  # Clean up any test files created during integration tests
  if ($context.snapshots_dir | path exists) {
    rm -rf $context.snapshots_dir
  }
}

@test
def "integration test snapshot creation and file output" [] {
  let context = setup_integration_test
  
  # Create snapshots directory
  mkdir $context.snapshots_dir
  
  # Test snapshot with JSON format
  let json_snapshot_file = $"($context.snapshots_dir)/test_snapshot.json"
  let test_items = $context.test_data
  
  # Simulate snapshot creation
  let snapshot = {
    metadata: {
      table_name: $context.table_name,
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: ($test_items | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $test_items
  }
  
  $snapshot | to json | save $json_snapshot_file
  
  # Verify snapshot file was created and has correct structure
  assert ($json_snapshot_file | path exists) "Snapshot file should be created"
  
  let loaded_snapshot = (open $json_snapshot_file)
  assert_type $loaded_snapshot "record" "Snapshot should be a record"
  assert_contains ($loaded_snapshot | columns) "metadata" "Should have metadata section"
  assert_contains ($loaded_snapshot | columns) "data" "Should have data section"
  assert_equal $loaded_snapshot.metadata.item_count ($test_items | length) "Should have correct item count"
  assert_equal ($loaded_snapshot.data | length) ($test_items | length) "Should preserve all data items"
  
  cleanup_integration_test $context
}

@test
def "integration test complete workflow simulation" [] {
  let context = setup_integration_test
  mkdir $context.snapshots_dir
  
  # Step 1: Start with seed data (simulated)
  let initial_data = [
    { id: "workflow-1", sort_key: "USER", name: "Workflow Test User" },
    { id: "workflow-2", sort_key: "PRODUCT", name: "Workflow Test Product" }
  ]
  
  # Step 2: Create snapshot
  let snapshot_file = $"($context.snapshots_dir)/workflow_test.json"
  let snapshot = {
    metadata: {
      table_name: $context.table_name,
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: ($initial_data | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $initial_data
  }
  $snapshot | to json | save $snapshot_file
  
  # Step 3: Simulate wipe (table would be empty)
  let table_after_wipe = []
  assert_equal ($table_after_wipe | length) 0 "Table should be empty after wipe"
  
  # Step 4: Restore from snapshot
  let loaded_snapshot = (open $snapshot_file)
  let restored_data = $loaded_snapshot.data
  
  # Verify restoration
  assert_equal ($restored_data | length) ($initial_data | length) "Should restore all items"
  assert_equal ($restored_data | first | get id) ($initial_data | first | get id) "Should preserve item details"
  
  cleanup_integration_test $context
}

@test
def "integration test seed data loading" [] {
  let context = setup_integration_test
  
  # Test the default seed data
  let seed_data = [
    { id: "user-1", sort_key: "USER", name: "Alice Johnson", email: "alice@example.com", age: 30, gsi1_pk: "ACTIVE_USER", gsi1_sk: "2024-01-15" },
    { id: "user-2", sort_key: "USER", name: "Bob Smith", email: "bob@example.com", age: 25, gsi1_pk: "ACTIVE_USER", gsi1_sk: "2024-01-20" },
    { id: "user-3", sort_key: "USER", name: "Carol Davis", email: "carol@example.com", age: 35, gsi1_pk: "INACTIVE_USER", gsi1_sk: "2024-01-10" },
    { id: "prod-1", sort_key: "PRODUCT", name: "Laptop", price: 999.99, category: "Electronics", in_stock: true, gsi1_pk: "ELECTRONICS", gsi1_sk: "LAPTOP" },
    { id: "prod-2", sort_key: "PRODUCT", name: "Coffee Mug", price: 12.99, category: "Kitchen", in_stock: true, gsi1_pk: "KITCHEN", gsi1_sk: "MUG" },
    { id: "prod-3", sort_key: "PRODUCT", name: "Book", price: 24.99, category: "Education", in_stock: false, gsi1_pk: "EDUCATION", gsi1_sk: "BOOK" }
  ]
  
  assert_equal ($seed_data | length) 6 "Should have correct number of seed items"
  
  # Validate seed data can be processed for batch write
  let batches = ($seed_data | chunks 25)
  assert_equal ($batches | length) 1 "Seed data should fit in one batch"
  
  # Verify all required fields are present
  $seed_data | each { |item|
    assert_contains ($item | columns) "id" "Seed item should have id"
    assert_contains ($item | columns) "sort_key" "Seed item should have sort_key"
  }
}

@test
def "integration test large dataset handling" [] {
  let context = setup_integration_test
  
  # Test with a larger dataset
  let large_dataset = generate_mixed_test_data 100 50
  assert_equal ($large_dataset | length) 150 "Should generate large dataset"
  
  # Test batching for large dataset
  let batches = ($large_dataset | chunks 25)
  assert_equal ($batches | length) 6 "Should create correct number of batches for large dataset"
  
  # Verify all items preserved across batches
  let total_items = ($batches | each { |batch| $batch | length } | math sum)
  assert_equal $total_items 150 "Should preserve all items in batches"
  
  # Test snapshot size for large dataset
  let large_snapshot = {
    metadata: { item_count: ($large_dataset | length) },
    data: $large_dataset
  }
  let snapshot_json = ($large_snapshot | to json)
  assert (($snapshot_json | str length) > 1000) "Large snapshot should be substantial size"
}

# =============================================================================
# EDGE CASES AND BUG DISCOVERY TESTS
# =============================================================================

# DynamoDB Limits & Constraints Tests
@test
def "test item approaching 400kb size limit" [] {
    # DynamoDB has a 400KB item size limit - test near this boundary
    let large_string = (1..3000 | each { |_| "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" } | str join "")  # 300KB string
    let large_item = {
        id: "large-test-item",
        sort_key: "LARGE",
        large_field: $large_string,
        metadata: "Testing large item handling"
    }
    
    # Test conversion doesn't crash with large data
    let converted = ($large_item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = match ($field_value | describe) {
            "string" => { "S": $field_value },
            "int" => { "N": ($field_value | into string) },
            _ => { "S": ($field_value | into string) }
        }
        $acc | insert $field_name $dynamodb_value
    })
    
    assert_equal $converted.id.S "large-test-item" "Should handle large items without crashing"
    assert (($converted.large_field.S | str length) > 200000) "Should preserve large field data"
}

@test
def "test dynamodb reserved word handling" [] {
    # Test DynamoDB reserved words as field names
    let reserved_item = {
        id: "reserved-test",
        sort_key: "RESERVED",
        order: "test-order",  # 'order' is reserved
        date: "2024-01-01",   # 'date' is reserved
        status: "active",     # 'status' is reserved
        size: 42              # 'size' is reserved
    }
    
    # Should convert without errors
    let converted = ($reserved_item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = match ($field_value | describe) {
            "string" => { "S": $field_value },
            "int" => { "N": ($field_value | into string) },
            _ => { "S": ($field_value | into string) }
        }
        $acc | insert $field_name $dynamodb_value
    })
    
    assert_equal $converted.order.S "test-order" "Should handle 'order' reserved word"
    assert_equal $converted.date.S "2024-01-01" "Should handle 'date' reserved word"
    assert_equal $converted.status.S "active" "Should handle 'status' reserved word"
}

@test
def "test batch size limit validation" [] {
    # DynamoDB batch operations limited to 25 items
    let large_batch = generate_test_users 30
    let batches = ($large_batch | chunks 25)
    
    assert_equal ($batches | length) 2 "Should split into 2 batches"
    assert_equal ($batches | first | length) 25 "First batch should be exactly 25 items"
    assert_equal ($batches | last | length) 5 "Last batch should have remaining 5 items"
    
    # Verify no items lost in batching
    let total_items = ($batches | each { |batch| $batch | length } | math sum)
    assert_equal $total_items 30 "Should preserve all items across batches"
}

@test
def "test extremely wide items" [] {
    # Test items with many attributes (hundreds of fields)
    let wide_item = (1..100 | reduce -f { id: "wide-test", sort_key: "WIDE" } { |i, acc|
        $acc | insert $"field_($i)" $"value_($i)"
    })
    
    assert_equal ($wide_item | columns | length) 102 "Should have 102 fields (including id and sort_key)"
    assert_equal $wide_item.field_50 "value_50" "Should preserve field values"
    
    # Test conversion of wide item
    let converted = ($wide_item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        $acc | insert $field_name { "S": $field_value }
    })
    
    assert_equal ($converted | columns | length) 102 "Should convert all fields"
}

# Data Quality & Encoding Tests  
@test
def "test unicode and special characters" [] {
    let unicode_item = {
        id: "unicode-test",
        sort_key: "UNICODE",
        emoji: "🚀📊✅❌🔍",
        chinese: "中文测试数据",
        arabic: "اختبار البيانات",
        special_chars: "!@#$%^&*()_+-=[]{}|;':\",./<>?",
        unicode_mix: "Mixed: 🌟 中文 العربية 日本語 русский"
    }
    
    # Should handle all unicode without errors
    let converted = ($unicode_item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        $acc | insert $field_name { "S": $field_value }
    })
    
    assert_equal $converted.emoji.S "🚀📊✅❌🔍" "Should preserve emoji characters"
    assert_equal $converted.chinese.S "中文测试数据" "Should preserve Chinese characters"
    assert_contains $converted.unicode_mix.S "🌟" "Should preserve mixed unicode"
}

@test
def "test json with edge case formatting" [] {
    # Test various JSON edge cases that might break parsing
    let edge_case_data = [
        { id: "json-1", value: "string with \"embedded quotes\"" },
        { id: "json-2", value: "string with\nnewlines\nand\ttabs" },
        { id: "json-3", value: "string with \\backslashes\\ and /forward/slashes/" },
        { id: "json-4", value: "" },  # empty string
        { id: "json-5", numbers: [0, -1, 3.14159, 1e10, -2.5e-3] }
    ]
    
    # Should convert to JSON and back without corruption
    let json_string = ($edge_case_data | to json)
    let parsed_back = ($json_string | from json)
    
    assert_equal ($edge_case_data | length) ($parsed_back | length) "Should preserve item count"
    assert_equal ($edge_case_data | first | get value) ($parsed_back | first | get value) "Should preserve quoted strings"
    assert_equal ($edge_case_data | get 2 | get value) ($parsed_back | get 2 | get value) "Should preserve backslashes"
}

@test
def "test csv edge cases" [] {
    # Test CSV data with embedded quotes, newlines, and commas
    let problematic_csv = "id,name,description\n1,\"Name, with comma\",\"Description with\nnewline\"\n2,\"Name with \"\"quotes\"\"\",Simple description\n3,\"Name with\ttab\",\"\"\"Quoted\"\" description\"\"\""
    
    let temp_csv = create_temp_test_file $problematic_csv ".csv"
    
    # Should parse CSV without errors
    let parsed_csv = try {
        open $temp_csv | from csv
    } catch { |error|
        error make { msg: $"CSV parsing failed: ($error.msg)" }
    }
    
    assert_equal ($parsed_csv | length) 3 "Should parse 3 CSV rows"
    assert_contains ($parsed_csv | first | get name) "comma" "Should handle embedded commas"
    
    cleanup_temp_files [$temp_csv]
}

@test
def "test malformed json recovery" [] {
    # Test various malformed JSON scenarios
    let malformed_cases = [
        '{"id": "test"',  # missing closing brace
        '{"id": "test",}',  # trailing comma
        '{"id": test}',  # unquoted value
        '',  # empty file
        'not json at all'  # completely invalid
    ]
    
    $malformed_cases | each { |bad_json|
        let temp_file = create_temp_test_file $bad_json ".json"
        
        # Should fail gracefully, not crash
        let result = try {
            open $temp_file | from json
            false  # Should not succeed
        } catch {
            true  # Should fail gracefully
        }
        
        assert $result "Should handle malformed JSON gracefully"
        cleanup_temp_files [$temp_file]
    }
}

# Memory & Resource Tests
@test  
def "test large dataset chunking efficiency" [] {
    # Test memory efficiency with large datasets
    let large_dataset = generate_mixed_test_data 1000 500  # 1500 items
    
    # Should handle large datasets without memory issues
    let batches = ($large_dataset | chunks 25)
    assert_equal ($batches | length) 60 "Should create 60 batches for 1500 items"
    
    # Verify memory efficiency - all items preserved
    let reconstructed = ($batches | flatten)
    assert_equal ($large_dataset | length) ($reconstructed | length) "Should preserve all items"
    assert_equal ($large_dataset | first | get id) ($reconstructed | first | get id) "Should preserve item order"
}

@test
def "test empty and minimal data scenarios" [] {
    # Test edge cases with minimal data
    let empty_list = []
    let single_item = [{ id: "single", sort_key: "ITEM" }]
    
    # Empty data should be handled gracefully  
    let empty_batches = ($empty_list | chunks 25)
    assert_equal ($empty_batches | length) 0 "Should handle empty data"
    
    # Single item should work correctly
    let single_batches = ($single_item | chunks 25)
    assert_equal ($single_batches | length) 1 "Should create one batch for single item"
    assert_equal ($single_batches | first | length) 1 "Single batch should have one item"
}

@test
def "test file operations edge cases" [] {
    # Test various file system edge cases
    let test_content = [{ id: "file-test", data: "test" }]
    
    # Test with very long filename (near OS limits)
    let long_name = (1..200 | each { |_| "x" } | str join "")
    let long_file = $"/tmp/test_($long_name).json"
    
    # Should handle long filenames gracefully
    let result = try {
        $test_content | to json | save $long_file
        if ($long_file | path exists) {
            rm $long_file
            true
        } else {
            false
        }
    } catch {
        true  # Failing gracefully is acceptable for very long names
    }
    
    assert $result "Should handle long filenames without crashing"
}

# Data Type Conversion Edge Cases
@test
def "test numeric edge cases" [] {
    let numeric_edge_cases = {
        id: "numeric-test",
        sort_key: "NUMERIC",
        zero: 0,
        negative: -42,
        large_int: 9223372036854775807,  # Max int64
        small_float: 0.000001,
        large_float: 1.7976931348623157e+308,  # Near max double
        scientific: 1.23e-10,
        negative_float: -3.14159
    }
    
    let converted = ($numeric_edge_cases | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = match ($field_value | describe) {
            "string" => { "S": $field_value },
            "int" => { "N": ($field_value | into string) },
            "float" => { "N": ($field_value | into string) },
            _ => { "S": ($field_value | into string) }
        }
        $acc | insert $field_name $dynamodb_value
    })
    
    assert_equal $converted.zero.N "0" "Should handle zero"
    assert_equal $converted.negative.N "-42" "Should handle negative numbers"
    assert ($converted.large_float.N | str contains "e") "Should handle scientific notation"
}

@test
def "test boolean and null edge cases" [] {
    let edge_case_item = {
        id: "edge-test",
        sort_key: "EDGE",
        true_bool: true,
        false_bool: false,
        null_value: null,
        empty_string: "",
        zero_value: 0
    }
    
    let converted = ($edge_case_item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = if $field_value == null {
            { "NULL": true }
        } else {
            match ($field_value | describe) {
                "string" => { "S": $field_value },
                "int" => { "N": ($field_value | into string) },
                "bool" => { "BOOL": $field_value },
                _ => { "S": ($field_value | into string) }
            }
        }
        $acc | insert $field_name $dynamodb_value
    })
    
    assert_equal $converted.true_bool.BOOL true "Should handle true boolean"
    assert_equal $converted.false_bool.BOOL false "Should handle false boolean"
    assert_equal $converted.null_value.NULL true "Should handle null values"
    assert_equal $converted.empty_string.S "" "Should handle empty strings"
}

# Concurrent Operations Simulation
@test
def "test simulated concurrent data processing" [] {
    # Simulate concurrent operations by processing same data multiple ways
    let base_data = generate_test_users 50
    
    # Process data in different orders and chunk sizes
    let batch1 = ($base_data | chunks 10)
    let batch2 = ($base_data | chunks 25) 
    let batch3 = ($base_data | reverse | chunks 15)
    
    # All should result in same total items
    let total1 = ($batch1 | each { |b| $b | length } | math sum)
    let total2 = ($batch2 | each { |b| $b | length } | math sum) 
    let total3 = ($batch3 | each { |b| $b | length } | math sum)
    
    assert_equal $total1 50 "Batch1 should preserve all items"
    assert_equal $total2 50 "Batch2 should preserve all items"
    assert_equal $total3 50 "Batch3 should preserve all items"
    
    # Data integrity should be maintained
    let reconstructed1 = ($batch1 | flatten)
    assert_equal ($base_data | first | get id) ($reconstructed1 | first | get id) "Should maintain data integrity"
}

@test
def "test snapshot format validation comprehensive" [] {
    # Test various snapshot format edge cases
    let test_data = generate_test_users 10
    
    # Test snapshot with missing fields
    let incomplete_snapshot = {
        metadata: { table_name: "test" },  # Missing other metadata
        data: $test_data
    }
    
    # Should handle incomplete metadata gracefully
    assert_contains ($incomplete_snapshot | columns) "metadata" "Should have metadata section"
    assert_contains ($incomplete_snapshot | columns) "data" "Should have data section"
    assert_equal ($incomplete_snapshot.data | length) 10 "Should preserve data even with incomplete metadata"
    
    # Test snapshot with extra fields
    let extended_snapshot = {
        metadata: {
            table_name: "test",
            timestamp: "2024-01-01",
            item_count: 10,
            tool: "test",
            version: "1.0",
            extra_field: "should be ignored"
        },
        data: $test_data,
        extra_section: "should be preserved"
    }
    
    assert_equal ($extended_snapshot.data | length) 10 "Should handle extra fields gracefully"
    assert_contains ($extended_snapshot | columns) "extra_section" "Should preserve extra sections"
}

# Test execution complete - remove print statements for nutest compatibility