#!/usr/bin/env nu

# Complete test suite runner for DynamoDB Nu-Loader
# Includes unit tests, integration tests, and AWS integration tests

print "🧪 DynamoDB Nu-Loader - Complete Test Suite"
print "============================================"
print ""

let start_time = (date now)

# Import nutest
use ../nutest/nutest

print "✅ Running basic verification test..."
let basic_result = try {
    nutest run-tests --path test_basic_functionality.nu --returns summary
} catch { |error|
    print $"❌ Basic tests failed: ($error.msg)"
    { total: 0, passed: 0, failed: 1, skipped: 0 }
}

print $"✅ Basic: ($basic_result.passed)/($basic_result.total) passed"

print "\n🔬 Running unit tests..."
let unit_result = try {
    nutest run-tests --path unit/ --returns summary --display terminal
} catch { |error|
    print $"❌ Unit tests failed: ($error.msg)"
    { total: 0, passed: 0, failed: 1, skipped: 0 }
}

print $"✅ Unit: ($unit_result.passed)/($unit_result.total) passed"

print "\n🔗 Running integration tests..."
let integration_result = try {
    nutest run-tests --path integration/ --returns summary --display terminal
} catch { |error|
    print $"❌ Integration tests failed: ($error.msg)"
    { total: 0, passed: 0, failed: 1, skipped: 0 }
}

print $"✅ Integration: ($integration_result.passed)/($integration_result.total) passed"

let end_time = (date now)
let duration = ($end_time - $start_time)

# Summary
let total_passed = ($basic_result.passed) + ($unit_result.passed) + ($integration_result.passed)
let total_tests = ($basic_result.total) + ($unit_result.total) + ($integration_result.total)
let total_failed = ($basic_result.failed) + ($unit_result.failed) + ($integration_result.failed)

print "\n📊 Test Summary"
print "==============="
print $"✅ Total Passed: ($total_passed)/($total_tests)"
print $"❌ Total Failed: ($total_failed)"
print $"⏱️  Duration: ($duration)"

if $total_failed == 0 {
    print "\n🎉 All tests passed! Your test infrastructure is working."
    print "\n💡 Next steps:"
    print "   1. Run AWS integration tests: nu tests/run_aws_integration_tests.nu"
    print "   2. Set up your AWS credentials for real testing"
    exit 0
} else {
    print $"\n⚠️  ($total_failed) tests failed - need investigation"
    exit 1
}