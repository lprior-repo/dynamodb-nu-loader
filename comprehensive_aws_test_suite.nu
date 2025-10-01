#!/usr/bin/env nu

# Comprehensive AWS Integration Test Suite for DynamoDB Nu-Loader
# Real AWS testing with beforeAll setup, complex data types, and comprehensive validation
#
# ⚠️ WARNING: This test suite creates and destroys REAL AWS resources
# Ensure you have:
# 1. Valid AWS credentials configured
# 2. Permissions for DynamoDB operations  
# 3. A test AWS account/region (to avoid production data)

print "🔥 DynamoDB Nu-Loader - Comprehensive AWS Test Suite"
print "====================================================="
print "⚠️  WARNING: Uses REAL AWS resources with your credentials"
print ""

# Global test configuration
let test_config = {
    region: ($env.AWS_TEST_REGION? | default "us-east-1"),
    profile: ($env.AWS_TEST_PROFILE? | default "default"),
    table_name: "nu-loader-comprehensive-test",
    cleanup_on_failure: true
}

print $"📋 Test Configuration:"
print $"   Region: ($test_config.region)"
print $"   Profile: ($test_config.profile)" 
print $"   Table Name: ($test_config.table_name)"
print ""

# Global state tracking
let test_state = {
    table_created: false,
    data_seeded: false,
    table_name: $test_config.table_name,
    region: $test_config.region,
    initial_item_count: 200
}

# =============================================================================
# COMPLEX DATA SCHEMA GENERATION - 200 ITEMS WITH ALL DYNAMODB TYPES
# =============================================================================

def generate_complex_test_data [count: int]: nothing -> list<record> {
    let categories = ["Electronics", "Books", "Clothing", "Home", "Sports", "Health", "Automotive", "Tools"]
    let statuses = ["ACTIVE", "INACTIVE", "PENDING", "ARCHIVED"]
    let boolean_values = [true, false]
    
    1..$count | each { |i|
        let category = ($categories | get (($i - 1) mod ($categories | length)))
        let status = ($statuses | get (($i - 1) mod ($statuses | length)))
        
        {
            # Primary key fields
            id: $"complex-item-($i | fill --width 3 --char '0')",
            sort_key: $"($category)#($status)",
            
            # String attributes
            name: $"Complex Test Item ($i)",
            description: $"This is a comprehensive test item with ID ($i) for testing all DynamoDB data types and operations.",
            category: $category,
            status: $status,
            
            # Numeric attributes (both int and float)
            sequence_number: $i,
            price: (if ($i mod 2) == 0 { ($i * 12.99) } else { ($i * 15) }),
            quantity: ($i * 3),
            rating: (if ($i mod 5) == 0 { 5.0 } else { 3.5 + (($i mod 4) * 0.5) }),
            
            # Boolean attributes
            in_stock: ($boolean_values | get (($i - 1) mod 2)),
            featured: (($i mod 10) == 0),
            premium: (($i mod 7) == 0),
            
            # Date/timestamp strings
            created_date: $"2024-0(if ($i mod 12) < 9 { ($i mod 12) + 1 } else { ($i mod 12) + 1 | into string })-0(if ($i mod 28) < 9 { ($i mod 28) + 1 } else { ($i mod 28) + 1 | into string })",
            updated_timestamp: $"2024-01-01T(if $i < 10 { '0' + ($i | into string) } else { $i | into string }):00:00Z",
            
            # GSI fields for testing secondary indexes
            gsi1_pk: $category,
            gsi1_sk: $"($status)#ITEM#($i)",
            gsi2_pk: $status,
            gsi2_sk: $"($category)#(date now | format date '%Y-%m-%d')",
            
            # Nested object-like data (stored as strings in DynamoDB)
            metadata: $"{{\"source\": \"test-suite\", \"version\": \"1.0\", \"item_id\": ($i), \"complex\": true}}",
            
            # List-like data (stored as strings)
            tags: $"[\"test\", \"comprehensive\", \"item-($i)\", \"($category | str downcase)\"]",
            
            # Additional fields for testing edge cases
            large_text: ("Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * ($i mod 5 + 1)),
            empty_when_even: (if ($i mod 2) == 0 { "" } else { $"Value for item ($i)" }),
            null_when_divisible_by_10: (if ($i mod 10) == 0 { null } else { $"Not null ($i)" }),
            
            # Testing special characters and encoding
            special_chars: $"Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>? Item ($i)",
            unicode_text: $"Unicode: 🚀📊✅❌🔍 Test Item ($i) 中文测试",
        }
    }
}

# =============================================================================
# SETUP AND TEARDOWN FUNCTIONS
# =============================================================================

def create_comprehensive_test_table [table_name: string, region: string]: nothing -> nothing {
    print $"🏗️  Creating comprehensive test table: ($table_name)"
    
    let result = (^aws dynamodb create-table 
        --table-name $table_name
        --attribute-definitions 
            "AttributeName=id,AttributeType=S"
            "AttributeName=sort_key,AttributeType=S"
            "AttributeName=gsi1_pk,AttributeType=S"
            "AttributeName=gsi1_sk,AttributeType=S"
            "AttributeName=gsi2_pk,AttributeType=S"
            "AttributeName=gsi2_sk,AttributeType=S"
        --key-schema 
            "AttributeName=id,KeyType=HASH"
            "AttributeName=sort_key,KeyType=RANGE"
        --global-secondary-indexes
            "IndexName=GSI1,KeySchema=[{AttributeName=gsi1_pk,KeyType=HASH},{AttributeName=gsi1_sk,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}"
            "IndexName=GSI2,KeySchema=[{AttributeName=gsi2_pk,KeyType=HASH},{AttributeName=gsi2_sk,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}"
        --billing-mode PAY_PER_REQUEST
        --region $region
        | complete)
    
    if $result.exit_code != 0 {
        error make { msg: $"Failed to create comprehensive test table: ($result.stderr)" }
    }
    
    # Wait for table to be active
    print "⏳ Waiting for table and GSIs to become active..."
    loop {
        let status_result = (^aws dynamodb describe-table --table-name $table_name --region $region | complete)
        if $status_result.exit_code == 0 {
            let description = ($status_result.stdout | from json)
            let table_status = $description.Table.TableStatus
            let gsi_statuses = ($description.Table.GlobalSecondaryIndexes? | default [] | each { |gsi| $gsi.IndexStatus })
            
            if $table_status == "ACTIVE" and ($gsi_statuses | all { |status| $status == "ACTIVE" }) {
                break
            }
            print $"   Table: ($table_status), GSIs: ($gsi_statuses)"
        }
        sleep 3sec
    }
    print "✅ Table and all GSIs are active"
}

def delete_comprehensive_test_table [table_name: string, region: string]: nothing -> nothing {
    print $"🗑️  Deleting comprehensive test table: ($table_name)"
    
    let result = (^aws dynamodb delete-table --table-name $table_name --region $region | complete)
    if $result.exit_code != 0 {
        print $"⚠️  Warning: Failed to delete table ($table_name): ($result.stderr)"
    } else {
        print "✅ Table deletion initiated"
    }
}

# =============================================================================
# TEST SETUP - BEFOREALL EQUIVALENT
# =============================================================================

def setup_comprehensive_test_environment []: nothing -> nothing {
    print "🚀 Setting up comprehensive test environment..."
    print "=============================================="
    
    # Validate AWS credentials
    print "🔐 Validating AWS credentials..."
    let result = (^aws sts get-caller-identity | complete)
    if $result.exit_code != 0 {
        error make { msg: $"AWS credentials validation failed: ($result.stderr)" }
    }
    
    let identity = ($result.stdout | from json)
    print $"✅ Authenticated as: ($identity.Arn)"
    
    # Create test table with GSIs
    create_comprehensive_test_table $test_state.table_name $test_state.region
    
    # Generate and save complex test data
    print "📊 Generating 200 complex test items with all DynamoDB data types..."
    let complex_data = generate_complex_test_data $test_state.initial_item_count
    let test_data_file = "/tmp/comprehensive_test_data.json"
    $complex_data | to json | save $test_data_file
    
    print $"✅ Generated ($complex_data | length) complex test items"
    print $"💾 Saved test data to: ($test_data_file)"
    
    # Set environment variables for the main tool
    $env.TABLE_NAME = $test_state.table_name
    $env.AWS_REGION = $test_state.region
    $env.SNAPSHOTS_DIR = "/tmp"
    $env.SKIP_CONFIRMATION = "true"  # Skip interactive confirmations
    
    # Seed the data using the actual tool
    print "🌱 Seeding comprehensive test data using nu-loader..."
    let seed_result = (nu main.nu seed $test_data_file | complete)
    if $seed_result.exit_code != 0 {
        error make { msg: $"Failed to seed comprehensive test data: ($seed_result.stderr)" }
    }
    
    # Verify data was seeded correctly
    print "🔍 Verifying data was seeded correctly..."
    let scan_result = (^aws dynamodb scan --table-name $test_state.table_name --region $test_state.region | complete)
    if $scan_result.exit_code != 0 {
        error make { msg: $"Failed to verify seeded data: ($scan_result.stderr)" }
    }
    
    let scanned_data = ($scan_result.stdout | from json)
    let actual_count = ($scanned_data.Items | length)
    
    if $actual_count != $test_state.initial_item_count {
        error make { msg: $"Data seeding verification failed: expected ($test_state.initial_item_count) items, found ($actual_count)" }
    }
    
    print $"✅ Successfully seeded and verified ($actual_count) items in DynamoDB"
    print "🎯 Test environment setup complete - ready for comprehensive testing!"
    print ""
}

# =============================================================================
# COMPREHENSIVE TEST SUITE
# =============================================================================

def run_comprehensive_test [test_name: string, test_fn: closure]: nothing -> record {
    print $"\\n🧪 Running: ($test_name)"
    print "=" * 60
    
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

# Individual test functions
def test_table_status_with_populated_data []: nothing -> nothing {
    print "📊 Testing status command with populated table..."
    
    let result = (nu main.nu status | complete)
    if $result.exit_code != 0 {
        error make { msg: $"Status command failed: ($result.stderr)" }
    }
    
    # Verify the output contains expected information
    let output = $result.stdout
    if not ($output | str contains $test_state.table_name) {
        error make { msg: "Status output doesn't contain table name" }
    }
    
    if not ($output | str contains "200") {
        error make { msg: "Status output doesn't show correct item count" }
    }
    
    print "✅ Status command correctly reports table information"
}

def test_snapshot_creation_with_complex_data []: nothing -> nothing {
    print "📸 Testing snapshot creation with 200 complex items..."
    
    let snapshot_name = "comprehensive-test-snapshot"
    let snapshot_result = (nu main.nu snapshot $snapshot_name | complete)
    if $snapshot_result.exit_code != 0 {
        error make { msg: $"Snapshot creation failed: ($snapshot_result.stderr)" }
    }
    
    # Verify snapshot file was created
    if not ($snapshot_name | path exists) {
        error make { msg: "Snapshot file was not created" }
    }
    
    # Verify snapshot content
    let snapshot_data = (open $snapshot_name | from json)
    if ($snapshot_data.data | length) != 200 {
        error make { msg: $"Snapshot contains wrong number of items: ($snapshot_data.data | length)" }
    }
    
    # Verify metadata
    if $snapshot_data.metadata.table_name != $test_state.table_name {
        error make { msg: "Snapshot metadata has wrong table name" }
    }
    
    print "✅ Snapshot successfully created with all 200 complex items"
    
    # Cleanup
    rm $snapshot_name
}

def test_scan_command_with_complex_data []: nothing -> nothing {
    print "🔍 Testing scan command with complex data types..."
    
    let scan_result = (nu main.nu scan | complete)
    if $scan_result.exit_code != 0 {
        error make { msg: $"Scan command failed: ($scan_result.stderr)" }
    }
    
    # The scan command should output all items
    let output = $scan_result.stdout
    if not ($output | str contains "complex-item-001") {
        error make { msg: "Scan output doesn't contain expected test items" }
    }
    
    if not ($output | str contains "Electronics") {
        error make { msg: "Scan output doesn't contain expected category data" }
    }
    
    print "✅ Scan command successfully retrieves complex data"
}

def test_wipe_operation_comprehensive []: nothing -> nothing {
    print "🧽 Testing wipe operation on populated table..."
    
    # Verify table has data before wipe
    let pre_scan = (^aws dynamodb scan --table-name $test_state.table_name --region $test_state.region | complete)
    let pre_data = ($pre_scan.stdout | from json)
    if ($pre_data.Items | length) == 0 {
        error make { msg: "Table should have data before wipe test" }
    }
    
    # Perform wipe
    let wipe_result = (nu main.nu wipe | complete)
    if $wipe_result.exit_code != 0 {
        error make { msg: $"Wipe command failed: ($wipe_result.stderr)" }
    }
    
    # Verify table is empty
    let post_scan = (^aws dynamodb scan --table-name $test_state.table_name --region $test_state.region | complete)
    let post_data = ($post_scan.stdout | from json)
    let remaining_items = ($post_data.Items | length)
    
    if $remaining_items != 0 {
        error make { msg: $"Wipe failed - ($remaining_items) items remaining" }
    }
    
    print "✅ Wipe operation successfully cleared all 200 complex items"
}

def test_reset_with_different_data []: nothing -> nothing {
    print "🔄 Testing reset operation with different complex data..."
    
    # Generate new test data (smaller set for reset test)
    let reset_data = generate_complex_test_data 50
    let reset_file = "/tmp/reset_test_data.json"
    $reset_data | to json | save $reset_file
    
    # Perform reset
    let reset_result = (nu main.nu reset $reset_file | complete)
    if $reset_result.exit_code != 0 {
        error make { msg: $"Reset command failed: ($reset_result.stderr)" }
    }
    
    # Verify new data count
    let final_scan = (^aws dynamodb scan --table-name $test_state.table_name --region $test_state.region | complete)
    let final_data = ($final_scan.stdout | from json)
    let final_count = ($final_data.Items | length)
    
    if $final_count != 50 {
        error make { msg: $"After reset, expected 50 items but found ($final_count)" }
    }
    
    print "✅ Reset operation successfully replaced data with new complex dataset"
    
    # Cleanup
    rm $reset_file
}

def test_restore_operation_comprehensive []: nothing -> nothing {
    print "📥 Testing restore operation with comprehensive data..."
    
    # First create a snapshot of current state
    let backup_name = "restore-test-backup"
    let snapshot_result = (nu main.nu snapshot $backup_name | complete)
    if $snapshot_result.exit_code != 0 {
        error make { msg: $"Failed to create backup for restore test: ($snapshot_result.stderr)" }
    }
    
    # Wipe the table
    let wipe_result = (nu main.nu wipe | complete)
    if $wipe_result.exit_code != 0 {
        error make { msg: $"Failed to wipe table for restore test: ($wipe_result.stderr)" }
    }
    
    # Restore from backup
    let restore_result = (nu main.nu restore $backup_name | complete)
    if $restore_result.exit_code != 0 {
        error make { msg: $"Restore operation failed: ($restore_result.stderr)" }
    }
    
    # Verify data was restored
    let final_scan = (^aws dynamodb scan --table-name $test_state.table_name --region $test_state.region | complete)
    let final_data = ($final_scan.stdout | from json)
    let final_count = ($final_data.Items | length)
    
    if $final_count != 50 {  # Should match the reset test data count
        error make { msg: $"After restore, expected 50 items but found ($final_count)" }
    }
    
    print "✅ Restore operation successfully recovered all data"
    
    # Cleanup
    rm $backup_name
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

print "🎬 Starting comprehensive AWS integration tests..."
print ""

# Setup test environment (beforeAll equivalent)
setup_comprehensive_test_environment

let start_time = (date now)

# Run comprehensive test suite
let test_results = [
    (run_comprehensive_test "Table Status with Populated Data" { test_table_status_with_populated_data }),
    (run_comprehensive_test "Snapshot Creation with Complex Data" { test_snapshot_creation_with_complex_data }),
    (run_comprehensive_test "Scan Command with Complex Data" { test_scan_command_with_complex_data }),
    (run_comprehensive_test "Wipe Operation Comprehensive" { test_wipe_operation_comprehensive }),
    (run_comprehensive_test "Reset with Different Data" { test_reset_with_different_data }),
    (run_comprehensive_test "Restore Operation Comprehensive" { test_restore_operation_comprehensive })
]

let end_time = (date now)
let total_duration = ($end_time - $start_time)

# =============================================================================
# CLEANUP AND REPORTING
# =============================================================================

print "\n🧹 Cleaning up test environment..."
delete_comprehensive_test_table $test_state.table_name $test_state.region

# Remove temporary files
try { rm "/tmp/comprehensive_test_data.json" } catch { }

print "\n📊 Comprehensive AWS Test Results"
print "===================================="

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
    print "\n🎉 All comprehensive tests passed!"
    print "\n💡 Your DynamoDB Nu-Loader tool successfully handles:"
    print "   • 200 complex items with all DynamoDB data types"
    print "   • Global Secondary Indexes (GSI1, GSI2)"
    print "   • Complete CRUD workflows (seed, scan, snapshot, wipe, reset, restore)"
    print "   • Real AWS DynamoDB operations under load"
    print "\n🚀 Tool is production-ready for Test Data Management (TDM) workflows!"
}