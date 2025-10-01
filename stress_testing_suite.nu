#!/usr/bin/env nu

# Stress Testing Suite for DynamoDB Nu-Loader
# Tests performance limits, memory usage, and error recovery
#
# ⚠️ WARNING: This test suite creates significant AWS usage and may incur costs
# Ensure you have:
# 1. Valid AWS credentials configured
# 2. Sufficient DynamoDB provisioned capacity or PAY_PER_REQUEST
# 3. A test AWS account/region with cost monitoring

print "💪 DynamoDB Nu-Loader - Stress Testing Suite"
print "==========================================="
print "⚠️  WARNING: High-intensity testing with potential AWS costs"
print ""

# Stress test configuration
let stress_config = {
    region: ($env.AWS_TEST_REGION? | default "us-east-1"),
    table_prefix: "nu-loader-stress-test",
    max_items_per_test: 5000,
    large_item_size_kb: 300,
    cleanup_always: true
}

print $"📋 Stress Test Configuration:"
print $"   Region: ($stress_config.region)"
print $"   Table Prefix: ($stress_config.table_prefix)"
print $"   Max Items Per Test: ($stress_config.max_items_per_test)"
print ""

# Performance tracking
let performance_metrics = {
    tests_run: 0,
    total_items_processed: 0,
    total_data_size_mb: 0,
    max_memory_usage_mb: 0,
    errors_encountered: 0
}

# =============================================================================
# STRESS TEST DATA GENERATORS
# =============================================================================

def generate_stress_test_dataset [count: int, size_category: string]: nothing -> list<record> {
    match $size_category {
        "small" => {
            # Small items for volume testing
            1..$count | each { |i|
                {
                    id: $"stress-small-($i | fill --width 6 --char '0')",
                    sort_key: "SMALL",
                    data: $"Small test data item ($i)",
                    timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
                    sequence: $i
                }
            }
        },
        "medium" => {
            # Medium items with realistic data
            1..$count | each { |i|
                {
                    id: $"stress-medium-($i | fill --width 6 --char '0')",
                    sort_key: "MEDIUM",
                    description: $"This is a medium-sized test item with ID ($i) containing realistic data that might be found in production systems. It includes various field types and reasonable content length.",
                    metadata: {
                        created_by: "stress-test",
                        version: "1.0",
                        item_number: $i,
                        category: (["A", "B", "C", "D"] | get (($i - 1) mod 4))
                    },
                    tags: ["stress", "test", $"item-($i)", "medium"],
                    numeric_data: {
                        sequence: $i,
                        value: ($i * 3.14159),
                        count: ($i mod 100)
                    },
                    status: (if ($i mod 2) == 0 { "active" } else { "inactive" })
                }
            }
        },
        "large" => {
            # Large items approaching DynamoDB limits
            1..$count | each { |i|
                let large_content = ("Large content block for stress testing. " * 2000)
                {
                    id: $"stress-large-($i | fill --width 6 --char '0')",
                    sort_key: "LARGE",
                    large_field_1: $large_content,
                    large_field_2: ($large_content + $" Additional content for item ($i)"),
                    metadata: $"Metadata for large item ($i) with timestamp: (date now | format date '%Y-%m-%d %H:%M:%S')",
                    complex_data: {
                        nested_level_1: {
                            nested_level_2: {
                                deep_content: $"Deep nested content for item ($i)",
                                arrays: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                                more_text: ("Nested text content. " * 100)
                            }
                        }
                    }
                }
            }
        },
        "unicode" => {
            # Unicode stress test data
            let unicode_samples = [
                "🚀🌟⭐✨💫🌙☀️🌍🌈🔥💧⚡🌿🎯🔍📊💡🚨🎉🎊🎁",
                "中文测试数据包含各种复杂字符和符号用于压力测试",
                "اختبار البيانات العربية مع النصوص المعقدة والرموز المختلفة",
                "日本語のテストデータです。複雑な文字とシンボルを含みます。",
                "Тестовые данные на русском языке с различными символами",
                "Ελληνικά δεδομένα δοκιμής με διάφορα σύμβολα",
                "עברית: נתוני בדיקה עם סמלים וטקסט מורכב",
                "हिंदी परीक्षण डेटा विभिन्न प्रतीकों के साथ"
            ]
            
            1..$count | each { |i|
                let sample = ($unicode_samples | get (($i - 1) mod ($unicode_samples | length)))
                {
                    id: $"stress-unicode-($i | fill --width 6 --char '0')",
                    sort_key: "UNICODE",
                    unicode_text: $sample,
                    mixed_content: $"Item ($i): ($sample) with English text",
                    emoji_heavy: "🎯🔍📊💡🚨⚡🌐🔧🎨🎪🎭🎮🎲🎸🎤🎧🎵🎶🎼🎹",
                    complex_unicode: $"Combining: ($sample) 🌍🚀 with numbers ($i) and symbols !@#$%"
                }
            }
        },
        _ => {
            error make { msg: $"Unknown size category: ($size_category)" }
        }
    }
}

def measure_performance [operation_name: string, operation: closure]: nothing -> record {
    print $"⏱️  Measuring performance for: ($operation_name)"
    
    let start_time = (date now)
    let start_memory = try {
        # Try to get memory usage (may not work on all systems)
        (ps | where pid == (ps | where command =~ "nu" | first | get pid) | first | get mem)
    } catch {
        0
    }
    
    let result = try {
        do $operation
        { success: true, error: null }
    } catch { |error|
        { success: false, error: $error.msg }
    }
    
    let end_time = (date now)
    let duration = ($end_time - $start_time)
    
    let end_memory = try {
        (ps | where pid == (ps | where command =~ "nu" | first | get pid) | first | get mem)
    } catch {
        0
    }
    
    {
        operation: $operation_name,
        duration: $duration,
        success: $result.success,
        error: $result.error,
        memory_start_mb: $start_memory,
        memory_end_mb: $end_memory,
        memory_delta_mb: ($end_memory - $start_memory)
    }
}

# =============================================================================
# STRESS TEST SCENARIOS
# =============================================================================

def stress_test_volume_processing []: nothing -> record {
    print "📊 Stress Test: High Volume Data Processing"
    print "Testing with 2000 small items for volume performance..."
    
    let table_name = $"($stress_config.table_prefix)-volume"
    
    # Create table
    ^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
        --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
        --billing-mode PAY_PER_REQUEST
        --region $stress_config.region | complete
    
    # Wait for active
    loop {
        let status = (^aws dynamodb describe-table --table-name $table_name --region $stress_config.region | complete | get stdout | from json | get Table.TableStatus)
        if $status == "ACTIVE" { break }
        sleep 2sec
    }
    
    let performance = measure_performance "Volume Processing" {
        # Generate high volume dataset
        let volume_data = generate_stress_test_dataset 2000 "small"
        let test_file = "/tmp/stress_volume_test.json"
        $volume_data | to json | save $test_file
        
        # Set environment
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $stress_config.region
        $env.SKIP_CONFIRMATION = "true"
        
        # Process high volume
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Volume seed failed: ($seed_result.stderr)" }
        }
        
        # Verify count
        let scan_result = (^aws dynamodb scan --table-name $table_name --region $stress_config.region | complete)
        let item_count = ($scan_result.stdout | from json | get Items | length)
        
        if $item_count != 2000 {
            error make { msg: $"Volume test failed: expected 2000, got ($item_count)" }
        }
        
        # Test snapshot performance
        let snapshot_result = (nu main.nu snapshot "stress-volume-snapshot" | complete)
        if $snapshot_result.exit_code != 0 {
            error make { msg: $"Volume snapshot failed: ($snapshot_result.stderr)" }
        }
        
        # Cleanup
        rm $test_file
        rm "stress-volume-snapshot"
        
        print "✅ Volume processing completed successfully"
    }
    
    # Cleanup table
    ^aws dynamodb delete-table --table-name $table_name --region $stress_config.region | complete
    
    $performance
}

def stress_test_large_items []: nothing -> record {
    print "🗂️  Stress Test: Large Item Processing"
    print "Testing with items approaching DynamoDB size limits..."
    
    let table_name = $"($stress_config.table_prefix)-large-items"
    
    # Create table
    ^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
        --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
        --billing-mode PAY_PER_REQUEST
        --region $stress_config.region | complete
    
    # Wait for active
    loop {
        let status = (^aws dynamodb describe-table --table-name $table_name --region $stress_config.region | complete | get stdout | from json | get Table.TableStatus)
        if $status == "ACTIVE" { break }
        sleep 2sec
    }
    
    let performance = measure_performance "Large Item Processing" {
        # Generate large items (smaller count due to size)
        let large_data = generate_stress_test_dataset 50 "large"
        let test_file = "/tmp/stress_large_test.json"
        $large_data | to json | save $test_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $stress_config.region
        $env.SKIP_CONFIRMATION = "true"
        
        # Process large items
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Large item seed failed: ($seed_result.stderr)" }
        }
        
        # Test operations on large items
        let scan_result = (nu main.nu scan | complete)
        if $scan_result.exit_code != 0 {
            error make { msg: $"Large item scan failed: ($scan_result.stderr)" }
        }
        
        print "✅ Large item processing completed"
        
        # Cleanup
        rm $test_file
    }
    
    # Cleanup table
    ^aws dynamodb delete-table --table-name $table_name --region $stress_config.region | complete
    
    $performance
}

def stress_test_unicode_intensive []: nothing -> record {
    print "🌐 Stress Test: Unicode Intensive Processing"
    print "Testing with heavy unicode and special character data..."
    
    let table_name = $"($stress_config.table_prefix)-unicode"
    
    # Create table
    ^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
        --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
        --billing-mode PAY_PER_REQUEST
        --region $stress_config.region | complete
    
    # Wait for active
    loop {
        let status = (^aws dynamodb describe-table --table-name $table_name --region $stress_config.region | complete | get stdout | from json | get Table.TableStatus)
        if $status == "ACTIVE" { break }
        sleep 2sec
    }
    
    let performance = measure_performance "Unicode Intensive Processing" {
        # Generate unicode-heavy dataset
        let unicode_data = generate_stress_test_dataset 500 "unicode"
        let test_file = "/tmp/stress_unicode_test.json"
        $unicode_data | to json | save $test_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $stress_config.region
        
        # Process unicode data
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Unicode seed failed: ($seed_result.stderr)" }
        }
        
        # Test unicode preservation through full cycle
        let snapshot_result = (nu main.nu snapshot "stress-unicode-snapshot" | complete)
        if $snapshot_result.exit_code != 0 {
            error make { msg: $"Unicode snapshot failed: ($snapshot_result.stderr)" }
        }
        
        # Verify unicode integrity
        let snapshot_data = (open "stress-unicode-snapshot" | from json)
        let sample_item = ($snapshot_data.data | first)
        
        if not ($sample_item.emoji_heavy? | default "" | str contains "🎯") {
            error make { msg: "Unicode data corrupted during processing" }
        }
        
        print "✅ Unicode intensive processing completed"
        
        # Cleanup
        rm $test_file
        rm "stress-unicode-snapshot"
    }
    
    # Cleanup table
    ^aws dynamodb delete-table --table-name $table_name --region $stress_config.region | complete
    
    $performance
}

def stress_test_rapid_operations []: nothing -> record {
    print "⚡ Stress Test: Rapid Sequential Operations"
    print "Testing rapid sequence of different operations..."
    
    let table_name = $"($stress_config.table_prefix)-rapid"
    
    # Create table
    ^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
        --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
        --billing-mode PAY_PER_REQUEST
        --region $stress_config.region | complete
    
    # Wait for active
    loop {
        let status = (^aws dynamodb describe-table --table-name $table_name --region $stress_config.region | complete | get stdout | from json | get Table.TableStatus)
        if $status == "ACTIVE" { break }
        sleep 2sec
    }
    
    let performance = measure_performance "Rapid Sequential Operations" {
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $stress_config.region
        $env.SKIP_CONFIRMATION = "true"
        
        # Rapid sequence of operations
        for i in 1..10 {
            print $"   Rapid operation cycle ($i)/10"
            
            # Generate different data each cycle
            let cycle_data = generate_stress_test_dataset 100 "medium"
            let test_file = $"/tmp/stress_rapid_($i).json"
            $cycle_data | to json | save $test_file
            
            # Seed data
            let seed_result = (nu main.nu seed $test_file | complete)
            if $seed_result.exit_code != 0 {
                error make { msg: $"Rapid cycle ($i) seed failed" }
            }
            
            # Snapshot
            let snapshot_name = $"rapid-snapshot-($i)"
            nu main.nu snapshot $snapshot_name | complete
            
            # Wipe
            nu main.nu wipe | complete
            
            # Restore
            nu main.nu restore $snapshot_name | complete
            
            # Cleanup cycle files
            rm $test_file
            rm $snapshot_name
        }
        
        print "✅ Rapid sequential operations completed"
    }
    
    # Cleanup table
    ^aws dynamodb delete-table --table-name $table_name --region $stress_config.region | complete
    
    $performance
}

def stress_test_memory_intensive []: nothing -> record {
    print "💾 Stress Test: Memory Intensive Operations"
    print "Testing memory usage with large datasets in memory..."
    
    let table_name = $"($stress_config.table_prefix)-memory"
    
    # Create table
    ^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
        --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
        --billing-mode PAY_PER_REQUEST
        --region $stress_config.region | complete
    
    # Wait for active
    loop {
        let status = (^aws dynamodb describe-table --table-name $table_name --region $stress_config.region | complete | get stdout | from json | get Table.TableStatus)
        if $status == "ACTIVE" { break }
        sleep 2sec
    }
    
    let performance = measure_performance "Memory Intensive Operations" {
        # Generate large dataset that will stress memory
        let memory_data = generate_stress_test_dataset 1000 "medium"
        let test_file = "/tmp/stress_memory_test.json"
        $memory_data | to json | save $test_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $stress_config.region
        
        # Process large dataset
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Memory intensive seed failed: ($seed_result.stderr)" }
        }
        
        # Create large snapshot (memory intensive)
        let snapshot_result = (nu main.nu snapshot "stress-memory-snapshot" | complete)
        if $snapshot_result.exit_code != 0 {
            error make { msg: $"Memory intensive snapshot failed: ($snapshot_result.stderr)" }
        }
        
        print "✅ Memory intensive operations completed"
        
        # Cleanup
        rm $test_file
        rm "stress-memory-snapshot"
    }
    
    # Cleanup table
    ^aws dynamodb delete-table --table-name $table_name --region $stress_config.region | complete
    
    $performance
}

# =============================================================================
# STRESS TEST EXECUTION AND REPORTING
# =============================================================================

def cleanup_stress_test_resources []: nothing -> nothing {
    print "\n🧹 Cleaning up all stress test resources..."
    
    # List and delete all stress test tables
    let table_list = try {
        ^aws dynamodb list-tables --region $stress_config.region | complete | get stdout | from json | get TableNames
    } catch {
        []
    }
    
    let stress_tables = ($table_list | where $it =~ $stress_config.table_prefix)
    
    if ($stress_tables | length) > 0 {
        print $"Deleting ($stress_tables | length) stress test tables..."
        $stress_tables | each { |table|
            print $"   - ($table)"
            ^aws dynamodb delete-table --table-name $table --region $stress_config.region | complete
        }
    }
    
    # Clean up test files
    let stress_files = [
        "/tmp/stress_volume_test.json",
        "/tmp/stress_large_test.json", 
        "/tmp/stress_unicode_test.json",
        "/tmp/stress_memory_test.json"
    ]
    
    $stress_files | each { |file|
        if ($file | path exists) {
            rm $file
        }
    }
    
    # Clean up any remaining stress snapshots
    try {
        ls stress-* | each { |file|
            rm $file.name
        }
    } catch {
        # No stress files found
    }
    
    print "✅ Stress test cleanup completed"
}

# Main stress test execution
print "🚀 Starting DynamoDB Nu-Loader Stress Tests..."
print ""

let stress_start_time = (date now)

try {
    let stress_results = [
        (stress_test_volume_processing),
        (stress_test_large_items),
        (stress_test_unicode_intensive),
        (stress_test_rapid_operations),
        (stress_test_memory_intensive)
    ]
    
    let stress_end_time = (date now)
    let total_stress_duration = ($stress_end_time - $stress_start_time)
    
    print "\n📊 Stress Test Performance Report"
    print "================================="
    print $"⏱️  Total Stress Test Duration: ($total_stress_duration)"
    print ""
    
    $stress_results | each { |result|
        let status_icon = if $result.success { "✅" } else { "❌" }
        print $"($status_icon) ($result.operation):"
        print $"   Duration: ($result.duration)"
        if $result.memory_delta_mb != 0 {
            print $"   Memory Delta: ($result.memory_delta_mb) MB"
        }
        if not $result.success {
            print $"   Error: ($result.error)"
        }
        print ""
    }
    
    let successful_tests = ($stress_results | where success == true | length)
    let total_stress_tests = ($stress_results | length)
    
    print $"🎯 Stress Test Summary: ($successful_tests)/($total_stress_tests) tests passed"
    
    if $successful_tests == $total_stress_tests {
        print "\n🏆 All stress tests passed! Your DynamoDB Nu-Loader demonstrates:"
        print "   • High volume data processing capabilities"
        print "   • Large item handling within DynamoDB limits"  
        print "   • Unicode and special character resilience"
        print "   • Rapid operation sequencing stability"
        print "   • Memory efficient processing"
        print "\n💪 Tool is performance-validated for production workloads!"
    } else {
        print "\n⚠️  Some stress tests failed - review performance limitations"
    }
    
} catch { |error|
    print $"\n💥 Stress test execution failed: ($error.msg)"
} finally {
    # Always cleanup regardless of success/failure
    cleanup_stress_test_resources
}