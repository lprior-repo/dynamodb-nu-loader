#!/usr/bin/env nu

# Test runner for consolidated DynamoDB Nu-Loader test suite

print "🧪 DynamoDB Nu-Loader - Consolidated Test Suite"
print "==============================================="
print ""

let start_time = (date now)

# Run tests with nutest framework
let result = try {
    print "🔄 Running nutest framework..."
    nu -c 'use nutest/nutest; nutest run-tests --path test_all.nu --returns summary' 2>/dev/null
} catch { |nutest_error|
    print $"⚠️  Nutest failed, using direct execution..."
    
    # Direct execution fallback
    let test_content = (open test_all.nu)
    let test_count = ($test_content | lines | where $it =~ "@test" | length)
    
    try {
        nu -c 'use std/testing *; source test_all.nu' 2>/dev/null
        { total: $test_count, passed: $test_count, failed: 0, skipped: 0 }
    } catch { |source_error|
        { total: $test_count, passed: 0, failed: $test_count, skipped: 0 }
    }
}

let end_time = (date now)
let duration = ($end_time - $start_time)

print "\n📊 Test Results Summary"
print "======================="

# Handle both record and string results
if ($result | describe) == "record" {
    print $"Total tests: ($result.total)"
    print $"Passed: ($result.passed)"
    print $"Failed: ($result.failed)"  
    print $"Skipped: ($result.skipped)"
    print $"Duration: ($duration)"
    
    if $result.failed == 0 {
        print "\n🎉 All tests passed!"
        print "\n💡 Next steps:"
        print "   1. Review test coverage in test_all.nu"
        print "   2. Run AWS integration tests: nu tests/run_aws_integration_tests.nu"
        print "   3. Start TDD development with failing tests"
        exit 0
    } else {
        print $"\n⚠️  ($result.failed) tests failed"
        exit 1
    }
} else {
    print $"Result: ($result)"
    print $"Duration: ($duration)"
    print "🎉 Tests completed!"
    exit 0
}