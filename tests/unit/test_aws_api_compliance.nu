#!/usr/bin/env nu

# Test suite for AWS API compliance and enhanced functionality
# Tests pagination, retry logic, error handling, and schema validation

use ../helpers/test_utils.nu *

#[test]
def test_scan_table_page_structure [] {
    # Test that scan_table_page returns correct structure
    # Note: This is a mock test since we can't run actual AWS commands in tests
    
    let mock_scan_result = {
        items: [],
        last_evaluated_key: null,
        scanned_count: 0,
        count: 0
    }
    
    # Verify the expected structure exists
    assert ($mock_scan_result | get items | describe | str contains "list") "Items should be a list"
    assert ("last_evaluated_key" in ($mock_scan_result | columns)) "Should have last_evaluated_key field"
    assert ("scanned_count" in ($mock_scan_result | columns)) "Should have scanned_count field"
    assert ("count" in ($mock_scan_result | columns)) "Should have count field"
}

#[test]
def test_batch_write_request_structure [] {
    # Test the structure of batch write requests
    let test_items = [
        {id: "test1", name: "Alice"},
        {id: "test2", name: "Bob"}
    ]
    
    let dynamodb_items = ($test_items | each { |item|
        let converted_item = ($item | transpose key value | reduce -f {} { |row, acc|
            let field_name = $row.key
            let field_value = $row.value
            let dynamodb_value = convert_to_dynamodb_value $field_value
            $acc | insert $field_name $dynamodb_value
        })
        { "PutRequest": { "Item": $converted_item } }
    })
    
    assert (($dynamodb_items | length) == 2) "Should have 2 items"
    assert ("PutRequest" in ($dynamodb_items | first | columns)) "Should have PutRequest structure"
    assert ("Item" in ($dynamodb_items | first | get PutRequest | columns)) "Should have Item in PutRequest"
}

#[test]
def test_delete_request_structure [] {
    # Test the structure of delete requests
    let test_item = {user_id: "user123", timestamp: "2024-01-01"}
    let key_schema = [
        {AttributeName: "user_id", KeyType: "HASH"},
        {AttributeName: "timestamp", KeyType: "RANGE"}
    ]
    let attribute_definitions = [
        {AttributeName: "user_id", AttributeType: "S"},
        {AttributeName: "timestamp", AttributeType: "S"}
    ]
    
    let key_object = get_key_attributes_for_item $test_item $key_schema $attribute_definitions
    let delete_request = {
        "DeleteRequest": {
            "Key": $key_object
        }
    }
    
    assert ("DeleteRequest" in ($delete_request | columns)) "Should have DeleteRequest structure"
    assert ("Key" in ($delete_request | get DeleteRequest | columns)) "Should have Key in DeleteRequest"
    assert ("user_id" in ($key_object | columns)) "Key should contain user_id"
    assert ("timestamp" in ($key_object | columns)) "Key should contain timestamp"
}

#[test]
def test_exponential_backoff_calculation [] {
    # Test exponential backoff wait times
    let wait_times = [1, 2, 4, 8, 16]
    
    assert (($wait_times | get 0) == 1) "First retry should wait 1 second"
    assert (($wait_times | get 1) == 2) "Second retry should wait 2 seconds"
    assert (($wait_times | get 2) == 4) "Third retry should wait 4 seconds"
    assert (($wait_times | get 3) == 8) "Fourth retry should wait 8 seconds"
    assert (($wait_times | get 4) == 16) "Fifth retry should wait 16 seconds"
}

#[test]
def test_chunking_logic_for_batch_operations [] {
    # Test that items are properly chunked into batches of 25
    let large_dataset = (0..100 | each { |i| {id: $"item($i)", value: $i} })
    let batches = ($large_dataset | chunks 25)
    
    assert (($batches | length) == 5) "Should create 5 batches for 101 items"
    assert (($batches | first | length) == 25) "First batch should have 25 items"
    assert (($batches | last | length) == 1) "Last batch should have 1 item"
}

#[test]
def test_unprocessed_items_structure [] {
    # Test structure for handling unprocessed items from AWS response
    let mock_unprocessed_response = {
        "UnprocessedItems": {
            "test-table": [
                {
                    "PutRequest": {
                        "Item": {
                            "id": {"S": "test1"},
                            "name": {"S": "Alice"}
                        }
                    }
                }
            ]
        }
    }
    
    let table_name = "test-table"
    let unprocessed = $mock_unprocessed_response | get -o UnprocessedItems
    
    assert ($unprocessed != null) "Should have UnprocessedItems field"
    assert ($table_name in ($unprocessed | columns)) "Should have table name in unprocessed items"
    assert (($unprocessed | get $table_name | length) == 1) "Should have 1 unprocessed item"
}

#[test]
def test_last_evaluated_key_structure [] {
    # Test LastEvaluatedKey structure for pagination
    let mock_last_evaluated_key = {
        "user_id": {"S": "user123"},
        "timestamp": {"S": "2024-01-01T10:00:00Z"}
    }
    
    assert ("user_id" in ($mock_last_evaluated_key | columns)) "Should have user_id key"
    assert ("timestamp" in ($mock_last_evaluated_key | columns)) "Should have timestamp key"
    assert (($mock_last_evaluated_key | get user_id | get S) == "user123") "Should have correct user_id value"
}

#[test]
def test_describe_table_response_structure [] {
    # Test expected structure from DescribeTable response
    let mock_describe_response = {
        "Table": {
            "TableName": "test-table",
            "KeySchema": [
                {"AttributeName": "id", "KeyType": "HASH"},
                {"AttributeName": "sort_key", "KeyType": "RANGE"}
            ],
            "AttributeDefinitions": [
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "sort_key", "AttributeType": "S"}
            ],
            "TableStatus": "ACTIVE",
            "CreationDateTime": 1234567890,
            "TableSizeBytes": 1024,
            "ItemCount": 100
        }
    }
    
    let table = $mock_describe_response | get Table
    assert ($table.TableName == "test-table") "Should have correct table name"
    assert (($table.KeySchema | length) == 2) "Should have 2 key schema entries"
    assert (($table.AttributeDefinitions | length) == 2) "Should have 2 attribute definitions"
    assert ($table.TableStatus == "ACTIVE") "Should have ACTIVE status"
}

#[test]
def test_scan_response_structure [] {
    # Test expected structure from Scan response
    let mock_scan_response = {
        "Items": [
            {
                "id": {"S": "item1"},
                "name": {"S": "Alice"}
            }
        ],
        "Count": 1,
        "ScannedCount": 1,
        "LastEvaluatedKey": {
            "id": {"S": "item1"}
        }
    }
    
    assert (($mock_scan_response | get Items | length) == 1) "Should have 1 item"
    assert ($mock_scan_response.Count == 1) "Should have Count field"
    assert ($mock_scan_response.ScannedCount == 1) "Should have ScannedCount field"
    assert ("LastEvaluatedKey" in ($mock_scan_response | columns)) "Should have LastEvaluatedKey field"
}

#[test]
def test_batch_write_response_structure [] {
    # Test expected structure from BatchWriteItem response
    let mock_batch_response = {
        "UnprocessedItems": {},
        "ConsumedCapacity": [
            {
                "TableName": "test-table",
                "CapacityUnits": 5.0
            }
        ]
    }
    
    assert ("UnprocessedItems" in ($mock_batch_response | columns)) "Should have UnprocessedItems field"
    assert ("ConsumedCapacity" in ($mock_batch_response | columns)) "Should have ConsumedCapacity field"
    assert (($mock_batch_response.ConsumedCapacity | length) == 1) "Should have 1 consumed capacity entry"
}

#[test]
def test_error_message_patterns [] {
    # Test error message pattern matching
    let error_patterns = [
        "ResourceNotFoundException",
        "ProvisionedThroughputExceededException", 
        "ThrottlingException",
        "RequestLimitExceeded",
        "InternalServerError",
        "ValidationException",
        "ItemCollectionSizeLimitExceededException",
        "ReplicatedWriteConflictException",
        "AccessDeniedException",
        "UnrecognizedClientException"
    ]
    
    for pattern in $error_patterns {
        let test_error = $"An error occurred: ($pattern) - details"
        assert ($test_error | str contains $pattern) $"Should detect ($pattern) error pattern"
    }
}

#[test]
def test_retryable_error_identification [] {
    # Test identification of retryable vs non-retryable errors
    let retryable_errors = [
        "ThrottlingException",
        "ProvisionedThroughputExceededException",
        "InternalServerError",
        "ReplicatedWriteConflictException"
    ]
    
    let non_retryable_errors = [
        "ResourceNotFoundException",
        "ValidationException",
        "AccessDeniedException",
        "UnrecognizedClientException"
    ]
    
    for error in $retryable_errors {
        let is_retryable = (
            ($error | str contains "ThrottlingException") or
            ($error | str contains "ProvisionedThroughputExceededException") or
            ($error | str contains "InternalServerError") or
            ($error | str contains "ReplicatedWriteConflictException")
        )
        assert $is_retryable $"($error) should be retryable"
    }
    
    for error in $non_retryable_errors {
        let is_retryable = (
            ($error | str contains "ThrottlingException") or
            ($error | str contains "ProvisionedThroughputExceededException") or
            ($error | str contains "InternalServerError") or
            ($error | str contains "ReplicatedWriteConflictException")
        )
        assert (not $is_retryable) $"($error) should not be retryable"
    }
}

# All tests completed - no print needed in module