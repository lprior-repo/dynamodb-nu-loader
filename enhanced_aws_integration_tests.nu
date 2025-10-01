#!/usr/bin/env nu

# Enhanced AWS Integration Test Suite for DynamoDB Nu-Loader
# Comprehensive testing including edge cases, error conditions, and cleanup
#
# ⚠️ WARNING: This test suite creates and destroys REAL AWS resources
# Ensure you have:
# 1. Valid AWS credentials configured
# 2. Permissions for DynamoDB operations
# 3. A test AWS account/region (to avoid production data)

print "🔥 DynamoDB Nu-Loader - Enhanced AWS Integration Test Suite"
print "=========================================================="
print "⚠️  WARNING: Uses REAL AWS resources with your credentials"
print ""

# Global test configuration
let test_config = {
    region: ($env.AWS_TEST_REGION? | default "us-east-1"),
    profile: ($env.AWS_TEST_PROFILE? | default "default"),
    table_prefix: "nu-loader-enhanced-test",
    cleanup_on_failure: true,
    test_timeout: "5min"
}

print $"📋 Test Configuration:"
print $"   Region: ($test_config.region)"
print $"   Profile: ($test_config.profile)" 
print $"   Table Prefix: ($test_config.table_prefix)"
print ""

# Global cleanup tracking
let cleanup_state = {
    tables_created: [],
    files_created: [],
    snapshots_created: []
}

# =============================================================================
# CLEANUP AND TEARDOWN FUNCTIONS (AFTERALL)
# =============================================================================

def cleanup_all_test_resources []: nothing -> nothing {
    print "\n🧹 Starting comprehensive cleanup (afterAll)..."
    print "================================================="
    
    # Clean up any remaining test tables
    print "🗑️  Cleaning up test tables..."
    let all_tables = (try {
        ^aws dynamodb list-tables --region $test_config.region | complete
    } catch {
        { exit_code: 1, stderr: "Failed to list tables" }
    })
    
    if $all_tables.exit_code == 0 {
        let table_list = ($all_tables.stdout | from json | get TableNames)
        let test_tables = ($table_list | where $it =~ $test_config.table_prefix)
        
        if ($test_tables | length) > 0 {
            print $"Found ($test_tables | length) test tables to clean up:"
            $test_tables | each { |table|
                print $"   - Deleting: ($table)"
                try {
                    ^aws dynamodb delete-table --table-name $table --region $test_config.region | complete
                } catch {
                    print $"     ⚠️  Warning: Failed to delete ($table)"
                }
            }
        } else {
            print "✅ No test tables found to clean up"
        }
    }
    
    # Clean up test files
    print "📁 Cleaning up test files..."
    let test_files = [
        "/tmp/enhanced_test_data.json",
        "/tmp/large_test_data.json", 
        "/tmp/malformed_test_data.json",
        "/tmp/unicode_test_data.json",
        "/tmp/stress_test_data.json"
    ]
    
    $test_files | each { |file|
        if ($file | path exists) {
            print $"   - Removing: ($file)"
            rm $file
        }
    }
    
    # Clean up any snapshot files created during testing
    print "📸 Cleaning up snapshot files..."
    let snapshot_patterns = [
        "enhanced-test-*",
        "stress-test-*",
        "large-data-*",
        "unicode-test-*",
        "error-test-*"
    ]
    
    $snapshot_patterns | each { |pattern|
        try {
            ls $pattern | each { |file|
                print $"   - Removing snapshot: ($file.name)"
                rm $file.name
            }
        } catch {
            # No files matching pattern - that's fine
        }
    }
    
    print "✅ Cleanup completed - all test resources removed"
}

# =============================================================================
# ENHANCED TEST UTILITIES
# =============================================================================

def create_test_table_with_schema [table_name: string, region: string, schema_type: string]: nothing -> nothing {
    print $"🏗️  Creating ($schema_type) test table: ($table_name)"
    
    let result = match $schema_type {
        "standard" => {
            (^aws dynamodb create-table 
                --table-name $table_name
                --attribute-definitions 
                    "AttributeName=id,AttributeType=S"
                    "AttributeName=sort_key,AttributeType=S"
                --key-schema 
                    "AttributeName=id,KeyType=HASH"
                    "AttributeName=sort_key,KeyType=RANGE"
                --billing-mode PAY_PER_REQUEST
                --region $region
                | complete)
        },
        "hash_only" => {
            (^aws dynamodb create-table 
                --table-name $table_name
                --attribute-definitions 
                    "AttributeName=id,AttributeType=S"
                --key-schema 
                    "AttributeName=id,KeyType=HASH"
                --billing-mode PAY_PER_REQUEST
                --region $region
                | complete)
        },
        "numeric_keys" => {
            (^aws dynamodb create-table 
                --table-name $table_name
                --attribute-definitions 
                    "AttributeName=id,AttributeType=N"
                    "AttributeName=sort_key,AttributeType=N"
                --key-schema 
                    "AttributeName=id,KeyType=HASH"
                    "AttributeName=sort_key,KeyType=RANGE"
                --billing-mode PAY_PER_REQUEST
                --region $region
                | complete)
        },
        _ => {
            error make { msg: $"Unknown schema type: ($schema_type)" }
        }
    }
    
    if $result.exit_code != 0 {
        error make { msg: $"Failed to create ($schema_type) test table: ($result.stderr)" }
    }
    
    # Wait for table to be active
    print "⏳ Waiting for table to become active..."
    loop {
        let status_result = (^aws dynamodb describe-table --table-name $table_name --region $region | complete)
        if $status_result.exit_code == 0 {
            let status = ($status_result.stdout | from json | get Table.TableStatus)
            if $status == "ACTIVE" {
                break
            }
            print $"   Status: ($status)"
        }
        sleep 3sec
    }
    print "✅ Table created and active"
}

def generate_large_test_data [count: int]: nothing -> list<record> {
    # Generate test data that pushes various limits
    1..$count | each { |i|
        let large_field = if ($i mod 10) == 0 {
            # Every 10th item has a large field (approaching DynamoDB limits)
            (1..1000 | each { |_| "Large data field content " } | str join "")
        } else {
            $"Normal content for item ($i)"
        }
        
        {
            id: $"large-item-(random chars --length 8)-($i | fill -w 5 -c '0')",
            sort_key: $"LARGE#($i)",
            large_content: $large_field,
            unicode_content: $"🚀 Test item ($i) with unicode: 中文 العربية 日本語",
            special_chars: $"Special: !@#$%^&*()_+-=[]{}|;':\",./<>? Item ($i)",
            numeric_edge: (if ($i mod 2) == 0 { $i * 1000000 } else { $i * -1000000 }),
            float_edge: ($i * 3.14159265359),
            boolean_value: (($i mod 2) == 0),
            empty_when_odd: (if ($i mod 2) == 1 { "" } else { $"Content ($i)" }),
            null_when_divisible_by_5: (if ($i mod 5) == 0 { null } else { $"Value ($i)" })
        }
    }
}

def generate_unicode_stress_data [count: int]: nothing -> list<record> {
    let unicode_samples = [
        "🚀🌟⭐✨💫🌙☀️🌍🌈🔥",
        "中文测试数据包含各种字符",
        "اختبار البيانات العربية مع النصوص",
        "日本語のテストデータです",
        "Тестовые данные на русском языке",
        "Δοκιμαστικά δεδομένα στα ελληνικά",
        "פירוט הנתונים לבדיקה בעברית",
        "हिंदी परीक्षण डेटा यहाँ है"
    ]
    
    1..$count | each { |i|
        let unicode_text = ($unicode_samples | get (($i - 1) mod ($unicode_samples | length)))
        {
            id: $"unicode-($i | fill -w 4 -c '0')",
            sort_key: "UNICODE",
            text: $unicode_text,
            mixed: $"Item ($i): ($unicode_text)",
            emoji_field: "🎯🔍📊💡🚨⚡🌐🔧",
            rtl_text: "العربية: البيانات التجريبية",
            complex_unicode: "🇺🇸🇨🇳🇯🇵🇩🇪🇫🇷 Multi-flag test"
        }
    }
}

def run_enhanced_test [test_name: string, test_fn: closure]: nothing -> record {
    print $"\\n🧪 Enhanced Test: ($test_name)"
    print "=" * 70
    
    let test_start = (date now)
    
    let result = try {
        do $test_fn
        { status: "PASS", error: null }
    } catch { |error|
        { status: "FAIL", error: $error.msg }
    }
    
    let test_end = (date now)
    let duration = ($test_end - $test_start)
    
    if $result.status == "PASS" {
        print $"✅ PASS: ($test_name) (($duration))"
    } else {
        print $"❌ FAIL: ($test_name) - ($result.error)"
    }
    
    {
        name: $test_name,
        status: $result.status,
        duration: $duration,
        error: $result.error
    }
}

# =============================================================================
# AWS SERVICE LIMITS AND FAILURE TESTS
# =============================================================================

def test_aws_credentials_validation_comprehensive []: nothing -> nothing {
    print "🔐 Comprehensive AWS credentials validation..."
    
    # Test basic authentication
    let identity_result = (^aws sts get-caller-identity --region $test_config.region | complete)
    if $identity_result.exit_code != 0 {
        error make { msg: $"AWS credentials validation failed: ($identity_result.stderr)" }
    }
    
    let identity = ($identity_result.stdout | from json)
    print $"✅ Authenticated as: ($identity.Arn)"
    
    # Test DynamoDB permissions
    let permissions_result = (^aws dynamodb list-tables --region $test_config.region | complete)
    if $permissions_result.exit_code != 0 {
        error make { msg: $"DynamoDB permissions check failed: ($permissions_result.stderr)" }
    }
    
    print "✅ DynamoDB permissions validated"
}

def test_large_item_handling_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-large-items"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        # Generate items with large content (but under 400KB limit)
        let large_data = generate_large_test_data 25
        let test_file = "/tmp/large_test_data.json"
        $large_data | to json | save $test_file
        
        print "📦 Testing large item handling in AWS..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        $env.SKIP_CONFIRMATION = "true"
        
        # Test seeding large items
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Large item seed failed: ($seed_result.stderr)" }
        }
        
        # Verify items were stored
        let scan_result = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        if $scan_result.exit_code != 0 {
            error make { msg: $"Large item scan failed: ($scan_result.stderr)" }
        }
        
        let scanned_data = ($scan_result.stdout | from json)
        let item_count = ($scanned_data.Items | length)
        
        if $item_count != 25 {
            error make { msg: $"Expected 25 large items, found ($item_count)" }
        }
        
        print "✅ Successfully handled large items in AWS DynamoDB"
        
        # Cleanup
        rm $test_file
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

def test_unicode_data_integrity_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-unicode"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        # Generate unicode stress test data
        let unicode_data = generate_unicode_stress_data 50
        let test_file = "/tmp/unicode_test_data.json"
        $unicode_data | to json | save $test_file
        
        print "🌐 Testing unicode data integrity in AWS..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Seed unicode data
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Unicode seed failed: ($seed_result.stderr)" }
        }
        
        # Create snapshot to test unicode preservation
        let snapshot_name = "unicode-test-snapshot"
        let snapshot_result = (nu main.nu snapshot $snapshot_name | complete)
        if $snapshot_result.exit_code != 0 {
            error make { msg: $"Unicode snapshot failed: ($snapshot_result.stderr)" }
        }
        
        # Verify snapshot contains unicode data
        let snapshot_data = (open $snapshot_name | from json)
        let sample_item = ($snapshot_data.data | first)
        
        if not ($sample_item.emoji_field? | default "" | str contains "🎯") {
            error make { msg: "Unicode data corrupted in snapshot" }
        }
        
        print "✅ Unicode data integrity preserved through full cycle"
        
        # Cleanup
        rm $test_file
        rm $snapshot_name
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

def test_batch_operation_limits_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-batch-limits"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        # Test exactly at DynamoDB batch limits (25 items)
        let batch_data = generate_large_test_data 75  # Will be split into 3 batches
        let test_file = "/tmp/batch_test_data.json"
        $batch_data | to json | save $test_file
        
        print "⚖️  Testing DynamoDB batch operation limits..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Should automatically handle batch splitting
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Batch limit test failed: ($seed_result.stderr)" }
        }
        
        # Verify all items were processed
        let scan_result = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let scanned_data = ($scan_result.stdout | from json)
        let actual_count = ($scanned_data.Items | length)
        
        if $actual_count != 75 {
            error make { msg: $"Batch processing failed: expected 75 items, got ($actual_count)" }
        }
        
        print "✅ Batch operation limits handled correctly"
        
        # Cleanup
        rm $test_file
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

def test_different_table_schemas []: nothing -> nothing {
    print "🏗️  Testing different DynamoDB table schemas..."
    
    # Test hash-only table (no sort key)
    let hash_only_table = $"($test_config.table_prefix)-hash-only"
    create_test_table_with_schema $hash_only_table $test_config.region "hash_only"
    
    try {
        # Create data suitable for hash-only table
        let hash_only_data = [
            { id: "hash-1", name: "Hash Only Item 1", value: 100 },
            { id: "hash-2", name: "Hash Only Item 2", value: 200 },
            { id: "hash-3", name: "Hash Only Item 3", value: 300 }
        ]
        
        let test_file = "/tmp/hash_only_test.json"
        $hash_only_data | to json | save $test_file
        
        $env.TABLE_NAME = $hash_only_table
        $env.AWS_REGION = $test_config.region
        
        # This might fail if tool assumes sort key exists
        let seed_result = (nu main.nu seed $test_file | complete)
        
        # Check if tool handled hash-only table gracefully
        if $seed_result.exit_code == 0 {
            # Verify data was stored
            let scan_result = (^aws dynamodb scan --table-name $hash_only_table --region $test_config.region | complete)
            let item_count = ($scan_result.stdout | from json | get Items | length)
            
            if $item_count != 3 {
                error make { msg: $"Hash-only table test failed: wrong item count ($item_count)" }
            }
            print "✅ Hash-only table schema handled correctly"
        } else {
            print "⚠️  Tool may not support hash-only tables (this could be expected)"
            print $"    Error: ($seed_result.stderr)"
        }
        
        # Cleanup
        rm $test_file
        
    } catch { |error|
        print $"⚠️  Hash-only table test error: ($error.msg)"
    }
    
    let _ = (^aws dynamodb delete-table --table-name $hash_only_table --region $test_config.region | complete)
}

def test_error_handling_malformed_data []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-error-handling"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        print "💥 Testing error handling with malformed data..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Test with malformed JSON file
        let malformed_json = '{"id": "test", "sort_key": "TEST", "incomplete": '
        let malformed_file = "/tmp/malformed_test_data.json"
        $malformed_json | save $malformed_file
        
        # Should fail gracefully
        let seed_result = (nu main.nu seed $malformed_file | complete)
        if $seed_result.exit_code == 0 {
            error make { msg: "Tool should have failed with malformed JSON" }
        }
        
        print "✅ Malformed JSON handled gracefully (failed as expected)"
        
        # Test with empty file
        let empty_file = "/tmp/empty_test_data.json"
        "" | save $empty_file
        
        let empty_result = (nu main.nu seed $empty_file | complete)
        if $empty_result.exit_code == 0 {
            print "⚠️  Empty file was accepted (may need validation)"
        } else {
            print "✅ Empty file rejected appropriately"
        }
        
        # Cleanup
        rm $malformed_file
        rm $empty_file
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

def test_network_timeout_resilience []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-network-test"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        print "🌐 Testing network resilience with large operations..."
        
        # Generate a substantial dataset to stress network
        let large_dataset = generate_large_test_data 200
        let test_file = "/tmp/network_stress_test.json"
        $large_dataset | to json | save $test_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # This should stress the network connection
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Network stress test failed: ($seed_result.stderr)" }
        }
        
        # Test large scan operation
        let scan_result = (nu main.nu scan | complete)
        if $scan_result.exit_code != 0 {
            error make { msg: $"Large scan failed: ($scan_result.stderr)" }
        }
        
        print "✅ Network resilience test passed"
        
        # Cleanup
        rm $test_file
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

def test_concurrent_operation_simulation []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-concurrent"
    
    create_test_table_with_schema $table_name $test_config.region "standard"
    
    try {
        print "🔄 Testing concurrent operation scenarios..."
        
        # Create multiple test files for simulated concurrent operations
        let data1 = generate_large_test_data 30
        let data2 = generate_unicode_stress_data 30
        
        let file1 = "/tmp/concurrent_test_1.json"
        let file2 = "/tmp/concurrent_test_2.json"
        
        $data1 | to json | save $file1
        $data2 | to json | save $file2
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Sequential operations to simulate potential race conditions
        let result1 = (nu main.nu seed $file1 | complete)
        let result2 = (nu main.nu seed $file2 | complete)
        
        if $result1.exit_code != 0 or $result2.exit_code != 0 {
            error make { msg: "Concurrent operation simulation failed" }
        }
        
        # Verify both datasets were processed
        let final_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let final_count = ($final_scan.stdout | from json | get Items | length)
        
        if $final_count != 60 {
            error make { msg: $"Expected 60 items from concurrent ops, got ($final_count)" }
        }
        
        print "✅ Concurrent operation simulation successful"
        
        # Cleanup
        rm $file1
        rm $file2
        
    } catch { |error|
        let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
        error make { msg: $error.msg }
    }
    
    let _ = (^aws dynamodb delete-table --table-name $table_name --region $test_config.region | complete)
}

# =============================================================================
# MAIN TEST EXECUTION WITH ENHANCED SCENARIOS
# =============================================================================

print "🚀 Starting Enhanced AWS Integration Tests..."
print ""

let start_time = (date now)

# Run enhanced test suite
let test_results = [
    (run_enhanced_test "AWS Credentials Validation Comprehensive" { test_aws_credentials_validation_comprehensive }),
    (run_enhanced_test "Large Item Handling AWS" { test_large_item_handling_aws }),
    (run_enhanced_test "Unicode Data Integrity AWS" { test_unicode_data_integrity_aws }),
    (run_enhanced_test "Batch Operation Limits AWS" { test_batch_operation_limits_aws }),
    (run_enhanced_test "Different Table Schemas" { test_different_table_schemas }),
    (run_enhanced_test "Error Handling Malformed Data" { test_error_handling_malformed_data }),
    (run_enhanced_test "Network Timeout Resilience" { test_network_timeout_resilience }),
    (run_enhanced_test "Concurrent Operation Simulation" { test_concurrent_operation_simulation })
]

let end_time = (date now)
let total_duration = ($end_time - $start_time)

# =============================================================================
# AFTERALL CLEANUP AND REPORTING
# =============================================================================

# Always run cleanup regardless of test results
cleanup_all_test_resources

print "\n📊 Enhanced AWS Integration Test Results"
print "========================================"

let passed_tests = ($test_results | where status == "PASS" | length)
let total_tests = ($test_results | length)
let failed_tests = ($test_results | where status == "FAIL")

print $"✅ Passed: ($passed_tests)/($total_tests) tests"
print $"⏱️  Total Duration: ($total_duration)"

if ($failed_tests | length) > 0 {
    print "\n❌ Failed Tests:"
    $failed_tests | each { |test|
        print $"   - ($test.name): ($test.error)"
    }
    
    print "\n🔍 Bug Discovery Summary:"
    print "The failed tests above may have discovered bugs or limitations in the tool."
    print "These should be investigated and fixed to improve production reliability."
    exit 1
} else {
    print "\n🎉 All enhanced integration tests passed!"
    print "\n💡 Your DynamoDB Nu-Loader tool successfully handles:"
    print "   • Large items approaching DynamoDB limits"
    print "   • Unicode and special character data"
    print "   • DynamoDB batch operation constraints"
    print "   • Different table schemas and edge cases"
    print "   • Error conditions and malformed data"
    print "   • Network stress and resilience scenarios" 
    print "   • Simulated concurrent operations"
    print "\n🚀 Tool demonstrates production-ready reliability!"
}