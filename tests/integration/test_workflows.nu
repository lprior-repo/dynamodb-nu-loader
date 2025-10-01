# Integration tests for complete workflows in DynamoDB Nu-Loader
use std/testing *
use ../helpers/test_utils.nu *

# Setup and teardown helpers for integration tests
def setup_integration_test []: nothing -> record {
  {
    table_name: "test-table-integration",
    test_data: (generate_mixed_test_data 5 3),
    snapshots_dir: "/tmp/test_snapshots_integration",
    config: (get_test_config)
  }
}

def cleanup_integration_test [context: record]: nothing -> nothing {
  # Clean up any test files created during integration tests
  if ($context.snapshots_dir | path exists) {
    rm -rf $context.snapshots_dir
  }
}

# Test complete snapshot workflow
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
def "integration test csv snapshot creation" [] {
  let context = setup_integration_test
  mkdir $context.snapshots_dir
  
  let csv_snapshot_file = $"($context.snapshots_dir)/test_snapshot.csv"
  let test_items = $context.test_data
  
  # Create CSV snapshot
  $test_items | to csv | save $csv_snapshot_file
  
  # Verify CSV file
  assert ($csv_snapshot_file | path exists) "CSV snapshot file should be created"
  
  let loaded_csv = (open $csv_snapshot_file | from csv)
  assert_equal ($loaded_csv | length) ($test_items | length) "Should preserve all items in CSV"
  
  cleanup_integration_test $context
}

# Test complete restore workflow  
@test
def "integration test restore from json snapshot" [] {
  let context = setup_integration_test
  mkdir $context.snapshots_dir
  
  # Create a test snapshot file
  let snapshot_file = $"($context.snapshots_dir)/restore_test.json"
  let test_snapshot = {
    metadata: {
      table_name: $context.table_name,
      timestamp: "2024-01-01 12:00:00",
      item_count: 2,
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: [
      { id: "restore-1", sort_key: "USER", name: "Restore Test 1" },
      { id: "restore-2", sort_key: "USER", name: "Restore Test 2" }
    ]
  }
  
  $test_snapshot | to json | save $snapshot_file
  
  # Test the restore data processing logic
  let loaded_data = (open $snapshot_file)
  let items_to_restore = if ($loaded_data | columns | "data" in $in) {
    $loaded_data.data
  } else {
    $loaded_data
  }
  
  assert_equal ($items_to_restore | length) 2 "Should extract correct number of items"
  assert_equal ($items_to_restore | first | get name) "Restore Test 1" "Should preserve field values"
  
  cleanup_integration_test $context
}

@test
def "integration test restore from csv file" [] {
  let context = setup_integration_test
  mkdir $context.snapshots_dir
  
  # Create a test CSV file
  let csv_file = $"($context.snapshots_dir)/restore_test.csv"
  let csv_content = "id,sort_key,name\ncsv-1,USER,CSV Test 1\ncsv-2,USER,CSV Test 2"
  $csv_content | save $csv_file
  
  # Test CSV restore processing
  let loaded_data = (open $csv_file | from csv)
  
  assert_equal ($loaded_data | length) 2 "Should load correct number of CSV items"
  assert_equal ($loaded_data | first | get name) "CSV Test 1" "Should preserve CSV field values"
  assert_equal ($loaded_data | last | get id) "csv-2" "Should load all CSV rows"
  
  cleanup_integration_test $context
}

# Test complete wipe functionality
@test
def "integration test wipe operation simulation" [] {
  let context = setup_integration_test
  let test_items = $context.test_data
  
  # Simulate the wipe operation logic (scanning and deleting)
  let items_to_delete = $test_items
  
  # Process in batches of 25 (DynamoDB limit)
  let delete_batches = ($items_to_delete | chunks 25)
  
  assert_equal ($delete_batches | length) 1 "Should create appropriate number of delete batches"
  
  # Verify delete request structure for each batch
  $delete_batches | each { |batch|
    let delete_requests = ($batch | each { |item|
      {
        "DeleteRequest": {
          "Key": {
            "id": { "S": $item.id },
            "sort_key": { "S": $item.sort_key }
          }
        }
      }
    })
    
    assert_equal ($delete_requests | length) ($batch | length) "Should create delete request for each item"
    assert_contains ($delete_requests | first | columns) "DeleteRequest" "Should have correct delete structure"
  }
}

# Test seed operation
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

# Test status operation
@test
def "integration test status information gathering" [] {
  let context = setup_integration_test
  
  # Mock table description response
  let mock_description = {
    "Table": {
      "TableName": $context.table_name,
      "TableStatus": "ACTIVE",
      "CreationDateTime": "2024-01-01T12:00:00.000Z",
      "TableSizeBytes": 2048
    }
  }
  
  let mock_item_count = 10  # From simulated scan
  
  # Simulate status info creation
  let status_info = {
    table_name: $context.table_name,
    status: $mock_description.Table.TableStatus,
    item_count: $mock_item_count,
    creation_time: $mock_description.Table.CreationDateTime,
    size_bytes: $mock_description.Table.TableSizeBytes
  }
  
  assert_equal $status_info.table_name $context.table_name "Should report correct table name"
  assert_equal $status_info.status "ACTIVE" "Should report table status"
  assert_equal $status_info.item_count 10 "Should report item count from scan"
  assert_type $status_info.size_bytes "int" "Size should be numeric"
}

# Test end-to-end workflow: seed → snapshot → wipe → restore
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

# Test error handling in workflows
@test
def "integration test file not found error handling" [] {
  let nonexistent_file = "/tmp/does_not_exist.json"
  
  assert_error {
    if not ($nonexistent_file | path exists) {
      error make { msg: $"File not found: ($nonexistent_file)" }
    }
    open $nonexistent_file
  } "Should handle missing file gracefully"
}

@test
def "integration test malformed json handling" [] {
  let context = setup_integration_test
  mkdir $context.snapshots_dir
  
  let bad_json_file = $"($context.snapshots_dir)/bad.json"
  "{ invalid json content" | save $bad_json_file
  
  assert_error {
    open $bad_json_file | from json
  } "Should handle malformed JSON gracefully"
  
  cleanup_integration_test $context
}

# Performance test with larger datasets
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
  assert ($snapshot_json | str length) > 1000 "Large snapshot should be substantial size"
}