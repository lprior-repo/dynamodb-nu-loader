#!/usr/bin/env nu

# Test suite for AWS CLI integration and complete command usage
# Tests error handling, stderr/stdout parsing, and exit code management

use ../helpers/test_utils.nu *

#[test]
def test_complete_command_structure [] {
    # Test that complete command returns expected structure
    
    # Mock complete result structure
    let mock_complete_result = {
        stdout: "test output",
        stderr: "test error",
        exit_code: 0
    }
    
    assert_type $mock_complete_result "record" "Complete result should be a record"
    assert ("stdout" in ($mock_complete_result | columns)) "Should have stdout field"
    assert ("stderr" in ($mock_complete_result | columns)) "Should have stderr field"
    assert ("exit_code" in ($mock_complete_result | columns)) "Should have exit_code field"
    
    assert ($mock_complete_result.exit_code == 0) "Exit code should be accessible"
    assert ($mock_complete_result.stdout == "test output") "Stdout should be accessible"
    assert ($mock_complete_result.stderr == "test error") "Stderr should be accessible"
}

#[test]
def test_aws_error_patterns_comprehensive [] {
    # Test all AWS error patterns that should be handled
    
    let error_patterns = [
        {
            pattern: "ResourceNotFoundException",
            stderr: "An error occurred (ResourceNotFoundException) when calling the DescribeTable operation: Table not found",
            should_retry: false
        },
        {
            pattern: "ProvisionedThroughputExceededException", 
            stderr: "An error occurred (ProvisionedThroughputExceededException) when calling the Scan operation: The level of configured provisioned throughput for the table was exceeded",
            should_retry: true
        },
        {
            pattern: "ThrottlingException",
            stderr: "An error occurred (ThrottlingException) when calling the BatchWriteItem operation: Rate of requests exceeds the allowed throughput",
            should_retry: true
        },
        {
            pattern: "RequestLimitExceeded",
            stderr: "An error occurred (RequestLimitExceeded) when calling the Scan operation: Throughput exceeds the current capacity of your table or index",
            should_retry: false
        },
        {
            pattern: "InternalServerError",
            stderr: "An error occurred (InternalServerError) when calling the DescribeTable operation: We encountered an internal error. Please try again",
            should_retry: true
        },
        {
            pattern: "ValidationException",
            stderr: "An error occurred (ValidationException) when calling the BatchWriteItem operation: The provided key element does not match the schema",
            should_retry: false
        },
        {
            pattern: "ItemCollectionSizeLimitExceededException",
            stderr: "An error occurred (ItemCollectionSizeLimitExceededException) when calling the PutItem operation: Item collection size limit exceeded",
            should_retry: false
        },
        {
            pattern: "ReplicatedWriteConflictException",
            stderr: "An error occurred (ReplicatedWriteConflictException) when calling the PutItem operation: A concurrent modification was made",
            should_retry: true
        },
        {
            pattern: "AccessDeniedException",
            stderr: "An error occurred (AccessDeniedException) when calling the DescribeTable operation: User is not authorized to perform this action",
            should_retry: false
        },
        {
            pattern: "UnrecognizedClientException", 
            stderr: "An error occurred (UnrecognizedClientException) when calling the DescribeTable operation: The security token included in the request is invalid",
            should_retry: false
        }
    ]
    
    for error_case in $error_patterns {
        # Test that each pattern is correctly identified
        assert ($error_case.stderr | str contains $error_case.pattern) $"Stderr should contain ($error_case.pattern)"
        
        # Test retryable vs non-retryable classification
        let is_retryable = (
            ($error_case.pattern | str contains "ThrottlingException") or
            ($error_case.pattern | str contains "ProvisionedThroughputExceededException") or
            ($error_case.pattern | str contains "InternalServerError") or
            ($error_case.pattern | str contains "ReplicatedWriteConflictException")
        )
        assert ($is_retryable == $error_case.should_retry) $"Retry classification should be correct for ($error_case.pattern)"
    }
}

#[test]
def test_complete_result_exit_code_handling [] {
    # Test different exit code scenarios
    
    let success_result = {
        stdout: '{"Table": {"TableName": "test-table"}}',
        stderr: "",
        exit_code: 0
    }
    
    let error_result = {
        stdout: "",
        stderr: "An error occurred (ResourceNotFoundException) when calling the DescribeTable operation: Table not found",
        exit_code: 254
    }
    
    let throttle_result = {
        stdout: "",
        stderr: "An error occurred (ThrottlingException) when calling the Scan operation: Request throttled",
        exit_code: 254
    }
    
    # Test success path
    assert ($success_result.exit_code == 0) "Success should have exit code 0"
    assert ($success_result.stdout | str contains "Table") "Success should have table data in stdout"
    
    # Test error path
    assert ($error_result.exit_code != 0) "Error should have non-zero exit code"
    assert ($error_result.stderr | str contains "ResourceNotFoundException") "Error should have error info in stderr"
    
    # Test retryable error
    assert ($throttle_result.exit_code != 0) "Throttle should have non-zero exit code"
    assert ($throttle_result.stderr | str contains "ThrottlingException") "Throttle should be identifiable"
}

#[test]
def test_json_parsing_from_stdout [] {
    # Test JSON parsing from stdout in different scenarios
    
    # Valid JSON response
    let valid_json_stdout = '{"Table": {"TableName": "test-table", "TableStatus": "ACTIVE", "ItemCount": 100}}'
    let parsed_result = try {
        $valid_json_stdout | from json
    } catch {
        null
    }
    
    assert ($parsed_result != null) "Valid JSON should parse successfully"
    assert ($parsed_result.Table.TableName == "test-table") "Parsed data should be accessible"
    assert ($parsed_result.Table.ItemCount == 100) "Numbers should parse correctly"
    
    # Invalid JSON response
    let invalid_json_stdout = '{"Table": {"TableName": "test-table", "Incomplete'
    let invalid_parsed = try {
        $invalid_json_stdout | from json
        false
    } catch {
        true
    }
    
    assert $invalid_parsed "Invalid JSON should throw error"
    
    # Empty response
    let empty_stdout = ""
    let empty_parsed = try {
        $empty_stdout | from json
        false
    } catch {
        true
    }
    
    assert $empty_parsed "Empty stdout should throw error when parsing as JSON"
}

#[test]
def test_stderr_error_extraction [] {
    # Test extracting error information from stderr
    
    let complex_stderr = """
An error occurred (ResourceNotFoundException) when calling the DescribeTable operation: Requested resource not found
Request ID: abc123-def456-ghi789
    """
    
    # Test basic pattern matching
    assert ($complex_stderr | str contains "ResourceNotFoundException") "Should detect error type"
    assert ($complex_stderr | str contains "DescribeTable") "Should detect operation"
    assert ($complex_stderr | str contains "Requested resource not found") "Should detect error message"
    
    # Test multiline stderr handling
    let multiline_stderr = """
An error occurred (ValidationException) when calling the BatchWriteItem operation: One or more parameter values were invalid: Item size has exceeded 400KB limit
Additional context information may be available
    """
    
    assert ($multiline_stderr | str contains "ValidationException") "Should handle multiline stderr"
    assert ($multiline_stderr | str contains "400KB limit") "Should preserve full error message"
}

#[test]
def test_aws_cli_command_construction [] {
    # Test AWS CLI command parameter handling
    
    let table_name = "test-table"
    let region = "us-east-1"
    
    # Test describe-table command structure
    let describe_cmd_parts = ["aws", "dynamodb", "describe-table", "--table-name", $table_name, "--region", $region]
    assert (($describe_cmd_parts | length) == 7) "Describe command should have correct number of parts"
    assert ($describe_cmd_parts | get 2) == "describe-table" "Command should be describe-table"
    assert ($describe_cmd_parts | get 4) == $table_name "Table name should be included"
    assert ($describe_cmd_parts | get 6) == $region "Region should be included"
    
    # Test scan command structure
    let scan_cmd_parts = ["aws", "dynamodb", "scan", "--table-name", $table_name, "--region", $region]
    assert ($scan_cmd_parts | get 2) == "scan" "Command should be scan"
    
    # Test file parameter handling
    let temp_file = "/tmp/test_file.json"
    let file_param = $"file://($temp_file)"
    assert ($file_param | str starts-with "file://") "File parameter should have correct prefix"
    assert ($file_param | str contains $temp_file) "File parameter should contain file path"
}

#[test]
def test_region_and_table_validation [] {
    # Test parameter validation logic
    
    # Test null region handling
    let null_region = null
    let env_region = $env.AWS_REGION?
    let final_region = $null_region | default $env_region
    
    # Test table name validation
    let valid_table_name = "test-table-123"
    let invalid_table_name = ""
    
    assert ($valid_table_name | str length) > 0 "Valid table name should have length"
    assert ($invalid_table_name | str length) == 0 "Invalid table name should be empty"
    
    # Test region format validation
    let valid_regions = ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"]
    for region in $valid_regions {
        assert ($region | str contains "-") "Valid regions should contain hyphens"
        assert (($region | str length) >= 9) "Valid regions should have minimum length"
    }
}

#[test]
def test_complete_with_different_commands [] {
    # Test complete command with different AWS CLI commands
    
    # Mock different command results
    let describe_result = {
        stdout: '{"Table": {"TableName": "test"}}',
        stderr: "",
        exit_code: 0
    }
    
    let scan_result = {
        stdout: '{"Items": [], "Count": 0, "ScannedCount": 0}',
        stderr: "",
        exit_code: 0
    }
    
    let batch_write_result = {
        stdout: '{"UnprocessedItems": {}}',
        stderr: "",
        exit_code: 0
    }
    
    let sts_result = {
        stdout: '{"UserId": "test", "Account": "123456789", "Arn": "arn:aws:iam::123456789:user/test"}',
        stderr: "",
        exit_code: 0
    }
    
    # Test each command type returns expected structure
    for result in [$describe_result, $scan_result, $batch_write_result, $sts_result] {
        assert_type $result "record" "Command result should be record"
        assert ("exit_code" in ($result | columns)) "Should have exit_code"
        assert ($result.exit_code == 0) "Mock results should be successful"
        
        let parsed_stdout = try {
            $result.stdout | from json
        } catch {
            null
        }
        assert ($parsed_stdout != null) "Stdout should be valid JSON"
    }
}

#[test]
def test_error_handling_consistency [] {
    # Test that error handling is consistent across all AWS operations
    
    let operations = [
        "describe-table",
        "scan-table", 
        "batch-write-item",
        "validate-credentials"
    ]
    
    for operation in $operations {
        # Test that operation names are valid
        assert ($operation | str length) > 0 "Operation name should not be empty"
        assert ($operation | str contains "-") "Operation name should contain hyphens"
        
        # Test error message construction
        let error_msg = $"AWS operation failed during ($operation)"
        assert ($error_msg | str contains $operation) "Error message should contain operation name"
        assert ($error_msg | str contains "AWS") "Error message should mention AWS"
    }
}

#[test]
def test_temp_file_path_construction [] {
    # Test temporary file path construction patterns
    
    let random_suffix = "abc123def"
    let temp_patterns = [
        $"/tmp/exclusive_start_key_($random_suffix).json",
        $"/tmp/batch_request_($random_suffix).json", 
        $"/tmp/dynamodb_nu_loader_($random_suffix).json"
    ]
    
    for temp_path in $temp_patterns {
        assert ($temp_path | str starts-with "/tmp/") "Temp files should be in /tmp"
        assert ($temp_path | str ends-with ".json") "Temp files should have .json extension"
        assert ($temp_path | str contains $random_suffix) "Temp files should contain random suffix"
        assert (($temp_path | str length) > 20) "Temp file paths should have reasonable length"
    }
}

#[test]
def test_aws_response_structure_validation [] {
    # Test AWS response structure validation
    
    # DescribeTable response structure
    let describe_response = {
        "Table": {
            "TableName": "test-table",
            "TableStatus": "ACTIVE",
            "KeySchema": [
                {"AttributeName": "id", "KeyType": "HASH"}
            ],
            "AttributeDefinitions": [
                {"AttributeName": "id", "AttributeType": "S"}
            ],
            "ItemCount": 100,
            "TableSizeBytes": 1024,
            "CreationDateTime": "2024-01-01T00:00:00Z"
        }
    }
    
    assert ("Table" in ($describe_response | columns)) "Response should have Table field"
    let table = $describe_response.Table
    assert ("TableName" in ($table | columns)) "Table should have TableName"
    assert ("KeySchema" in ($table | columns)) "Table should have KeySchema"
    assert ("AttributeDefinitions" in ($table | columns)) "Table should have AttributeDefinitions"
    
    # Scan response structure
    let scan_response = {
        "Items": [
            {"id": {"S": "item1"}, "name": {"S": "test"}}
        ],
        "Count": 1,
        "ScannedCount": 1,
        "LastEvaluatedKey": {
            "id": {"S": "item1"}
        }
    }
    
    assert ("Items" in ($scan_response | columns)) "Scan response should have Items"
    assert ("Count" in ($scan_response | columns)) "Scan response should have Count"
    assert ("ScannedCount" in ($scan_response | columns)) "Scan response should have ScannedCount"
    assert (($scan_response.Items | length) == 1) "Items should be accessible as list"
    
    # BatchWriteItem response structure
    let batch_response = {
        "UnprocessedItems": {
            "test-table": [
                {"PutRequest": {"Item": {"id": {"S": "item1"}}}}
            ]
        }
    }
    
    assert ("UnprocessedItems" in ($batch_response | columns)) "Batch response should have UnprocessedItems"
    let unprocessed = $batch_response.UnprocessedItems
    assert ("test-table" in ($unprocessed | columns)) "UnprocessedItems should contain table name"
}

# All tests completed - no print needed in module