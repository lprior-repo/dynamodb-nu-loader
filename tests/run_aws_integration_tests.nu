#!/usr/bin/env nu

# AWS Integration Test Suite for DynamoDB Nu-Loader
# Real AWS testing using user's credentials - like Terratest for TDM tools
#
# ⚠️ WARNING: This test suite creates and destroys REAL AWS resources
# Ensure you have:
# 1. Valid AWS credentials configured
# 2. Permissions for DynamoDB operations
# 3. A test AWS account/region (to avoid production data)

print "🔥 DynamoDB Nu-Loader - AWS Integration Test Suite"
print "================================================="
print "⚠️  WARNING: Uses REAL AWS resources with your credentials"
print ""

# Test configuration - MUST be different from production
let test_config = {
    region: ($env.AWS_TEST_REGION? | default "us-east-1"),
    profile: ($env.AWS_TEST_PROFILE? | default "default"),
    table_prefix: "nu-loader-test",
    cleanup_on_failure: true
}

print $"📋 Test Configuration:"
print $"   Region: ($test_config.region)"
print $"   Profile: ($test_config.profile)" 
print $"   Table Prefix: ($test_config.table_prefix)"
print ""

let start_time = (date now)
let test_results = []

# Test suite state management
def create_test_table [table_name: string, region: string]: nothing -> nothing {
    print $"🏗️  Creating test table: ($table_name)"
    
    let result = (^aws dynamodb create-table 
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
    
    if $result.exit_code != 0 {
        error make { msg: $"Failed to create test table: ($result.stderr)" }
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
        }
        sleep 2sec
    }
    print "✅ Table created and active"
}

def delete_test_table [table_name: string, region: string]: nothing -> nothing {
    print $"🗑️  Deleting test table: ($table_name)"
    
    let result = (^aws dynamodb delete-table --table-name $table_name --region $region | complete)
    if $result.exit_code != 0 {
        print $"⚠️  Warning: Failed to delete table ($table_name): ($result.stderr)"
    } else {
        print "✅ Table deleted"
    }
}

def run_test [test_name: string, test_fn: closure]: nothing -> record {
    print $"\n🧪 Running: ($test_name)"
    print "=" * 50
    
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

# AWS Integration Tests

def test_aws_credentials_validation []: nothing -> nothing {
    print "🔐 Validating AWS credentials..."
    
    let result = (^aws sts get-caller-identity | complete)
    if $result.exit_code != 0 {
        error make { msg: $"AWS credentials validation failed: ($result.stderr)" }
    }
    
    let identity = ($result.stdout | from json)
    print $"✅ Authenticated as: ($identity.Arn)"
}

def test_table_status_real_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-status-test"
    
    create_test_table $table_name $test_config.region
    
    try {
        # Test the actual status command
        print "📊 Testing status command with real table..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        let result = (nu main.nu status | complete)
        if $result.exit_code != 0 {
            error make { msg: $"Status command failed: ($result.stderr)" }
        }
        
        print "✅ Status command works with real AWS table"
        
    } catch { |error|
        delete_test_table $table_name $test_config.region
        error make { msg: $error.msg }
    }
    
    delete_test_table $table_name $test_config.region
}

def test_seed_and_scan_real_data []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-seed-test"
    
    create_test_table $table_name $test_config.region
    
    try {
        # Create test data file with unique name
        let test_data = [
            { id: "test-1", sort_key: "USER", name: "Integration Test User 1", age: 25 },
            { id: "test-2", sort_key: "USER", name: "Integration Test User 2", age: 30 },
            { id: "prod-1", sort_key: "PRODUCT", name: "Test Product", price: 19.99 }
        ]
        
        let test_file = $"/tmp/integration_test_data_(random chars --length 8).json"
        $test_data | to json | save $test_file
        
        # Test seeding real data
        print "🌱 Testing seed command with real AWS table..."
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        let seed_result = (nu main.nu seed $test_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Seed command failed: ($seed_result.stderr)" }
        }
        
        # Verify data was actually written to AWS
        print "🔍 Verifying data was written to DynamoDB..."
        let scan_result = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        if $scan_result.exit_code != 0 {
            error make { msg: $"AWS scan failed: ($scan_result.stderr)" }
        }
        
        let scanned_data = ($scan_result.stdout | from json)
        let item_count = ($scanned_data.Items | length)
        
        if $item_count != 3 {
            error make { msg: $"Expected 3 items, found ($item_count)" }
        }
        
        print $"✅ Successfully seeded and verified ($item_count) items in AWS DynamoDB"
        
        # Cleanup test file
        rm $test_file
        
    } catch { |error|
        delete_test_table $table_name $test_config.region
        error make { msg: $error.msg }
    }
    
    delete_test_table $table_name $test_config.region
}

def test_snapshot_and_restore_real_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-snapshot-test"
    
    create_test_table $table_name $test_config.region
    
    try {
        # First, add some data to snapshot
        let initial_data = [
            { id: "snap-1", sort_key: "DATA", value: "original", count: 1 },
            { id: "snap-2", sort_key: "DATA", value: "backup", count: 2 }
        ]
        
        let data_file = $"/tmp/snapshot_test_data_(random chars --length 8).json"
        $initial_data | to json | save $data_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        $env.SNAPSHOTS_DIR = "/tmp"
        
        # Seed initial data
        let seed_result = (nu main.nu seed $data_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Initial seed failed: ($seed_result.stderr)" }
        }
        
        # Create snapshot with unique name
        print "📸 Creating snapshot from real AWS table..."
        let snapshot_name = $"test-backup-(random chars --length 8)"
        let snapshot_result = (nu main.nu snapshot $snapshot_name | complete)
        if $snapshot_result.exit_code != 0 {
            error make { msg: $"Snapshot creation failed: ($snapshot_result.stderr)" }
        }
        
        # Verify snapshot file exists and has correct data
        # The snapshot command creates files in SNAPSHOTS_DIR, so check current directory
        # Look for the exact filename since custom names don't get .json extension
        let snapshot_file = $snapshot_name
        if not ($snapshot_file | path exists) {
            error make { msg: $"Snapshot file ($snapshot_file) was not created" }
        }
        let snapshot_data = (open $snapshot_file | from json)
        
        if ($snapshot_data.data | length) != 2 {
            error make { msg: $"Snapshot contains wrong number of items: ($snapshot_data.data | length)" }
        }
        
        # Test restore (wipe + reload)
        print "🔄 Testing restore from snapshot..."
        let restore_result = (nu main.nu restore $snapshot_file | complete)
        if $restore_result.exit_code != 0 {
            error make { msg: $"Restore failed: ($restore_result.stderr)" }
        }
        
        # Verify restoration worked
        let final_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let final_data = ($final_scan.stdout | from json)
        let final_count = ($final_data.Items | length)
        
        if $final_count != 2 {
            error make { msg: $"After restore, expected 2 items but found ($final_count)" }
        }
        
        print "✅ Snapshot and restore cycle completed successfully"
        
        # Cleanup
        rm $data_file
        rm $snapshot_file
        
    } catch { |error|
        delete_test_table $table_name $test_config.region
        error make { msg: $error.msg }
    }
    
    delete_test_table $table_name $test_config.region
}

def test_wipe_operation_real_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-wipe-test"
    
    create_test_table $table_name $test_config.region
    
    try {
        # Add data to wipe
        let test_data = [
            { id: "wipe-1", sort_key: "DATA", temp: true },
            { id: "wipe-2", sort_key: "DATA", temp: true },
            { id: "wipe-3", sort_key: "DATA", temp: true }
        ]
        
        let data_file = $"/tmp/wipe_test_data_(random chars --length 8).json"
        $test_data | to json | save $data_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Seed data first
        let seed_result = (nu main.nu seed $data_file | complete)
        if $seed_result.exit_code != 0 {
            error make { msg: $"Initial seed for wipe test failed: ($seed_result.stderr)" }
        }
        
        # Verify data exists before wipe
        let pre_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let pre_data = ($pre_scan.stdout | from json)
        if ($pre_data.Items | length) != 3 {
            error make { msg: "Data wasn't properly seeded before wipe test" }
        }
        
        # Test wipe (skip interactive confirmation for testing)
        print "🧽 Testing wipe operation..."
        # Use environment variable to bypass confirmation in tests
        $env.SKIP_CONFIRMATION = "true"
        let wipe_result = (nu main.nu wipe | complete)
        if $wipe_result.exit_code != 0 {
            error make { msg: $"Wipe command failed: ($wipe_result.stderr)" }
        }
        
        # Verify table is empty
        let post_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let post_data = ($post_scan.stdout | from json)
        let remaining_items = ($post_data.Items | length)
        
        if $remaining_items != 0 {
            error make { msg: $"Wipe failed - ($remaining_items) items remaining" }
        }
        
        print "✅ Wipe operation successfully cleared all data"
        
        # Cleanup
        rm $data_file
        
    } catch { |error|
        delete_test_table $table_name $test_config.region
        error make { msg: $error.msg }
    }
    
    delete_test_table $table_name $test_config.region
}

def test_reset_workflow_real_aws []: nothing -> nothing {
    let table_name = $"($test_config.table_prefix)-reset-test"
    
    create_test_table $table_name $test_config.region
    
    try {
        # Create initial and reset data
        let initial_data = [
            { id: "old-1", sort_key: "DATA", version: "v1" },
            { id: "old-2", sort_key: "DATA", version: "v1" }
        ]
        
        let reset_data = [
            { id: "new-1", sort_key: "DATA", version: "v2" },
            { id: "new-2", sort_key: "DATA", version: "v2" },
            { id: "new-3", sort_key: "DATA", version: "v2" }
        ]
        
        let initial_file = $"/tmp/initial_data_(random chars --length 8).json"
        let reset_file = $"/tmp/reset_data_(random chars --length 8).json"
        
        $initial_data | to json | save $initial_file
        $reset_data | to json | save $reset_file
        
        $env.TABLE_NAME = $table_name
        $env.AWS_REGION = $test_config.region
        
        # Load initial data
        let initial_seed = (nu main.nu seed $initial_file | complete)
        if $initial_seed.exit_code != 0 {
            error make { msg: $"Initial data load failed: ($initial_seed.stderr)" }
        }
        
        # Verify initial state
        let pre_reset_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let pre_reset_data = ($pre_reset_scan.stdout | from json)
        if ($pre_reset_data.Items | length) != 2 {
            error make { msg: "Initial data count incorrect" }
        }
        
        # Test reset (wipe + reload)
        print "🔄 Testing reset workflow (wipe + seed)..."
        # Use environment variable to bypass confirmation in tests
        $env.SKIP_CONFIRMATION = "true"
        let reset_result = (nu main.nu reset $reset_file | complete)
        if $reset_result.exit_code != 0 {
            error make { msg: $"Reset command failed: ($reset_result.stderr)" }
        }
        
        # Verify reset worked
        let post_reset_scan = (^aws dynamodb scan --table-name $table_name --region $test_config.region | complete)
        let post_reset_data = ($post_reset_scan.stdout | from json)
        let final_count = ($post_reset_data.Items | length)
        
        if $final_count != 3 {
            error make { msg: $"After reset, expected 3 items but found ($final_count)" }
        }
        
        # Verify it's the new data (check for v2)
        let has_v2_data = ($post_reset_data.Items | any { |item|
            ($item.version?.S? == "v2")
        })
        
        if not $has_v2_data {
            error make { msg: "Reset didn't load the new data - still has old data" }
        }
        
        print "✅ Reset workflow successfully replaced old data with new data"
        
        # Cleanup
        rm $initial_file
        rm $reset_file
        
    } catch { |error|
        delete_test_table $table_name $test_config.region
        error make { msg: $error.msg }
    }
    
    delete_test_table $table_name $test_config.region
}

# Main test execution
print "🚀 Starting AWS Integration Tests..."
print ""

# Run all integration tests
let test_results = [
    (run_test "AWS Credentials Validation" { test_aws_credentials_validation }),
    (run_test "Table Status with Real AWS" { test_table_status_real_aws }),
    (run_test "Seed and Scan Real Data" { test_seed_and_scan_real_data }),
    (run_test "Snapshot and Restore Real AWS" { test_snapshot_and_restore_real_aws }),
    (run_test "Wipe Operation Real AWS" { test_wipe_operation_real_aws }),
    (run_test "Reset Workflow Real AWS" { test_reset_workflow_real_aws })
]

let end_time = (date now)
let total_duration = ($end_time - $start_time)

# Test summary
# =============================================================================
# AFTERALL CLEANUP
# =============================================================================

def cleanup_integration_test_resources []: nothing -> nothing {
    print "\n🧹 Running afterAll cleanup for integration tests..."
    print "===================================================="
    
    # Clean up any remaining test tables
    let table_list = try {
        ^aws dynamodb list-tables --region $test_config.region | complete
    } catch {
        { exit_code: 1, stderr: "Failed to list tables" }
    }
    
    if $table_list.exit_code == 0 {
        let all_tables = ($table_list.stdout | from json | get TableNames)
        let integration_tables = ($all_tables | where $it =~ $test_config.table_prefix)
        
        if ($integration_tables | length) > 0 {
            print $"🗑️  Found ($integration_tables | length) orphaned test tables to clean up:"
            $integration_tables | each { |table|
                print $"   - Deleting: ($table)"
                try {
                    ^aws dynamodb delete-table --table-name $table --region $test_config.region | complete
                } catch {
                    print $"     ⚠️  Warning: Failed to delete ($table)"
                }
            }
        } else {
            print "✅ No orphaned test tables found"
        }
    }
    
    # Clean up any temporary test files
    let temp_files = [
        "/tmp/integration_test_data_*.json",
        "/tmp/snapshot_test_data_*.json", 
        "/tmp/wipe_test_data_*.json",
        "/tmp/initial_data_*.json",
        "/tmp/reset_data_*.json"
    ]
    
    print "📁 Cleaning up temporary test files..."
    $temp_files | each { |pattern|
        try {
            ls $pattern | each { |file|
                print $"   - Removing: ($file.name)"
                rm $file.name
            }
        } catch {
            # No files matching pattern - that's fine
        }
    }
    
    # Clean up any snapshot files from integration tests
    let snapshot_patterns = [
        "test-backup-*",
        "integration-snapshot-*",
        "restore-test-*"
    ]
    
    print "📸 Cleaning up integration test snapshots..."
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
    
    print "✅ Integration test cleanup completed"
}

# Always run cleanup, regardless of test results
cleanup_integration_test_resources

print "\n📊 AWS Integration Test Results"
print "================================"

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
    exit 1
} else {
    print "\n🎉 All AWS integration tests passed!"
    print "\n💡 Your DynamoDB Nu-Loader tool is working correctly with real AWS resources!"
}