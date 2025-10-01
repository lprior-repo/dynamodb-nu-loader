#!/usr/bin/env nu

# Fixed Nutest Integration for DynamoDB Nu-Loader
# Uses proper nutest framework according to documentation

print "🧪 DynamoDB Nu-Loader Test Suite (Fixed Nutest Framework)"
print "=========================================================="
print ""

let start_time = (date now)

# Import nutest properly
use ../nutest/nutest

print "✅ Nutest framework imported successfully"

# Run unit tests with proper nutest commands
print "\n🔬 Running Unit Tests..."
print "========================"

let unit_results = try {
    nutest run-tests --path tests/unit/ --returns summary --display terminal
} catch { |error|
    print $"❌ Unit tests failed to run: ($error.msg)"
    { total: 0, passed: 0, failed: 1, skipped: 0 }
}

print "\n🔗 Running Integration Tests..."  
print "================================"

let integration_results = try {
    nutest run-tests --path tests/integration/ --returns summary --display terminal
} catch { |error|
    print $"❌ Integration tests failed to run: ($error.msg)"
    { total: 0, passed: 0, failed: 1, skipped: 0 }
}

let end_time = (date now)
let duration = ($end_time - $start_time)

print "\n📊 Test Summary"
print "==============="
print $"Unit Tests: ($unit_results.passed)/($unit_results.total) passed"
print $"Integration Tests: ($integration_results.passed)/($integration_results.total) passed"

let total_passed = ($unit_results.passed) + ($integration_results.passed)
let total_tests = ($unit_results.total) + ($integration_results.total)
let total_failed = ($unit_results.failed) + ($integration_results.failed)

print $"Total: ($total_passed)/($total_tests) passed"
print $"⏱️  Duration: ($duration)"

if $total_failed == 0 {
    print "\n🎉 All tests passed!"
    exit 0
} else {
    print $"\n⚠️  ($total_failed) tests failed"
    exit 1
}