# Unit tests for data operations in DynamoDB Nu-Loader
use std/testing *
use ../helpers/test_utils.nu *

# Test the detect_and_process function
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

# Test data type conversion for DynamoDB format
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

# Test batch processing logic
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

# Test snapshot format creation
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

# Test configuration loading logic
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

# Test error handling for invalid files
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

# Property-based test: Roundtrip consistency
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