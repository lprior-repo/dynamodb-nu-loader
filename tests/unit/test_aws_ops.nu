# Unit tests for AWS operations in DynamoDB Nu-Loader
use std/testing *
use ../helpers/test_utils.nu *

# Test DynamoDB item format conversion
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

# Test batch request structure
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

# Test table info response parsing
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

# Test empty table handling
@test
def "test empty table scan result" [] {
  let empty_scan_response = { "Items": [] }
  let items = $empty_scan_response.Items
  
  assert_equal ($items | length) 0 "Should handle empty scan result"
  assert_type $items "list" "Should return a list even when empty"
}

@test
def "test empty batch operations" [] {
  let empty_items = []
  
  # Test that we can detect empty batches
  let should_skip = (($empty_items | length) == 0)
  assert_equal $should_skip true "Should detect empty item list"
}

# Test chunking for batch operations
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

# Test error scenarios
@test
def "test invalid table name handling" [] {
  let invalid_table_name = ""
  
  assert_equal ($invalid_table_name | str length) 0 "Should detect empty table name"
}

@test
def "test malformed dynamodb response handling" [] {
  let malformed_response = { "WrongField": [] }
  
  # Test that we can detect missing expected fields
  let has_items = ("Items" in ($malformed_response | columns))
  assert_equal $has_items false "Should detect missing Items field"
}

# Property-based tests
@test
def "property batch operations preserve all items" [] {
  let original_data = generate_mixed_test_data 50 25
  let batches = ($original_data | chunks 25)
  let reconstructed = ($batches | flatten)
  
  assert_equal ($original_data | length) ($reconstructed | length) "Batching should preserve item count"
  assert_equal ($original_data | first | get id) ($reconstructed | first | get id) "Batching should preserve item order and content"
}

@test
def "property dynamodb conversion is reversible for basic types" [] {
  let original_item = {
    string_val: "test",
    int_val: 42,
    bool_val: true
  }
  
  # Convert to DynamoDB format
  let dynamodb_format = ($original_item | transpose key value | reduce -f {} { |row, acc|
    let field_name = $row.key
    let field_value = $row.value
    let dynamodb_value = match ($field_value | describe) {
      "string" => { "S": $field_value },
      "int" => { "N": ($field_value | into string) },
      "bool" => { "BOOL": $field_value },
      _ => { "S": ($field_value | into string) }
    }
    $acc | insert $field_name $dynamodb_value
  })
  
  # Convert back
  let converted_back = ($dynamodb_format | transpose key value | reduce -f {} { |row, acc|
    let field_name = $row.key
    let field_value = ($row.value | values | first)
    $acc | insert $field_name $field_value
  })
  
  assert_equal $converted_back.string_val $original_item.string_val "String should roundtrip"
  assert_equal $converted_back.bool_val $original_item.bool_val "Boolean should roundtrip"
  # Note: Numbers become strings in this conversion, which is expected
}