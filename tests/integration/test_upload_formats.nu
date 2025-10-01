# Comprehensive tests for CSV and JSON upload/restore functionality in DynamoDB Nu-Loader

use ../helpers/test_utils.nu *

# Setup for upload tests
def setup_upload_test []: nothing -> record {
  {
    table_name: "test-table-upload",
    temp_dir: "/tmp/upload_format_tests",
    mixed_data: (generate_mixed_test_data 4 3),  # 4 users + 3 products
    user_data: (generate_test_users 5),
    product_data: (generate_test_products 4)
  }
}

def cleanup_upload_test [context: record]: nothing -> nothing {
  if ($context.temp_dir | path exists) {
    rm -rf $context.temp_dir
  }
}

# Test JSON upload scenarios
#[test]
def "upload test json raw array format" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create raw JSON array file
  let json_file = $"($context.temp_dir)/raw_data.json"
  $context.user_data | to json | save $json_file
  
  # Test the detect_and_process function logic
  let loaded_data = if ($json_file | str ends-with ".csv") {
    open $json_file
  } else {
    let data = open $json_file
    if ($data | columns | "data" in $in) {
      $data.data
    } else {
      $data
    }
  }
  
  assert_equal ($loaded_data | length) 5 "Should load all items from raw JSON"
  assert_equal ($loaded_data | first | get sort_key) "USER" "Should preserve USER sort_key"
  assert_type ($loaded_data | first | get age) "int" "Should preserve integer types in JSON"
  
  # Verify all required fields are present
  $loaded_data | each { |item|
    assert_contains ($item | columns) "id" "Each item should have id"
    assert_contains ($item | columns) "sort_key" "Each item should have sort_key"
    assert_contains ($item | columns) "name" "Each item should have name"
  }
  
  cleanup_upload_test $context
}

#[test]
def "upload test json snapshot format" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create snapshot format JSON file
  let snapshot_file = $"($context.temp_dir)/snapshot_upload.json"
  let snapshot = {
    metadata: {
      table_name: $context.table_name,
      timestamp: "2024-01-01 12:00:00",
      item_count: ($context.mixed_data | length),
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $context.mixed_data
  }
  $snapshot | to json | save $snapshot_file
  
  # Test snapshot processing
  let loaded_data = if ($snapshot_file | str ends-with ".csv") {
    open $snapshot_file
  } else {
    let data = open $snapshot_file
    if ($data | columns | "data" in $in) {
      $data.data
    } else {
      $data
    }
  }
  
  assert_equal ($loaded_data | length) 7 "Should extract data from snapshot format"
  
  # Verify mixed data types (users and products)
  let users = ($loaded_data | where sort_key == "USER")
  let products = ($loaded_data | where sort_key == "PRODUCT")
  
  assert_equal ($users | length) 4 "Should have 4 users"
  assert_equal ($products | length) 3 "Should have 3 products"
  
  # Verify user-specific fields
  assert_contains ($users | first | columns) "email" "Users should have email"
  assert_contains ($users | first | columns) "age" "Users should have age"
  
  # Verify product-specific fields
  assert_contains ($products | first | columns) "price" "Products should have price"
  assert_contains ($products | first | columns) "category" "Products should have category"
  
  cleanup_upload_test $context
}

# Test CSV upload scenarios
#[test]
def "upload test csv format with all data types" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create CSV with mixed data types
  let csv_file = $"($context.temp_dir)/mixed_data.csv"
  $context.mixed_data | to csv | save $csv_file
  
  # Test CSV processing
  let loaded_data = if ($csv_file | str ends-with ".csv") {
    open $csv_file
  } else {
    open $csv_file
  }
  
  assert_equal ($loaded_data | length) 7 "Should load all CSV rows"
  
  # CSV parsing converts all values to strings, verify this behavior
  assert_type ($loaded_data | first | get id) "string" "CSV should parse IDs as strings"
  
  # Verify data structure preservation despite type conversion
  let csv_users = ($loaded_data | where sort_key == "USER")
  let csv_products = ($loaded_data | where sort_key == "PRODUCT")
  
  assert ($csv_users | length) > 0 "Should have user records in CSV"
  assert ($csv_products | length) > 0 "Should have product records in CSV"
  
  cleanup_upload_test $context
}

#[test]
def "upload test csv format with special characters" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create CSV with special characters and edge cases
  let special_data = [
    {
      id: "special-1",
      sort_key: "TEST",
      name: "Name with, comma",
      description: "Text with \"quotes\" and newlines",
      notes: "Multi\nline\ntext",
      special_chars: "émojis 🚀 and àccénts"
    },
    {
      id: "special-2",
      sort_key: "TEST",
      name: "Simple Name",
      description: "Simple description",
      notes: "Simple notes",
      special_chars: "Normal text"
    }
  ]
  
  let csv_file = $"($context.temp_dir)/special_chars.csv"
  $special_data | to csv | save $csv_file
  
  let loaded_data = open $csv_file
  
  assert_equal ($loaded_data | length) 2 "Should handle special characters in CSV"
  assert ($loaded_data | first | get name | str contains "comma") "Should preserve comma in CSV field"
  
  cleanup_upload_test $context
}

#[test]
def "upload test csv format empty and null handling" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create CSV with empty values and null equivalents
  let data_with_empties = [
    {
      id: "empty-1",
      sort_key: "TEST",
      name: "Full Record",
      optional_field: "Has Value",
      empty_field: "",
      null_field: null
    },
    {
      id: "empty-2", 
      sort_key: "TEST",
      name: "Partial Record",
      optional_field: "",
      empty_field: null,
      null_field: ""
    }
  ]
  
  let csv_file = $"($context.temp_dir)/empty_values.csv"
  $data_with_empties | to csv | save $csv_file
  
  let loaded_data = open $csv_file
  
  assert_equal ($loaded_data | length) 2 "Should handle empty/null values in CSV"
  assert_equal ($loaded_data | first | get name) "Full Record" "Should preserve non-empty values"
  
  cleanup_upload_test $context
}

# Test format detection and processing
#[test]
def "upload test format auto detection" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create identical data in different formats
  let test_data = (generate_test_users 3)
  
  let json_file = $"($context.temp_dir)/auto_detect.json"
  let csv_file = $"($context.temp_dir)/auto_detect.csv"
  let no_ext_file = $"($context.temp_dir)/auto_detect"
  
  $test_data | to json | save $json_file
  $test_data | to csv | save $csv_file
  $test_data | to json | save $no_ext_file
  
  # Test auto-detection logic
  let json_detected = ($json_file | str ends-with ".csv")
  let csv_detected = ($csv_file | str ends-with ".csv")
  let no_ext_detected = ($no_ext_file | str ends-with ".csv")
  
  assert_equal $json_detected false "Should detect .json files correctly"
  assert_equal $csv_detected true "Should detect .csv files correctly"
  assert_equal $no_ext_detected false "Should default non-.csv files to JSON"
  
  # Test actual loading with detection
  let json_data = if ($json_file | str ends-with ".csv") { open $json_file } else { open $json_file }
  let csv_data = if ($csv_file | str ends-with ".csv") { open $csv_file } else { open $csv_file }
  
  assert_equal ($json_data | length) 3 "Should load JSON data correctly"
  assert_equal ($csv_data | length) 3 "Should load CSV data correctly"
  
  cleanup_upload_test $context
}

# Test large dataset uploads
#[test]
def "upload test large dataset performance" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create large dataset
  let large_dataset = generate_mixed_test_data 50 30  # 80 items total
  
  # Test JSON upload
  let large_json_file = $"($context.temp_dir)/large_dataset.json"
  $large_dataset | to json | save $large_json_file
  
  let loaded_json = open $large_json_file
  assert_equal ($loaded_json | length) 80 "Should handle large JSON datasets"
  
  # Test CSV upload
  let large_csv_file = $"($context.temp_dir)/large_dataset.csv"
  $large_dataset | to csv | save $large_csv_file
  
  let loaded_csv = open $large_csv_file
  assert_equal ($loaded_csv | length) 80 "Should handle large CSV datasets"
  
  # Test batch processing logic for large datasets
  let batches = ($large_dataset | chunks 25)
  assert_equal ($batches | length) 4 "Should create correct number of batches for large dataset"
  
  # Verify all items preserved across batches
  let total_items = ($batches | each { |batch| $batch | length } | math sum)
  assert_equal $total_items 80 "Should preserve all items in batches"
  
  cleanup_upload_test $context
}

# Test error scenarios in uploads
#[test]
def "upload test malformed json handling" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  # Create malformed JSON file
  let bad_json_file = $"($context.temp_dir)/malformed.json"
  '{"invalid": json, "missing": quotes}' | save $bad_json_file
  
  # Test error handling
  assert_error {
    open $bad_json_file
  } "Should handle malformed JSON gracefully"
  
  cleanup_upload_test $context
}

#[test]
def "upload test missing file handling" [] {
  let nonexistent_file = "/tmp/does_not_exist.json"
  
  assert_error {
    if not ($nonexistent_file | path exists) {
      error make { msg: $"File not found: ($nonexistent_file)" }
    }
    open $nonexistent_file
  } "Should handle missing files gracefully"
}

# Test data integrity during upload
#[test]
def "upload test data integrity preservation" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  let original_data = [
    {
      id: "integrity-1",
      sort_key: "TEST",
      string_val: "test string",
      int_val: 42,
      float_val: 3.14159,
      bool_val: true,
      array_val: ["a", "b", "c"],
      nested_val: { key: "value", num: 123 }
    }
  ]
  
  # Test JSON integrity
  let json_file = $"($context.temp_dir)/integrity_test.json"
  $original_data | to json | save $json_file
  let json_loaded = open $json_file
  
  assert_equal ($json_loaded | first | get string_val) "test string" "Should preserve strings in JSON"
  assert_equal ($json_loaded | first | get int_val) 42 "Should preserve integers in JSON"
  assert_equal ($json_loaded | first | get bool_val) true "Should preserve booleans in JSON"
  
  # Test CSV type conversion awareness
  let csv_file = $"($context.temp_dir)/integrity_test.csv"
  $original_data | to csv | save $csv_file
  let csv_loaded = open $csv_file
  
  # CSV converts all to strings, verify this is handled
  assert_type ($csv_loaded | first | get string_val) "string" "CSV should keep strings as strings"
  assert_type ($csv_loaded | first | get int_val) "string" "CSV should convert integers to strings"
  assert_type ($csv_loaded | first | get bool_val) "string" "CSV should convert booleans to strings"
  
  cleanup_upload_test $context
}

# Property-based test for upload consistency
#[test]
def "property upload formats preserve essential structure" [] {
  let context = setup_upload_test
  mkdir $context.temp_dir
  
  let test_data = generate_test_users 10
  
  # Test that both formats preserve the essential structure
  let json_file = $"($context.temp_dir)/property_test.json"
  let csv_file = $"($context.temp_dir)/property_test.csv"
  
  $test_data | to json | save $json_file
  $test_data | to csv | save $csv_file
  
  let json_loaded = open $json_file
  let csv_loaded = open $csv_file
  
  # Both should have same number of records
  assert_equal ($json_loaded | length) ($csv_loaded | length) "JSON and CSV should have same record count"
  
  # Both should have same IDs (essential for DynamoDB)
  let json_ids = ($json_loaded | get id | sort)
  let csv_ids = ($csv_loaded | get id | sort)
  assert_equal $json_ids $csv_ids "JSON and CSV should preserve same IDs"
  
  # Both should have same sort_key values
  let json_sort_keys = ($json_loaded | get sort_key | sort)
  let csv_sort_keys = ($csv_loaded | get sort_key | sort)
  assert_equal $json_sort_keys $csv_sort_keys "JSON and CSV should preserve same sort_keys"
  
  cleanup_upload_test $context
}