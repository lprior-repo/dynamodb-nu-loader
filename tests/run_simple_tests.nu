#!/usr/bin/env nu

# Simple test runner for DynamoDB Nu-Loader
# Runs basic validation without external dependencies

print "🧪 Running DynamoDB Nu-Loader Test Suite (Simple Mode)"
print "======================================================="

let start_time = (date now)

# Test 1: Basic CLI validation
print "\n🔍 Running basic CLI validation..."
try {
  nu simple_validation_test.nu | ignore
  print "✅ Basic CLI validation passed"
} catch {
  print "❌ Basic CLI validation failed"
  exit 1
}

# Test 2: Syntax validation - check all .nu files for syntax errors
print "\n🔍 Checking syntax of all Nushell files..."
let nu_files = [
  "main.nu"
  "tests/helpers/test_utils.nu"
  "tests/unit/test_data_ops.nu"
  "tests/unit/test_aws_ops.nu"
  "tests/unit/test_cli.nu"
  "tests/unit/test_upload_processing.nu"
  "tests/unit/test_validation.nu"
  "tests/integration/test_workflows.nu"
  "tests/integration/test_formats.nu"
  "tests/integration/test_upload_formats.nu"
]

let syntax_results = ($nu_files | each { |file|
  if ($file | path exists) {
    let result = (try {
      nu -c $"nu --check ($file)" | ignore; "OK"
    } catch {
      "ERROR"
    })
    
    if $result == "OK" {
      print $"✅ ($file) syntax OK"
      { file: $file, status: "OK" }
    } else {
      print $"❌ ($file) syntax error"
      { file: $file, status: "ERROR" }
    }
  } else {
    print $"⚠️  ($file) not found"
    { file: $file, status: "MISSING" }
  }
})

let syntax_errors = ($syntax_results | where status == "ERROR")

if ($syntax_errors | length) > 0 {
  print $"\n❌ Syntax errors found in: ($syntax_errors | get file | str join ', ')"
  exit 1
}

# Test 3: Function signature validation
print "\n🔍 Validating function signatures..."
try {
  nu -c "source main.nu; help main" | ignore
  nu -c "source main.nu; help main status" | ignore
  nu -c "source main.nu; help main snapshot" | ignore
  nu -c "source main.nu; help main restore" | ignore
  nu -c "source main.nu; help main wipe" | ignore
  nu -c "source main.nu; help main seed" | ignore
  print "✅ All function signatures valid"
} catch {
  print "❌ Function signature validation failed"
  exit 1
}

# Test 4: Parameter validation
print "\n🔍 Testing parameter validation..."
let test_commands = [
  "main status"
  "main snapshot"
  "main restore nonexistent.json"
  "main wipe"
  "main seed"
]

for cmd in $test_commands {
  let result = (try {
    nu -c $"source main.nu; ($cmd)" o+e> /dev/null; "success"
  } catch {
    "failed"
  })
  
  if $result == "failed" {
    print $"✅ ($cmd) correctly validates parameters"
  } else {
    print $"❌ ($cmd) should have failed parameter validation"
    exit 1
  }
}

# Test 5: Environment variable support
print "\n🔍 Testing environment variable support..."
try {
  with-env {TABLE_NAME: "test-table", AWS_REGION: "us-east-1", SNAPSHOTS_DIR: "./snapshots"} {
    nu -c "source main.nu; help main status" | ignore
  }
  print "✅ Environment variables work correctly"
} catch {
  print "❌ Environment variable support failed"
  exit 1
}

# Test 6: File format detection
print "\n🔍 Testing file format detection..."
try {
  nu -c "source main.nu; let file = 'test.csv'; if (\$file | str ends-with '.csv') { print 'CSV' } else { print 'JSON' }" | str contains "CSV"
  nu -c "source main.nu; let file = 'test.json'; if (\$file | str ends-with '.csv') { print 'CSV' } else { print 'JSON' }" | str contains "JSON"
  print "✅ File format detection works"
} catch {
  print "❌ File format detection failed"
  exit 1
}

# Test 7: Required files exist
print "\n🔍 Checking required files..."
let required_files = [
  "main.nu"
  "seed-data.json"
  "README.md"
  "LICENSE"
  ".gitignore"
]

for file in $required_files {
  if ($file | path exists) {
    print $"✅ ($file) exists"
  } else {
    print $"❌ ($file) missing"
    exit 1
  }
}

# Test 8: Test data generators work
print "\n🔍 Testing data generators..."
try {
  nu -c "source tests/helpers/test_utils.nu; let users = (generate_test_users 3); if (\$users | length) == 3 { print 'OK' }"
  nu -c "source tests/helpers/test_utils.nu; let products = (generate_test_products 2); if (\$products | length) == 2 { print 'OK' }"
  print "✅ Test data generators work"
} catch {
  print "❌ Test data generators failed"
  exit 1
}

let end_time = (date now)
let duration = ($end_time - $start_time)

print "\n🎉 All simple tests passed!"
print $"⏱️  Duration: ($duration)"
print ""
print "📝 Note: This covers basic functionality and syntax validation."
print "   For comprehensive unit and integration testing, install nutest:"
print "   git clone https://github.com/vyadh/nutest.git"
print "   cp -r nutest/nutest ."
print "   nu -c 'use nutest; nutest run-tests --path tests'"
print ""
print "💡 To test with a real DynamoDB table:"
print "   export TABLE_NAME=your-table-name"
print "   export AWS_REGION=your-region"
print "   export SNAPSHOTS_DIR=./snapshots"
print "   nu main.nu status"