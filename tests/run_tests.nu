#!/usr/bin/env nu

# Test runner for DynamoDB Nu-Loader using nutest framework
# This script runs all tests and provides a comprehensive test report

# Check if nutest is available
def check_nutest []: nothing -> nothing {
  try {
    ^nutest --version
  } catch {
    print "Error: nutest is not installed or not in PATH"
    print "Please install nutest first:"
    print "  git clone https://github.com/vyadh/nutest"
    print "  # Follow installation instructions"
    exit 1
  }
}

# Run unit tests
def run_unit_tests []: nothing -> record {
  print "🧪 Running unit tests..."
  
  let unit_test_files = [
    "tests/unit/test_data_ops.nu",
    "tests/unit/test_aws_ops.nu", 
    "tests/unit/test_cli.nu",
    "tests/unit/test_upload_processing.nu",
    "tests/unit/test_validation.nu"
  ]
  
  let results = ($unit_test_files | each { |test_file|
    if ($test_file | path exists) {
      print $"  Running ($test_file)..."
      try {
        let result = (^nutest $test_file)
        { file: $test_file, status: "PASS", output: $result }
      } catch { |e|
        { file: $test_file, status: "FAIL", error: $e.msg }
      }
    } else {
      { file: $test_file, status: "SKIP", reason: "File not found" }
    }
  })
  
  let passed = ($results | where status == "PASS" | length)
  let failed = ($results | where status == "FAIL" | length)
  let skipped = ($results | where status == "SKIP" | length)
  
  {
    type: "unit",
    total: ($results | length),
    passed: $passed,
    failed: $failed,
    skipped: $skipped,
    results: $results
  }
}

# Run integration tests
def run_integration_tests []: nothing -> record {
  print "🔗 Running integration tests..."
  
  let integration_test_files = [
    "tests/integration/test_workflows.nu",
    "tests/integration/test_formats.nu",
    "tests/integration/test_upload_formats.nu"
  ]
  
  let results = ($integration_test_files | each { |test_file|
    if ($test_file | path exists) {
      print $"  Running ($test_file)..."
      try {
        let result = (^nutest $test_file)
        { file: $test_file, status: "PASS", output: $result }
      } catch { |e|
        { file: $test_file, status: "FAIL", error: $e.msg }
      }
    } else {
      { file: $test_file, status: "SKIP", reason: "File not found" }
    }
  })
  
  let passed = ($results | where status == "PASS" | length)
  let failed = ($results | where status == "FAIL" | length)
  let skipped = ($results | where status == "SKIP" | length)
  
  {
    type: "integration",
    total: ($results | length),
    passed: $passed,
    failed: $failed,
    skipped: $skipped,
    results: $results
  }
}

# Run all tests and generate report
def run_all_tests []: nothing -> record {
  print "🚀 Starting DynamoDB Nu-Loader Test Suite"
  print "========================================"
  print ""
  
  let start_time = (date now)
  
  # Run unit tests
  let unit_results = run_unit_tests
  print ""
  
  # Run integration tests
  let integration_results = run_integration_tests
  print ""
  
  let end_time = (date now)
  let duration = ($end_time - $start_time)
  
  # Calculate totals
  let total_tests = ($unit_results.total + $integration_results.total)
  let total_passed = ($unit_results.passed + $integration_results.passed)
  let total_failed = ($unit_results.failed + $integration_results.failed)
  let total_skipped = ($unit_results.skipped + $integration_results.skipped)
  
  let overall_result = {
    start_time: $start_time,
    end_time: $end_time,
    duration: $duration,
    total_tests: $total_tests,
    total_passed: $total_passed,
    total_failed: $total_failed,
    total_skipped: $total_skipped,
    unit_results: $unit_results,
    integration_results: $integration_results,
    success: ($total_failed == 0)
  }
  
  $overall_result
}

# Print test summary
def print_test_summary [results: record]: nothing -> nothing {
  print "📊 Test Summary"
  print "==============="
  print $"Total Tests: ($results.total_tests)"
  print $"✅ Passed: ($results.total_passed)"
  if $results.total_failed > 0 {
    print $"❌ Failed: ($results.total_failed)"
  }
  if $results.total_skipped > 0 {
    print $"⏭️  Skipped: ($results.total_skipped)"
  }
  print $"⏱️  Duration: ($results.duration)"
  print ""
  
  if $results.success {
    print "🎉 All tests passed!"
  } else {
    print "💥 Some tests failed. See details above."
    
    # Print failed test details
    print ""
    print "Failed Tests:"
    print "============="
    
    let failed_unit = ($results.unit_results.results | where status == "FAIL")
    let failed_integration = ($results.integration_results.results | where status == "FAIL") 
    
    ($failed_unit | append $failed_integration) | each { |failed_test|
      print $"❌ ($failed_test.file): ($failed_test.error)"
    }
  }
}

# Save test results to file
def save_test_results [results: record, filename: string]: nothing -> nothing {
  $results | to json | save $filename
  print $"📄 Test results saved to ($filename)"
}

# Main test runner
def main [
  --unit-only        # Run only unit tests
  --integration-only # Run only integration tests  
  --save-results: string  # Save results to JSON file
  --verbose          # Verbose output
]: nothing -> nothing {
  
  check_nutest
  
  if $unit_only {
    let results = run_unit_tests
    print_test_summary { 
      total_tests: $results.total,
      total_passed: $results.passed,
      total_failed: $results.failed,
      total_skipped: $results.skipped,
      success: ($results.failed == 0),
      unit_results: $results,
      integration_results: { total: 0, passed: 0, failed: 0, skipped: 0 },
      duration: "N/A"
    }
  } else if $integration_only {
    let results = run_integration_tests
    print_test_summary {
      total_tests: $results.total,
      total_passed: $results.passed,
      total_failed: $results.failed,
      total_skipped: $results.skipped,
      success: ($results.failed == 0),
      unit_results: { total: 0, passed: 0, failed: 0, skipped: 0 },
      integration_results: $results,
      duration: "N/A"
    }
  } else {
    let results = run_all_tests
    print_test_summary $results
    
    if ($save_results != null) {
      save_test_results $results $save_results
    }
    
    # Exit with appropriate code
    if not $results.success {
      exit 1
    }
  }
}

# Show usage if called without nutest available
if (which nutest | length) == 0 {
  print "DynamoDB Nu-Loader Test Runner"
  print "=============================="
  print ""
  print "This test suite requires nutest framework."
  print "Install from: https://github.com/vyadh/nutest"
  print ""
  print "Usage:"
  print "  nu run_tests.nu                    # Run all tests"
  print "  nu run_tests.nu --unit-only        # Run only unit tests"
  print "  nu run_tests.nu --integration-only # Run only integration tests"
  print "  nu run_tests.nu --save-results results.json  # Save results to file"
}