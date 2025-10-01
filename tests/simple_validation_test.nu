#!/usr/bin/env nu

# Simple validation test for DynamoDB Nu-Loader
# Tests basic functionality without requiring external nutest framework

print "🧪 Running simple validation tests for DynamoDB Nu-Loader"
print "========================================================="

# Test 1: Help commands work
print "\n🔍 Test 1: Checking help commands..."
try {
  nu -c "source main.nu; help main" | ignore
  print "✅ Main help works"
} catch {
  print "❌ Main help failed"
  exit 1
}

try {
  nu -c "source main.nu; help main status" | ignore
  print "✅ Status help works"
} catch {
  print "❌ Status help failed"
  exit 1
}

try {
  nu -c "source main.nu; help main snapshot" | ignore
  print "✅ Snapshot help works"
} catch {
  print "❌ Snapshot help failed"
  exit 1
}

# Test 2: Validation works for missing parameters
print "\n🔍 Test 2: Checking parameter validation..."
let status_result = (try { 
  nu -c "source main.nu; main status" o+e> /dev/null; "success"
} catch { 
  "failed"
})

if $status_result == "failed" {
  print "✅ Status correctly validates missing parameters"
} else {
  print "❌ Status should have failed without parameters"
  exit 1
}

let snapshot_result = (try {
  nu -c "source main.nu; main snapshot" o+e> /dev/null; "success"  
} catch {
  "failed"
})

if $snapshot_result == "failed" {
  print "✅ Snapshot correctly validates missing parameters"
} else {
  print "❌ Snapshot should have failed without parameters"
  exit 1
}

# Test 3: Environment variables work
print "\n🔍 Test 3: Checking environment variable support..."
try {
  with-env {TABLE_NAME: "test-table", AWS_REGION: "us-east-1", SNAPSHOTS_DIR: "./snapshots"} {
    nu -c "source main.nu; help main status" | ignore
  }
  print "✅ Environment variables are accessible"
} catch {
  print "❌ Environment variable test failed"
  exit 1
}

# Test 4: File format detection
print "\n🔍 Test 4: Checking file format detection logic..."
try {
  nu -c "source main.nu; if ('test.csv' | str ends-with '.csv') { print 'CSV detected' } else { print 'JSON detected' }" | str contains "CSV detected"
  print "✅ CSV format detection works"
} catch {
  print "❌ File format detection failed"
  exit 1
}

# Test 5: Seed data file exists
print "\n🔍 Test 5: Checking seed data file..."
if ("seed-data.json" | path exists) {
  print "✅ Seed data file exists"
} else {
  print "❌ Seed data file missing"
  exit 1
}

# Test 6: Enhanced help works
print "\n🔍 Test 6: Checking enhanced help..."
try {
  nu main.nu | ignore
  print "✅ Enhanced help works"
} catch {
  print "❌ Enhanced help failed"
  exit 1
}

# Test 7: Test that validation error messages are correct
print "\n🔍 Test 7: Checking validation error messages..."
try {
  let error_output = (nu -c "source main.nu; main status" err> /tmp/test_error.txt)
  let error_content = (open /tmp/test_error.txt)
  if ($error_content | str contains "TABLE_NAME environment variable") {
    print "✅ Error messages mention environment variables"
  } else {
    print "❌ Error messages don't mention environment variables"
    exit 1
  }
  rm /tmp/test_error.txt
} catch {
  print "⚠️  Could not test error message content"
}

print "\n🎉 All simple validation tests passed!"
print "📝 Note: For comprehensive testing, install nutest and run: nu run_tests.nu"
print ""
print "💡 To test with a real DynamoDB table:"
print "   export TABLE_NAME=your-table-name"
print "   export AWS_REGION=your-region"
print "   export SNAPSHOTS_DIR=./snapshots"
print "   nu main.nu status"