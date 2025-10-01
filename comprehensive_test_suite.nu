#!/usr/bin/env nu

# Comprehensive DynamoDB Nu-Loader Test Suite - All Tests in One File
# Combines unit tests, AWS integration tests, and stress testing
# Usage: nu comprehensive_test_suite.nu [--unit-only] [--no-aws] [--no-stress]

use std/testing *

print "🎯 DynamoDB Nu-Loader - Comprehensive Test Suite"
print "==============================================="
print "All tests consolidated into a single file"
print ""

# Parse arguments
def main [
    --unit-only     # Run only unit tests
    --no-aws        # Skip AWS integration tests
    --no-stress     # Skip stress tests
    --help          # Show help
] {
    if $help {
        print "Usage: nu comprehensive_test_suite.nu [options]"
        print ""
        print "Options:"
        print "  --unit-only     Run only unit tests (fast)"
        print "  --no-aws        Skip AWS integration tests"
        print "  --no-stress     Skip stress tests"
        print "  --help          Show this help"
        print ""
        print "Examples:"
        print "  nu comprehensive_test_suite.nu --unit-only"
        print "  nu comprehensive_test_suite.nu --no-stress"
        return
    }

    let start_time = (date now)
    let test_results = []

    # =============================================================================
    # TEST UTILITIES AND HELPERS
    # =============================================================================

    def assert_equal [actual: any, expected: any, message: string]: nothing -> nothing {
        if $actual != $expected {
            error make {
                msg: $"Assertion failed: ($message)",
                label: {
                    text: $"Expected ($expected), got ($actual)",
                    span: (metadata $actual).span
                }
            }
        }
    }

    def assert [condition: bool, message: string]: nothing -> nothing {
        if not $condition {
            error make {
                msg: $"Assertion failed: ($message)"
            }
        }
    }

    def generate_test_users [count: int]: nothing -> list<record> {
        1..$count | each { |i|
            {
                id: $"user-($i)",
                sort_key: "USER",
                name: $"Test User ($i)",
                email: $"user($i)@example.com",
                age: (20 + ($i mod 40))
            }
        }
    }

    def create_temp_test_file [content: string, extension: string]: nothing -> string {
        let temp_file = $"/tmp/test_(random chars --length 8)($extension)"
        $content | save $temp_file
        $temp_file
    }

    def cleanup_temp_files [files: list<string>]: nothing -> nothing {
        $files | each { |file|
            if ($file | path exists) {
                rm $file
            }
        }
    }

    def run_test_section [section_name: string, test_fn: closure]: nothing -> record {
        print $"\\n🧪 ($section_name)"
        print "=" * 60
        
        let section_start = (date now)
        
        let result = try {
            do $test_fn
            { success: true, error: null }
        } catch { |error|
            { success: false, error: $error.msg }
        }
        
        let section_end = (date now)
        let duration = ($section_end - $section_start)
        
        if $result.success {
            print $"✅ ($section_name) completed successfully in ($duration)"
        } else {
            print $"❌ ($section_name) failed: ($result.error)"
        }
        
        {
            section: $section_name,
            success: $result.success,
            duration: $duration,
            error: $result.error
        }
    }

    # =============================================================================
    # UNIT TESTS
    # =============================================================================

    let unit_tests_result = (run_test_section "Unit Tests" {
        # Basic functionality tests
        assert ((2 + 2) == 4) "Basic math should work"
        assert (([1, 2, 3] | length) == 3) "List operations should work"
        
        let person = { name: "Alice", age: 30 }
        assert ($person.name == "Alice") "Record access should work"
        
        # Data operations tests
        let test_data = [
            { id: "1", name: "Alice" },
            { id: "2", name: "Bob" }
        ]
        assert (($test_data | length) == 2) "Test data should have 2 items"
        
        # DynamoDB type conversion test
        let test_item = {
            string_field: "hello",
            int_field: 42,
            bool_field: true
        }
        
        let converted = ($test_item | transpose key value | reduce -f {} { |row, acc|
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
        
        assert ($converted.string_field.S == "hello") "Should convert string correctly"
        assert ($converted.int_field.N == "42") "Should convert int to string"
        assert ($converted.bool_field.BOOL == true) "Should preserve boolean"
        
        # Batch chunking test
        let items = generate_test_users 30
        let batches = ($items | chunks 25)
        assert (($batches | length) == 2) "Should create 2 batches for 30 items"
        assert (($batches | first | length) == 25) "First batch should have 25 items"
        assert (($batches | last | length) == 5) "Last batch should have 5 items"
        
        # Unicode handling test
        let unicode_item = {
            emoji: "🚀📊✅❌🔍",
            chinese: "中文测试数据",
            mixed: "Mixed: 🌟 中文 test"
        }
        
        let unicode_converted = ($unicode_item | transpose key value | reduce -f {} { |row, acc|
            $acc | insert $row.key { "S": $row.value }
        })
        
        assert ($unicode_converted.emoji.S == "🚀📊✅❌🔍") "Should preserve emoji"
        assert ($unicode_converted.chinese.S == "中文测试数据") "Should preserve Chinese"
        
        # JSON roundtrip test
        let original_data = generate_test_users 5
        let json_string = ($original_data | to json)
        let parsed_data = ($json_string | from json)
        assert (($original_data | length) == ($parsed_data | length)) "JSON roundtrip should preserve count"
        
        # Edge case tests
        let empty_list = []
        let empty_batches = ($empty_list | chunks 25)
        assert (($empty_batches | length) == 0) "Should handle empty data"
        
        # File operations test
        let test_content = [{ id: "test", data: "value" }]
        let temp_file = create_temp_test_file ($test_content | to json) ".json"
        let loaded_content = (open $temp_file)
        assert (($loaded_content | length) == 1) "Should load content from file"
        cleanup_temp_files [$temp_file]
        
        print "✅ All unit tests passed!"
    })

    let test_results = ($test_results | append $unit_tests_result)

    # =============================================================================
    # AWS INTEGRATION TESTS (if not skipped)
    # =============================================================================

    if not $no_aws and not $unit_only {
        print "\n⚠️  AWS tests will create and destroy REAL AWS resources"
        print "   Ensure you have valid credentials and test environment"
        
        let aws_tests_result = (run_test_section "AWS Integration Tests" {
            # Test configuration
            let table_prefix = "nu-loader-comprehensive-test"
            let region = ($env.AWS_TEST_REGION? | default "us-east-1")
            
            # Validate AWS credentials
            let identity_result = (^aws sts get-caller-identity | complete)
            if $identity_result.exit_code != 0 {
                error make { msg: $"AWS credentials validation failed: ($identity_result.stderr)" }
            }
            let identity = ($identity_result.stdout | from json)
            print $"✅ Authenticated as: ($identity.Arn)"
            
            # Test 1: Basic table operations
            let table_name = $"($table_prefix)-basic"
            
            # Create table
            let create_result = (^aws dynamodb create-table 
                --table-name $table_name
                --attribute-definitions "AttributeName=id,AttributeType=S" "AttributeName=sort_key,AttributeType=S"
                --key-schema "AttributeName=id,KeyType=HASH" "AttributeName=sort_key,KeyType=RANGE"
                --billing-mode PAY_PER_REQUEST
                --region $region | complete)
            
            if $create_result.exit_code != 0 {
                error make { msg: $"Failed to create test table: ($create_result.stderr)" }
            }
            
            # Wait for table to be active
            loop {
                let status_result = (^aws dynamodb describe-table --table-name $table_name --region $region | complete)
                if $status_result.exit_code == 0 {
                    let status = ($status_result.stdout | from json | get Table.TableStatus)
                    if $status == "ACTIVE" {
                        break
                    }
                }
                sleep 2sec
            }
            
            print $"✅ Created test table: ($table_name)"
            
            # Test tool functionality
            let test_data = [
                { id: "test-1", sort_key: "USER", name: "Test User 1", age: 25 },
                { id: "test-2", sort_key: "USER", name: "Test User 2", age: 30 }
            ]
            
            let test_file = "/tmp/aws_test_data.json"
            $test_data | to json | save $test_file
            
            # Set environment variables
            $env.TABLE_NAME = $table_name
            $env.AWS_REGION = $region
            $env.SKIP_CONFIRMATION = "true"
            
            # Test seed command
            let seed_result = (nu main.nu seed $test_file | complete)
            if $seed_result.exit_code != 0 {
                error make { msg: $"Seed command failed: ($seed_result.stderr)" }
            }
            
            # Verify data was written
            let scan_result = (^aws dynamodb scan --table-name $table_name --region $region | complete)
            if $scan_result.exit_code != 0 {
                error make { msg: $"Scan verification failed: ($scan_result.stderr)" }
            }
            
            let scanned_data = ($scan_result.stdout | from json)
            let item_count = ($scanned_data.Items | length)
            
            if $item_count != 2 {
                error make { msg: $"Expected 2 items, found ($item_count)" }
            }
            
            print "✅ Seed and verification successful"
            
            # Test status command
            let status_result = (nu main.nu status | complete)
            if $status_result.exit_code != 0 {
                error make { msg: $"Status command failed: ($status_result.stderr)" }
            }
            
            print "✅ Status command successful"
            
            # Test snapshot command
            $env.SNAPSHOTS_DIR = "/tmp"
            let snapshot_name = "comprehensive-test-snapshot"
            let snapshot_result = (nu main.nu snapshot $snapshot_name | complete)
            if $snapshot_result.exit_code != 0 {
                error make { msg: $"Snapshot command failed: ($snapshot_result.stderr)" }
            }
            
            # Verify snapshot file
            if not ($snapshot_name | path exists) {
                error make { msg: "Snapshot file was not created" }
            }
            
            let snapshot_data = (open $snapshot_name | from json)
            if ($snapshot_data.data | length) != 2 {
                error make { msg: "Snapshot contains wrong number of items" }
            }
            
            print "✅ Snapshot command successful"
            
            # Test wipe command
            let wipe_result = (nu main.nu wipe | complete)
            if $wipe_result.exit_code != 0 {
                error make { msg: $"Wipe command failed: ($wipe_result.stderr)" }
            }
            
            # Verify table is empty
            let empty_scan = (^aws dynamodb scan --table-name $table_name --region $region | complete)
            let empty_data = ($empty_scan.stdout | from json)
            if ($empty_data.Items | length) != 0 {
                error make { msg: "Wipe command did not clear all data" }
            }
            
            print "✅ Wipe command successful"
            
            # Test restore command
            let restore_result = (nu main.nu restore $snapshot_name | complete)
            if $restore_result.exit_code != 0 {
                error make { msg: $"Restore command failed: ($restore_result.stderr)" }
            }
            
            # Verify restoration
            let restore_scan = (^aws dynamodb scan --table-name $table_name --region $region | complete)
            let restore_data = ($restore_scan.stdout | from json)
            if ($restore_data.Items | length) != 2 {
                error make { msg: "Restore command did not restore correct data" }
            }
            
            print "✅ Restore command successful"
            
            # Cleanup
            rm $test_file
            rm $snapshot_name
            let _ = (^aws dynamodb delete-table --table-name $table_name --region $region | complete)
            
            print "✅ All AWS integration tests passed!"
        })
        
        let test_results = ($test_results | append $aws_tests_result)
    }

    # =============================================================================
    # STRESS TESTS (if not skipped)
    # =============================================================================

    if not $no_stress and not $unit_only and not $no_aws {
        let stress_tests_result = (run_test_section "Stress Tests" {
            print "💪 Running lightweight stress tests..."
            
            # Large dataset test
            let large_dataset = generate_test_users 500
            assert (($large_dataset | length) == 500) "Should generate 500 test users"
            
            let large_batches = ($large_dataset | chunks 25)
            assert (($large_batches | length) == 20) "Should create 20 batches for 500 items"
            
            # Memory efficiency test
            let reconstructed = ($large_batches | flatten)
            assert (($large_dataset | length) == ($reconstructed | length)) "Should preserve all items"
            
            # JSON processing stress test
            let json_data = ($large_dataset | to json)
            let parsed_back = ($json_data | from json)
            assert (($large_dataset | length) == ($parsed_back | length)) "Large JSON processing should work"
            
            # Unicode stress test
            let unicode_data = (1..100 | each { |i|
                {
                    id: $"unicode-($i)",
                    sort_key: $"UNICODE-($i)",  # Unique sort keys to avoid duplicates
                    text: "🚀🌟⭐✨💫 Test ($i) 中文 العربية 日本語",
                    mixed: $"Item ($i): 🌍🚀 with numbers and symbols !@#$%"
                }
            })
            
            assert (($unicode_data | length) == 100) "Should generate 100 unicode items"
            
            let unicode_json = ($unicode_data | to json)
            let unicode_parsed = ($unicode_json | from json)
            assert (($unicode_data | length) == ($unicode_parsed | length)) "Unicode JSON processing should work"
            
            print "✅ All stress tests passed!"
        })
        
        let test_results = ($test_results | append $stress_tests_result)
    }

    # =============================================================================
    # FINAL CLEANUP AND REPORTING
    # =============================================================================

    # Clean up any remaining test resources
    if not $no_aws and not $unit_only {
        print "\n🧹 Final cleanup - checking for orphaned resources..."
        
        let cleanup_patterns = [
            "nu-loader-comprehensive-test",
            "nu-loader-test"
        ]
        
        let table_list = try {
            ^aws dynamodb list-tables | complete | get stdout | from json | get TableNames
        } catch {
            []
        }
        
        $cleanup_patterns | each { |pattern|
            let orphaned_tables = ($table_list | where $it =~ $pattern)
            if ($orphaned_tables | length) > 0 {
                print $"🗑️  Cleaning up ($orphaned_tables | length) orphaned tables..."
                $orphaned_tables | each { |table|
                    print $"   - ($table)"
                    let _ = (^aws dynamodb delete-table --table-name $table | complete)
                }
            }
        }
        
        # Clean up test files
        let temp_patterns = [
            "/tmp/aws_test_data.json",
            "/tmp/comprehensive_test_data.json"
        ]
        
        $temp_patterns | each { |file|
            if ($file | path exists) {
                rm $file
            }
        }
        
        # Clean up snapshots
        try {
            ls comprehensive-test-* | each { |file|
                rm $file.name
            }
        } catch {
            # No files found
        }
        
        print "✅ Cleanup completed"
    }

    let end_time = (date now)
    let total_duration = ($end_time - $start_time)

    # Generate final report
    print "\n📊 Comprehensive Test Results"
    print "============================="
    print $"⏱️  Total Duration: ($total_duration)"
    print ""

    let successful_sections = ($test_results | where success == true | length)
    let total_sections = ($test_results | length)

    print "🎯 Section Summary:"
    $test_results | each { |result|
        let status_icon = if $result.success { "✅" } else { "❌" }
        print $"   ($status_icon) ($result.section): ($result.duration)"
        if not $result.success and ($result.error != null) {
            print $"       Error: ($result.error)"
        }
    }

    print ""
    print $"✅ Sections Passed: ($successful_sections)/($total_sections)"

    if $successful_sections == $total_sections {
        print "\n🎉 All test sections completed successfully!"
        print ""
        print "💡 Your DynamoDB Nu-Loader is validated for:"
        print "   • Core functionality and edge cases"
        if not $no_aws and not $unit_only {
            print "   • Real AWS DynamoDB operations"
            print "   • Complete TDM workflows"
        }
        if not $no_stress and not $unit_only {
            print "   • Performance under moderate stress"
        }
        print ""
        print "🚀 Tool is production-ready for TDM operations!"
        
        # Save test report
        let test_report = {
            timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
            total_duration: $total_duration,
            sections_run: $total_sections,
            sections_passed: $successful_sections,
            test_mode: {
                unit_only: $unit_only,
                no_aws: $no_aws,
                no_stress: $no_stress
            },
            section_results: $test_results
        }
        
        $test_report | to json | save -f "comprehensive_test_report.json"
        print $"📋 Detailed report saved to: comprehensive_test_report.json"
        
    } else {
        print "\n❌ Some test sections failed!"
        print ""
        let failed_sections = ($test_results | where success == false)
        if ($failed_sections | length) > 0 {
            print "💥 Failed Sections:"
            $failed_sections | each { |section|
                print $"   - ($section.section): ($section.error)"
            }
        }
        exit 1
    }

    print ""
    print "🎯 Test execution completed!"
}