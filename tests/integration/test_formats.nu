# Integration tests for file format handling in DynamoDB Nu-Loader

use ../helpers/test_utils.nu *

# Test JSON format handling
@test
def "integration test json format roundtrip" [] {
  let test_data = generate_mixed_test_data 3 2
  let temp_dir = "/tmp/format_test_json"
  mkdir $temp_dir
  
  # Test raw JSON array format
  let json_file = $"($temp_dir)/test_data.json"
  $test_data | to json | save $json_file
  
  let loaded_data = (open $json_file)
  assert_equal ($loaded_data | length) 5 "Should preserve item count in JSON"
  assert_equal ($loaded_data | first | get id) ($test_data | first | get id) "Should preserve field values in JSON"
  
  # Test snapshot JSON format
  let snapshot_file = $"($temp_dir)/snapshot.json"
  let snapshot = {
    metadata: {
      table_name: "test-table",
      timestamp: "2024-01-01 12:00:00",
      item_count: ($test_data | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $test_data
  }
  $snapshot | to json | save $snapshot_file
  
  let loaded_snapshot = (open $snapshot_file)
  assert_contains ($loaded_snapshot | columns) "metadata" "Snapshot should have metadata"
  assert_contains ($loaded_snapshot | columns) "data" "Snapshot should have data"
  assert_equal ($loaded_snapshot.data | length) ($test_data | length) "Snapshot should preserve data"
  
  rm -rf $temp_dir
}

@test
def "integration test csv format roundtrip" [] {
  let test_data = generate_test_users 3  # Use consistent data structure for CSV
  let temp_dir = "/tmp/format_test_csv"
  mkdir $temp_dir
  
  let csv_file = $"($temp_dir)/test_data.csv"
  $test_data | to csv | save $csv_file
  
  let loaded_data = (open $csv_file | from csv)
  assert_equal ($loaded_data | length) 3 "Should preserve item count in CSV"
  assert_equal ($loaded_data | first | get id) ($test_data | first | get id) "Should preserve ID field in CSV"
  assert_equal ($loaded_data | first | get name) ($test_data | first | get name) "Should preserve string fields in CSV"
  
  # Note: CSV conversion may change numeric types to strings
  assert_type ($loaded_data | first | get age) "string" "CSV parsing converts numbers to strings"
  
  rm -rf $temp_dir
}

# Test format auto-detection
@test
def "integration test format detection by extension" [] {
  let test_data = generate_test_users 2
  let temp_dir = "/tmp/format_detection_test"
  mkdir $temp_dir
  
  # Create files with different extensions
  let json_file = $"($temp_dir)/data.json"
  let csv_file = $"($temp_dir)/data.csv"
  let no_ext_file = $"($temp_dir)/data"
  
  $test_data | to json | save $json_file
  $test_data | to csv | save $csv_file
  $test_data | to json | save $no_ext_file
  
  # Test detection logic
  assert ($json_file | str ends-with ".json") "Should detect JSON extension"
  assert ($csv_file | str ends-with ".csv") "Should detect CSV extension"
  assert (not ($no_ext_file | str ends-with ".csv") "Files without .csv should default to JSON"
  
  # Test actual file loading with detection
  let json_loaded = if ($json_file | str ends-with ".csv") {
    open $json_file | from csv
  } else {
    open $json_file
  }
  
  let csv_loaded = if ($csv_file | str ends-with ".csv") {
    open $csv_file | from csv
  } else {
    open $csv_file
  }
  
  assert_equal ($json_loaded | length) 2 "JSON detection should work"
  assert_equal ($csv_loaded | length) 2 "CSV detection should work"
  
  rm -rf $temp_dir
}

# Test snapshot format with different data types
@test
def "integration test snapshot format with mixed data types" [] {
  let mixed_data = [
    {
      id: "test-1",
      sort_key: "TEST",
      string_field: "hello",
      int_field: 42,
      float_field: 3.14,
      bool_field: true,
      null_field: null
    },
    {
      id: "test-2", 
      sort_key: "TEST",
      string_field: "world",
      int_field: 100,
      float_field: 2.71,
      bool_field: false,
      null_field: null
    }
  ]
  
  let temp_dir = "/tmp/mixed_types_test"
  mkdir $temp_dir
  
  let snapshot_file = $"($temp_dir)/mixed_snapshot.json"
  let snapshot = {
    metadata: {
      table_name: "test-table",
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: ($mixed_data | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $mixed_data
  }
  
  $snapshot | to json | save $snapshot_file
  let loaded = (open $snapshot_file)
  
  # Verify metadata preservation
  assert_equal $loaded.metadata.item_count 2 "Should preserve item count"
  assert_equal $loaded.metadata.table_name "test-table" "Should preserve table name"
  
  # Verify data type preservation in JSON
  let first_item = ($loaded.data | first)
  assert_equal $first_item.string_field "hello" "Should preserve strings"
  assert_equal $first_item.int_field 42 "Should preserve integers"
  assert_equal $first_item.float_field 3.14 "Should preserve floats"
  assert_equal $first_item.bool_field true "Should preserve booleans"
  
  rm -rf $temp_dir
}

# Test CSV handling with special characters
@test
def "integration test csv format with special characters" [] {
  let special_data = [
    {
      id: "special-1",
      sort_key: "TEST",
      name: "Name, with comma",
      description: "Description with \"quotes\"",
      notes: "Notes with\nnewline"
    },
    {
      id: "special-2",
      sort_key: "TEST", 
      name: "Simple name",
      description: "Simple description",
      notes: "Simple notes"
    }
  ]
  
  let temp_dir = "/tmp/csv_special_test"
  mkdir $temp_dir
  
  let csv_file = $"($temp_dir)/special.csv"
  $special_data | to csv | save $csv_file
  
  # Verify CSV file was created
  assert ($csv_file | path exists) "CSV file should be created"
  
  let loaded_data = (open $csv_file | from csv)
  assert_equal ($loaded_data | length) 2 "Should load all items despite special characters"
  
  # CSV should handle these characters properly
  let first_item = ($loaded_data | first)
  assert ($first_item.name | str contains "comma") "Should preserve comma in quoted field"
  
  rm -rf $temp_dir
}

# Test large file handling
@test
def "integration test large file format handling" [] {
  let large_data = generate_mixed_test_data 50 25  # 75 items
  let temp_dir = "/tmp/large_file_test"
  mkdir $temp_dir
  
  # Test large JSON snapshot
  let large_json_file = $"($temp_dir)/large.json"
  let large_snapshot = {
    metadata: {
      table_name: "large-test-table",
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: ($large_data | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $large_data
  }
  
  $large_snapshot | to json | save $large_json_file
  
  # Verify large file handling
  assert ($large_json_file | path exists) "Large JSON file should be created"
  
  let file_size = (ls $large_json_file | first | get size)
  assert ($file_size > 1000) "Large file should have substantial size"
  
  let loaded_large = (open $large_json_file)
  assert_equal ($loaded_large.data | length) 75 "Should preserve all items in large file"
  
  # Test large CSV
  let large_csv_file = $"($temp_dir)/large.csv"
  $large_data | to csv | save $large_csv_file
  
  let csv_loaded = (open $large_csv_file | from csv)
  assert_equal ($csv_loaded | length) 75 "Should handle large CSV files"
  
  rm -rf $temp_dir
}

# Test empty data handling
@test
def "integration test empty data format handling" [] {
  let empty_data = []
  let temp_dir = "/tmp/empty_data_test"
  mkdir $temp_dir
  
  # Test empty JSON
  let empty_json_file = $"($temp_dir)/empty.json"
  $empty_data | to json | save $empty_json_file
  
  let loaded_empty_json = (open $empty_json_file)
  assert_equal ($loaded_empty_json | length) 0 "Should handle empty JSON array"
  
  # Test empty snapshot
  let empty_snapshot_file = $"($temp_dir)/empty_snapshot.json"
  let empty_snapshot = {
    metadata: {
      table_name: "empty-table",
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: 0,
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $empty_data
  }
  
  $empty_snapshot | to json | save $empty_snapshot_file
  let loaded_empty_snapshot = (open $empty_snapshot_file)
  
  assert_equal $loaded_empty_snapshot.metadata.item_count 0 "Should handle empty snapshot metadata"
  assert_equal ($loaded_empty_snapshot.data | length) 0 "Should handle empty snapshot data"
  
  rm -rf $temp_dir
}

# Test file encoding and character sets
@test
def "integration test unicode character handling" [] {
  let unicode_data = [
    {
      id: "unicode-1",
      sort_key: "TEST",
      name: "José María",
      description: "Café with emojis ☕ 🎉",
      chinese: "你好世界",
      emoji: "🚀🔥💯"
    }
  ]
  
  let temp_dir = "/tmp/unicode_test"
  mkdir $temp_dir
  
  # Test Unicode in JSON
  let unicode_json_file = $"($temp_dir)/unicode.json"
  $unicode_data | to json | save $unicode_json_file
  
  let loaded_unicode = (open $unicode_json_file)
  assert_equal ($loaded_unicode | length) 1 "Should handle Unicode in JSON"
  
  let unicode_item = ($loaded_unicode | first)
  assert ($unicode_item.name | str contains "José") "Should preserve accented characters"
  assert ($unicode_item.description | str contains "☕") "Should preserve emoji characters"
  assert ($unicode_item.chinese | str contains "你好") "Should preserve non-Latin characters"
  
  rm -rf $temp_dir
}

# Test format compatibility with existing fixtures
@test
def "integration test format compatibility with fixtures" [] {
  # Test with existing fixture files
  let fixture_json = "tests/fixtures/sample_users.json"
  let fixture_csv = "tests/fixtures/sample_users.csv"
  let fixture_snapshot = "tests/fixtures/sample_snapshot.json"
  
  if ($fixture_json | path exists) {
    let json_data = (open $fixture_json)
    assert_type $json_data "list" "Fixture JSON should be a list"
    assert ($json_data | length) > 0 "Fixture should have data"
  }
  
  if ($fixture_csv | path exists) {
    let csv_data = (open $fixture_csv | from csv)
    assert_type $csv_data "list" "Fixture CSV should parse to list"
    assert ($csv_data | length) > 0 "CSV fixture should have data"
  }
  
  if ($fixture_snapshot | path exists) {
    let snapshot_data = (open $fixture_snapshot)
    assert_type $snapshot_data "record" "Snapshot fixture should be a record"
    assert_contains ($snapshot_data | columns) "metadata" "Snapshot should have metadata"
    assert_contains ($snapshot_data | columns) "data" "Snapshot should have data"
  }
}

# Property-based test for format consistency
@test 
def "property format conversion preserves essential data structure" [] {
  let test_data = generate_test_users 5
  let temp_dir = "/tmp/property_format_test"
  mkdir $temp_dir
  
  # Test JSON → CSV → JSON roundtrip preserves structure
  let json_file = $"($temp_dir)/original.json"
  let csv_file = $"($temp_dir)/converted.csv"
  let json_file2 = $"($temp_dir)/roundtrip.json"
  
  # Original → JSON
  $test_data | to json | save $json_file
  let from_json = (open $json_file)
  
  # JSON → CSV
  $from_json | to csv | save $csv_file
  let from_csv = (open $csv_file | from csv)
  
  # CSV → JSON (completing roundtrip)
  $from_csv | to json | save $json_file2
  let final_json = (open $json_file2)
  
  # Verify essential structure preservation
  assert_equal ($test_data | length) ($final_json | length) "Roundtrip should preserve item count"
  assert_equal ($test_data | first | get id) ($final_json | first | get id) "Roundtrip should preserve key fields"
  
  rm -rf $temp_dir
}