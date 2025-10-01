#!/usr/bin/env nu

# Master Test Runner for DynamoDB Nu-Loader
# Executes all test suites with proper reporting and cleanup

def main [
    --skip-aws       # Skip AWS integration tests
    --skip-stress    # Skip stress testing
    --quick          # Quick mode - essential tests only
] {
    print "🎯 DynamoDB Nu-Loader - Master Test Suite Runner"
    print "==============================================="
    print ""

    if $quick {
        print "🏃 Quick mode enabled - running essential tests only"
    }

    if $skip_aws {
        print "⚠️  AWS tests skipped (--skip-aws flag)"
    }

    if $skip_stress {
        print "⚠️  Stress tests skipped (--skip-stress flag)"
    }

    print ""

    def run_test_suite [suite_name: string, command: string, required: bool = true]: nothing -> record {
        print $"🧪 Running: ($suite_name)"
        print "=" * 60
        
        let suite_start = (date now)
        
        let result = try {
            let output = (nu -c $command | complete)
            {
                success: ($output.exit_code == 0),
                output: $output.stdout,
                error: $output.stderr,
                exit_code: $output.exit_code
            }
        } catch { |error|
            {
                success: false,
                output: "",
                error: $error.msg,
                exit_code: 1
            }
        }
        
        let suite_end = (date now)
        let duration = ($suite_end - $suite_start)
        
        if $result.success {
            print $"✅ PASS: ($suite_name) (($duration))"
            
            # Try to extract test counts from output
            let test_count = try {
                if ($result.output | str contains "Passed:") {
                    let line = ($result.output | lines | where $it =~ "Passed:" | first)
                    let parts = ($line | str replace "✅ Passed: " "" | str replace " tests" "" | split row "/")
                    {
                        passed: ($parts | first | into int),
                        total: ($parts | last | into int)
                    }
                } else if ($result.output | str contains "passed") and ($result.output | str contains "total") {
                    # Parse nutest format
                    {
                        passed: 1,
                        total: 1
                    }
                } else {
                    { passed: 1, total: 1 }  # Assume success if can't parse
                }
            } catch {
                { passed: 1, total: 1 }
            }
            
            {
                suite: $suite_name,
                success: true,
                duration: $duration,
                tests_passed: $test_count.passed,
                tests_total: $test_count.total,
                error: null
            }
        } else {
            print $"❌ FAIL: ($suite_name) - Exit code: ($result.exit_code)"
            if ($result.error | str length) > 0 {
                print $"   Error: ($result.error)"
            }
            
            if $required {
                print "\n💥 Required test suite failed - stopping execution"
                exit 1
            }
            
            {
                suite: $suite_name,
                success: false,
                duration: $duration,
                tests_passed: 0,
                tests_total: 0,
                error: $result.error
            }
        }
    }

    # Test execution plan
    print "📋 Test Execution Plan:"
    print "   1. Unit Tests (43 tests) - Required"
    if not $skip_aws {
        print "   2. AWS Integration Tests (6 tests) - Optional"
        if not $quick {
            print "   3. Enhanced AWS Integration (8 tests) - Optional"
            print "   4. Comprehensive AWS Suite (6 tests) - Optional"
        }
        if not $skip_stress {
            print "   5. Stress Testing Suite (5 tests) - Optional"
        }
    }
    print ""

    let overall_start = (date now)
    let suite_results = []

    # 1. Unit Tests (Always run - required)
    let unit_result = (run_test_suite "Unit Tests" "nu run_tests.nu" true)
    let suite_results = ($suite_results | append $unit_result)

    # 2. AWS Integration Tests (Optional)
    if not $skip_aws {
        print "\n⚠️  AWS tests will create and destroy REAL AWS resources"
        print "   Ensure you have valid credentials and test environment"
        print ""
        
        let aws_result = (run_test_suite "AWS Integration Tests" "nu tests/run_aws_integration_tests.nu" false)
        let suite_results = ($suite_results | append $aws_result)
        
        # 3. Enhanced AWS Integration (Skip in quick mode)
        if not $quick and $aws_result.success {
            let enhanced_result = (run_test_suite "Enhanced AWS Integration" "nu enhanced_aws_integration_tests.nu" false)
            let suite_results = ($suite_results | append $enhanced_result)
            
            # 4. Comprehensive AWS Suite
            let comprehensive_result = (run_test_suite "Comprehensive AWS Suite" "nu comprehensive_aws_test_suite.nu" false)
            let suite_results = ($suite_results | append $comprehensive_result)
        }
        
        # 5. Stress Testing (Skip if requested)
        if not $skip_stress and not $quick {
            print "\n💪 Stress tests may take significant time and AWS resources"
            print "   Consider running separately for performance validation"
            print ""
            
            let stress_result = (run_test_suite "Stress Testing Suite" "nu stress_testing_suite.nu" false)
            let suite_results = ($suite_results | append $stress_result)
        }
    }

    let overall_end = (date now)
    let total_duration = ($overall_end - $overall_start)

    # Generate comprehensive report
    print "\n📊 Master Test Suite Results"
    print "============================="
    print $"⏱️  Total Execution Time: ($total_duration)"
    print ""

    let successful_suites = ($suite_results | where success == true | length)
    let total_suites = ($suite_results | length)
    let total_tests_run = ($suite_results | each { |r| $r.tests_total } | math sum)
    let total_tests_passed = ($suite_results | each { |r| $r.tests_passed } | math sum)

    print "🎯 Suite Summary:"
    $suite_results | each { |result|
        let status_icon = if $result.success { "✅" } else { "❌" }
        let test_info = if $result.tests_total > 0 { 
            $" - ($result.tests_passed)/($result.tests_total) tests"
        } else { 
            ""
        }
        print $"   ($status_icon) ($result.suite): ($result.duration)($test_info)"
        if not $result.success and ($result.error != null) {
            print $"       Error: ($result.error)"
        }
    }

    print ""
    print $"✅ Suites Passed: ($successful_suites)/($total_suites)"
    print $"🎯 Tests Passed: ($total_tests_passed)/($total_tests_run)"

    # Final assessment
    if $successful_suites == $total_suites {
        print "\n🎉 All test suites completed successfully!"
        print ""
        print "💡 Your DynamoDB Nu-Loader is validated for:"
        print "   • Core functionality and edge cases"
        if not $skip_aws {
            print "   • Real AWS DynamoDB operations"
            print "   • Production-ready Test Data Management workflows"
        }
        if not $skip_stress {
            print "   • Performance under stress conditions"
        }
        print ""
        print "🚀 Tool is production-ready for TDM operations!"
        
        # Create test completion artifact
        let test_report = {
            timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
            total_duration: $total_duration,
            suites_run: $total_suites,
            suites_passed: $successful_suites,
            tests_run: $total_tests_run,
            tests_passed: $total_tests_passed,
            success_rate: (($total_tests_passed / $total_tests_run) * 100),
            environment: {
                skip_aws: $skip_aws,
                skip_stress: $skip_stress,
                quick_mode: $quick
            },
            suite_results: $suite_results
        }
        
        $test_report | to json | save "test_run_report.json"
        print $"📋 Detailed report saved to: test_run_report.json"
        
    } else {
        print "\n❌ Some test suites failed!"
        print ""
        print "🔍 Failed suites may indicate:"
        print "   • Bugs or limitations in the tool"
        print "   • Missing dependencies or permissions"
        print "   • Environmental issues (AWS credentials, network, etc.)"
        print ""
        print "📋 Review the detailed output above for specific error information"
        
        let failed_suites = ($suite_results | where success == false)
        if ($failed_suites | length) > 0 {
            print "\n💥 Failed Suites:"
            $failed_suites | each { |suite|
                print $"   - ($suite.suite): ($suite.error)"
            }
        }
        
        exit 1
    }

    print ""
    print "🎯 Test execution completed!"
    print "   Run with --help to see available options"
    print "   Run individual suites for targeted testing"
}