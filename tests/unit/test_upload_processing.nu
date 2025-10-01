# Unit tests for upload processing logic in DynamoDB Nu-Loader

use ../helpers/test_utils.nu *

# Test the detect_and_process function directly
#[test]
def "unit test detect_and_process with json raw array" [] {
  let test_data = [
    { id: "test-1", sort_key: "USER", name: "Test User 1" },
    { id: "test-2", sort_key: "USER", name: "Test User 2" }
  ]
  
  let temp_file = create_temp_test_file ($test_data | to json) ".json"
  
  # Simulate detect_and_process logic
  let loaded_data = if ($temp_file | str ends-with ".csv") {
    open $temp_file
  } else {
    let data = open $temp_file
    if ($data | columns | "data" in $in) {
      $data.data
    } else {
      $data
    }
  }
  
  assert_equal ($loaded_data | length) 2 "Should load 2 items from JSON array"
  assert_equal ($loaded_data | first | get name) "Test User 1" "Should preserve field values"
  assert_type ($loaded_data | first | get id) "string" "Should preserve string types"
  
  cleanup_temp_files [$temp_file]
}

#[test]
def "unit test detect_and_process with json snapshot format" [] {
  let snapshot_data = {
    metadata: {
      table_name: "test-table",
      timestamp: "2024-01-01 12:00:00",
      item_count: 2,
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: [
      { id: "snap-1", sort_key: "USER", name: "Snapshot User 1" },
      { id: "snap-2", sort_key: "USER", name: "Snapshot User 2" }
    ]
  }
  
  let temp_file = create_temp_test_file ($snapshot_data | to json) ".json"
  
  # Simulate detect_and_process logic for snapshot format
  let loaded_data = if ($temp_file | str ends-with ".csv") {
    open $temp_file
  } else {
    let data = open $temp_file
    if ($data | columns | "data" in $in) {
      $data.data
    } else {
      $data
    }
  }
  
  assert_equal ($loaded_data | length) 2 "Should extract data from snapshot format"
  assert_equal ($loaded_data | first | get name) "Snapshot User 1" "Should preserve field values"
  
  cleanup_temp_files [$temp_file]
}

#[test]
def "unit test detect_and_process with csv format" [] {
  let csv_content = "id,sort_key,name\ncsv-1,USER,CSV User 1\ncsv-2,USER,CSV User 2"
  let temp_file = create_temp_test_file $csv_content ".csv"
  
  # Simulate detect_and_process logic for CSV
  let loaded_data = if ($temp_file | str ends-with ".csv") {
    open $temp_file  # Nushell auto-detects CSV
  } else {
    open $temp_file
  }
  
  assert_equal ($loaded_data | length) 2 "Should load 2 rows from CSV"
  assert_equal ($loaded_data | first | get name) "CSV User 1" "Should preserve CSV field values"
  assert_type ($loaded_data | first | get id) "string" "CSV should parse all fields as strings"
  
  cleanup_temp_files [$temp_file]
}

# Test DynamoDB batch write item conversion
#[test]
def "unit test batch write item conversion for mixed types" [] {
  let mixed_items = [
    {
      id: "mixed-1",
      sort_key: "USER",
      name: "Alice",
      age: 30,
      active: true,
      score: 95.5,
      tags: ["premium", "verified"]
    },
    {
      id: "mixed-2",
      sort_key: "PRODUCT",
      name: "Laptop",
      price: 999.99,
      in_stock: false,
      rating: null
    }
  ]
  
  # Simulate the batch write conversion logic
  let dynamodb_items = ($mixed_items | each { |item|
    let converted_item = ($item | transpose key value | reduce -f {} { |row, acc|
      let field_name = $row.key
      let field_value = $row.value
      let dynamodb_value = if ($field_value == null) {
        { "NULL": true }
      } else {
        match ($field_value | describe) {
          "string" => { "S": $field_value },
          "int" => { "N": ($field_value | into string) },
          "float" => { "N": ($field_value | into string) },
          "bool" => { "BOOL": $field_value },
          _ => { "S": ($field_value | into string) }
        }
      }
      $acc | insert $field_name $dynamodb_value
    })
    { "PutRequest": { "Item": $converted_item } }
  })
  
  assert_equal ($dynamodb_items | length) 2 "Should convert all items"
  
  let first_item = ($dynamodb_items | first | get PutRequest.Item)
  assert_equal $first_item.id.S "mixed-1" "Should convert string ID"
  assert_equal $first_item.age.N "30" "Should convert int to string for DynamoDB"
  assert_equal $first_item.active.BOOL true "Should preserve boolean type"
  assert_equal $first_item.score.N "95.5" "Should convert float to string"
  
  let second_item = ($dynamodb_items | get 1 | get PutRequest.Item)
  assert_equal $second_item.price.N "999.99" "Should handle product price conversion"
  assert_equal $second_item.in_stock.BOOL false "Should handle boolean false"
}

# Test CSV data type handling
#[test]
def "unit test csv data type preservation awareness" [] {
  let original_data = [
    {
      id: "type-1",
      sort_key: "TEST",
      string_field: "hello",
      int_field: 42,
      float_field: 3.14,
      bool_field: true
    }
  ]
  
  # Convert to CSV and back (simulating file round-trip)
  let csv_content = ($original_data | to csv)
  let parsed_csv = ($csv_content | from csv)
  
  # CSV parsing in modern Nushell preserves numeric types
  let parsed_item = ($parsed_csv | first)
  assert_type $parsed_item.string_field "string" "String should remain string in CSV"
  assert_type $parsed_item.int_field "int" "Int should be preserved as int in CSV"
  assert_type $parsed_item.float_field "float" "Float should be preserved as float in CSV"
  assert_type $parsed_item.bool_field "string" "Bool becomes string in CSV"
  
  # Values should be preserved with correct types
  assert_equal $parsed_item.int_field 42 "Int value should be preserved"
  assert_equal $parsed_item.float_field 3.14 "Float value should be preserved"
  assert_equal $parsed_item.bool_field "true" "Bool value should be preserved as string"
}

# Test file extension detection logic
#[test]
def "unit test file extension detection" [] {
  let test_files = [
    "data.json",
    "backup.csv",
    "snapshot.JSON",  # uppercase
    "export.CSV",     # uppercase
    "noextension",
    "file.with.dots.json",
    "file.with.dots.csv"
  ]
  
  let detection_results = ($test_files | each { |file|
    {
      file: $file,
      is_csv: (($file | str ends-with ".csv") or ($file | str ends-with ".CSV")),
      is_json: (($file | str ends-with ".json") or ($file | str ends-with ".JSON"))
    }
  })
  
  # Verify detection logic
  let csv_files = ($detection_results | where is_csv)
  let json_files = ($detection_results | where is_json)
  let no_ext_files = ($detection_results | where { |row| (not $row.is_csv) and (not $row.is_json) })
  
  assert_equal ($csv_files | length) 3 "Should detect 3 CSV files"
  assert_equal ($json_files | length) 3 "Should detect 3 JSON files"  
  assert_equal ($no_ext_files | length) 1 "Should handle 1 file without clear extension"
  
  # Verify specific detections
  assert ($detection_results | where file == "data.json" | first | get is_json) "Should detect .json"
  assert ($detection_results | where file == "backup.csv" | first | get is_csv) "Should detect .csv"
  assert (not ($detection_results | where file == "noextension" | first | get is_csv)) "Should not detect CSV for no extension"
}

# Test load_and_restore function components
#[test]
def "unit test load_and_restore file validation" [] {
  let existing_file = create_temp_test_file "test data" ".json"
  let nonexistent_file = "/tmp/does_not_exist.json"
  
  # Test file existence check
  let existing_check = ($existing_file | path exists)
  let nonexistent_check = ($nonexistent_file | path exists)
  
  assert_equal $existing_check true "Should detect existing file"
  assert_equal $nonexistent_check false "Should detect non-existing file"
  
  # Test error condition for missing file
  assert_error {
    if not ($nonexistent_file | path exists) {
      error make { msg: $"File not found: ($nonexistent_file)" }
    }
  } "Should create error for missing file"
  
  cleanup_temp_files [$existing_file]
}

# Test batch size validation
#[test]
def "unit test batch size compliance" [] {
  let large_dataset = generate_test_users 100
  let batches = ($large_dataset | chunks 25)
  
  # DynamoDB batch operations are limited to 25 items
  assert_equal ($batches | length) 4 "Should create correct number of batches"
  
  # Verify no batch exceeds the limit
  $batches | each { |batch|
    assert (($batch | length) <= 25) "Each batch should not exceed 25 items"
  }
  
  # Verify first batches are exactly 25 items
  assert_equal ($batches | first | length) 25 "First batch should be exactly 25 items"
  assert_equal ($batches | get 1 | length) 25 "Second batch should be exactly 25 items"
  assert_equal ($batches | get 2 | length) 25 "Third batch should be exactly 25 items"
  assert_equal ($batches | get 3 | length) 25 "Fourth batch should be exactly 25 items"
}

# Test upload data validation
#[test]
def "unit test upload data structure validation" [] {
  let valid_items = [
    { id: "valid-1", sort_key: "USER", name: "Valid User" },
    { id: "valid-2", sort_key: "PRODUCT", name: "Valid Product" }
  ]
  
  let invalid_items = [
    { sort_key: "USER", name: "Missing ID" },  # Missing id
    { id: "invalid-2", name: "Missing Sort Key" }  # Missing sort_key
  ]
  
  # Test validation logic for required fields
  let valid_check = ($valid_items | all { |item|
    ("id" in ($item | columns)) and ("sort_key" in ($item | columns))
  })
  
  let invalid_check = ($invalid_items | all { |item|
    ("id" in ($item | columns)) and ("sort_key" in ($item | columns))
  })
  
  assert_equal $valid_check true "Valid items should pass validation"
  assert_equal $invalid_check false "Invalid items should fail validation"
}

# Test empty dataset handling
#[test]
def "unit test empty dataset upload handling" [] {
  let empty_items = []
  
  # Test batch processing with empty dataset
  let empty_batches = ($empty_items | chunks 25)
  assert_equal ($empty_batches | length) 0 "Empty dataset should create no batches"
  
  # Test empty detection logic
  let should_skip = (($empty_items | length) == 0)
  assert_equal $should_skip true "Should detect empty dataset for skipping"
}

# Property-based test for upload processing
#[test]
def "property upload processing preserves item count" [] {
  let test_sizes = [1, 5, 25, 26, 50, 100]
  
  $test_sizes | each { |size|
    let items = generate_test_users $size
    let batches = ($items | chunks 25)
    let total_in_batches = ($batches | each { |batch| $batch | length } | math sum)
    
    assert_equal $total_in_batches $size $"Batching should preserve count for ($size) items"
  }
}

#[test]
def "property upload type conversion is consistent" [] {
  let test_data = [
    { id: "prop-1", sort_key: "TEST", value: "string" },
    { id: "prop-2", sort_key: "TEST", value: 42 },
    { id: "prop-3", sort_key: "TEST", value: true }
  ]
  
  # Test that conversion logic is deterministic
  let conversion1 = ($test_data | each { |item|
    $item | transpose key value | reduce -f {} { |row, acc|
      let field_name = $row.key
      let field_value = $row.value
      let dynamodb_value = match ($field_value | describe) {
        "string" => { "S": $field_value },
        "int" => { "N": ($field_value | into string) },
        "bool" => { "BOOL": $field_value },
        _ => { "S": ($field_value | into string) }
      }
      $acc | insert $field_name $dynamodb_value
    }
  })
  
  let conversion2 = ($test_data | each { |item|
    $item | transpose key value | reduce -f {} { |row, acc|
      let field_name = $row.key
      let field_value = $row.value
      let dynamodb_value = match ($field_value | describe) {
        "string" => { "S": $field_value },
        "int" => { "N": ($field_value | into string) },
        "bool" => { "BOOL": $field_value },
        _ => { "S": ($field_value | into string) }
      }
      $acc | insert $field_name $dynamodb_value
    }
  })
  
  assert_equal $conversion1 $conversion2 "Type conversion should be deterministic"
}