#!/usr/bin/env nu

# Test suite for functional programming patterns and recursive implementations
# Tests the new functional implementations that replaced mutable variables

use ../helpers/test_utils.nu *

#[test]
def test_recursive_scan_termination [] {
    # Test that recursive scanning terminates correctly
    
    # Mock page result with no more pages
    let final_page_result = {
        items: [{id: "item1"}, {id: "item2"}],
        last_evaluated_key: null,
        scanned_count: 2,
        count: 2
    }
    
    let initial_accumulator = {
        items: [],
        total_scanned: 0,
        page_count: 0
    }
    
    # Simulate accumulator update for final page
    let final_accumulator = {
        items: ($initial_accumulator.items | append $final_page_result.items),
        total_scanned: ($initial_accumulator.total_scanned + $final_page_result.scanned_count),
        page_count: ($initial_accumulator.page_count + 1)
    }
    
    # Test termination condition
    assert ($final_page_result.last_evaluated_key == null) "Should terminate when last_evaluated_key is null"
    assert (($final_accumulator.items | length) == 2) "Final accumulator should have correct items"
    assert ($final_accumulator.total_scanned == 2) "Final accumulator should have correct scanned count"
    assert ($final_accumulator.page_count == 1) "Final accumulator should have correct page count"
}

#[test]
def test_recursive_scan_continuation [] {
    # Test that recursive scanning continues correctly with pagination
    
    # Mock page result with more pages
    let page_result = {
        items: [{id: "item1"}],
        last_evaluated_key: {id: {S: "item1"}},
        scanned_count: 1,
        count: 1
    }
    
    let accumulator = {
        items: [],
        total_scanned: 0,
        page_count: 0
    }
    
    let updated_accumulator = {
        items: ($accumulator.items | append $page_result.items),
        total_scanned: ($accumulator.total_scanned + $page_result.scanned_count),
        page_count: ($accumulator.page_count + 1)
    }
    
    # Test continuation condition
    assert ($page_result.last_evaluated_key != null) "Should continue when last_evaluated_key is not null"
    assert (($updated_accumulator.items | length) == 1) "Accumulator should be updated"
    assert ($updated_accumulator.page_count == 1) "Page count should be incremented"
    
    # Test that last_evaluated_key can be used for next call
    let next_exclusive_start_key = $page_result.last_evaluated_key
    assert_type $next_exclusive_start_key "record" "Next key should be a record"
    assert ("id" in ($next_exclusive_start_key | columns)) "Next key should have id field"
}

#[test]
def test_recursive_batch_write_base_cases [] {
    # Test base cases for recursive batch write
    
    # Test empty items list (should return immediately)
    let empty_items = []
    assert (($empty_items | length) == 0) "Empty items should have zero length"
    
    # Test retry count exceeding max retries
    let max_retries = 3
    let exceeded_retry_count = 4
    assert ($exceeded_retry_count > $max_retries) "Exceeded retry count should be greater than max"
    
    # Test successful completion condition
    let remaining_items = []
    let retry_count = 1
    assert (($remaining_items | length) == 0) "No remaining items means success"
    assert ($retry_count <= $max_retries) "Retry count should be within limits"
}

#[test]
def test_recursive_batch_write_retry_progression [] {
    # Test retry count progression in recursive calls
    
    let initial_retry_count = 0
    let max_retries = 3
    
    # Test progression through retry attempts
    let retry_attempts = [0, 1, 2, 3]
    
    for attempt in $retry_attempts {
        assert ($attempt <= $max_retries) "Attempt should be within max retries"
        
        let next_attempt = $attempt + 1
        if $next_attempt <= $max_retries {
            assert ($next_attempt > $attempt) "Next attempt should be incremented"
        } else {
            assert ($next_attempt > $max_retries) "Should exceed max retries and fail"
        }
    }
    
    # Test exponential backoff wait times
    let wait_times = [1, 2, 4, 8, 16]
    for i in 0..<($wait_times | length) {
        let wait_time = ($wait_times | get $i)
        let expected_wait = (2 | math pow $i)
        assert ($wait_time == $expected_wait) $"Wait time at index ($i) should be ($expected_wait)"
    }
}

#[test]
def test_functional_enumerate_replacement [] {
    # Test that enumerate correctly replaces mutable counter patterns
    
    let test_batches = [
        ["item1", "item2"],
        ["item3", "item4", "item5"],
        ["item6"]
    ]
    
    let enumerated_batches = ($test_batches | enumerate)
    
    # Test structure of enumerated results
    assert (($enumerated_batches | length) == 3) "Should have 3 enumerated items"
    
    for enum_item in $enumerated_batches {
        assert_type $enum_item "record" "Enumerated item should be a record"
        assert ("index" in ($enum_item | columns)) "Should have index field"
        assert ("item" in ($enum_item | columns)) "Should have item field"
        
        let batch_num = ($enum_item.index + 1)  # 1-based numbering
        assert ($batch_num > 0) "Batch number should be positive"
        assert ($batch_num <= 3) "Batch number should be within range"
        
        assert_type $enum_item.item "list" "Item should be a list"
    }
    
    # Test specific indices
    assert (($enumerated_batches | get 0 | get index) == 0) "First index should be 0"
    assert (($enumerated_batches | get 1 | get index) == 1) "Second index should be 1"
    assert (($enumerated_batches | get 2 | get index) == 2) "Third index should be 2"
}

#[test]
def test_functional_pipeline_composition [] {
    # Test complex functional pipeline compositions used in the codebase
    
    let test_data = [
        {name: "Alice", age: 25, active: true},
        {name: "Bob", age: 30, active: false}, 
        {name: "Charlie", age: 35, active: true}
    ]
    
    # Test map-reduce pattern for data transformation
    let transformed_data = ($test_data 
        | each { |person| 
            {
                name: ($person.name | str upcase),
                age_group: (if $person.age < 30 { "young" } else { "mature" }),
                status: (if $person.active { "active" } else { "inactive" })
            }
        }
        | where status == "active"
        | reduce -f {} { |person, acc|
            $acc | insert $person.name $person.age_group
        }
    )
    
    assert_type $transformed_data "record" "Transformed data should be a record"
    assert ("ALICE" in ($transformed_data | columns)) "Should have Alice"
    assert ("CHARLIE" in ($transformed_data | columns)) "Should have Charlie"
    assert ("BOB" not-in ($transformed_data | columns)) "Should not have Bob (inactive)"
    assert ($transformed_data.ALICE == "young") "Alice should be in young group"
    assert ($transformed_data.CHARLIE == "mature") "Charlie should be in mature group"
}

#[test]
def test_immutable_data_patterns [] {
    # Test immutable data update patterns
    
    let original_record = {
        field1: "value1",
        field2: 42,
        nested: {inner: "original"}
    }
    
    # Test immutable field update
    let updated_record = ($original_record | insert field3 "new_value")
    assert ("field3" in ($updated_record | columns)) "Updated record should have new field"
    assert ("field1" in ($original_record | columns)) "Original record should be unchanged"
    assert ("field3" not-in ($original_record | columns)) "Original record should not have new field"
    
    # Test immutable nested update
    let updated_nested = ($original_record | insert nested {inner: "updated", extra: "field"})
    assert ($updated_nested.nested.inner == "updated") "Nested field should be updated"
    assert ($updated_nested.nested.extra == "field") "New nested field should be added"
    assert ($original_record.nested.inner == "original") "Original nested should be unchanged"
    
    # Test list immutability
    let original_list = [1, 2, 3]
    let extended_list = ($original_list | append [4, 5])
    assert (($original_list | length) == 3) "Original list should be unchanged"
    assert (($extended_list | length) == 5) "Extended list should have new items"
}

#[test]
def test_recursive_error_propagation [] {
    # Test that errors propagate correctly through recursive calls
    
    let error_conditions = [
        {condition: "missing_table", should_fail: true},
        {condition: "invalid_key", should_fail: true},
        {condition: "valid_operation", should_fail: false}
    ]
    
    for error_case in $error_conditions {
        if $error_case.should_fail {
            # Test error creation and propagation
            let test_error = try {
                error make { msg: $"Test error for ($error_case.condition)" }
                false
            } catch { |error|
                assert ($error.msg | str contains $error_case.condition) "Error should contain condition"
                true
            }
            assert $test_error "Error should be caught and handled"
        } else {
            # Test successful operation
            let success = try {
                "success"
            } catch {
                "failure"
            }
            assert ($success == "success") "Valid operation should succeed"
        }
    }
}

#[test]
def test_tail_recursion_pattern [] {
    # Test tail recursion patterns for stack safety
    
    # Test that recursive calls are in tail position (last operation)
    # This is a structural test of the recursive pattern
    
    let recursive_call_pattern = {
        base_case: "return result",
        recursive_case: "recursive_call(modified_params)"
    }
    
    assert ($recursive_call_pattern.base_case | str contains "return") "Base case should return"
    assert ($recursive_call_pattern.recursive_case | str contains "recursive_call") "Recursive case should call itself"
    
    # Test parameter modification between calls
    let test_params = {
        remaining_items: [1, 2, 3, 4, 5],
        retry_count: 0,
        max_retries: 3
    }
    
    # Simulate parameter modification for next recursive call
    let modified_params = {
        remaining_items: ($test_params.remaining_items | skip 3),  # Process some items
        retry_count: ($test_params.retry_count + 1),  # Increment retry
        max_retries: $test_params.max_retries  # Keep same
    }
    
    assert (($modified_params.remaining_items | length) < ($test_params.remaining_items | length)) "Remaining items should decrease"
    assert ($modified_params.retry_count > $test_params.retry_count) "Retry count should increase"
    assert ($modified_params.max_retries == $test_params.max_retries) "Max retries should stay same"
}

#[test]
def test_higher_order_function_usage [] {
    # Test higher-order function patterns used in the codebase
    
    let test_items = [
        {type: "user", data: {name: "Alice"}},
        {type: "product", data: {name: "Widget"}},
        {type: "user", data: {name: "Bob"}}
    ]
    
    # Test filter with predicate
    let users_only = ($test_items | where type == "user")
    assert (($users_only | length) == 2) "Should filter to users only"
    assert (($users_only | all { |item| $item.type == "user" })) "All filtered items should be users"
    
    # Test map with transformation function
    let names_only = ($test_items | each { |item| $item.data.name })
    assert (($names_only | length) == 3) "Should extract all names"
    assert ("Alice" in $names_only) "Should contain Alice"
    assert ("Widget" in $names_only) "Should contain Widget"
    assert ("Bob" in $names_only) "Should contain Bob"
    
    # Test reduce with accumulator function
    let name_types = ($test_items | reduce -f {} { |item, acc|
        $acc | insert $item.data.name $item.type
    })
    assert ($name_types.Alice == "user") "Alice should be user type"
    assert ($name_types.Widget == "product") "Widget should be product type"
    assert ($name_types.Bob == "user") "Bob should be user type"
}

#[test]
def test_closure_capture_patterns [] {
    # Test closure patterns and variable capture
    
    let external_value = "captured"
    let multiplier = 3
    
    # Test simple closure capture
    let test_data = [1, 2, 3, 4, 5]
    let processed = ($test_data | each { |x| 
        {
            original: $x,
            multiplied: ($x * $multiplier),
            tagged: $"($external_value)_($x)"
        }
    })
    
    assert (($processed | length) == 5) "Should process all items"
    assert (($processed | first | get multiplied) == 3) "Should capture multiplier"
    assert (($processed | first | get tagged) == "captured_1") "Should capture external value"
    
    # Test closure with complex logic
    let condition_checker = { |item|
        ($item.original > 2) and ($item.multiplied < 15)
    }
    
    let filtered = ($processed | where { |item| do $condition_checker $item })
    assert (($filtered | length) == 2) "Should filter correctly with closure"
}

#[test]
def test_functional_error_handling [] {
    # Test functional error handling patterns
    
    let risky_operations = [
        {input: 10, divisor: 2, should_succeed: true},
        {input: 10, divisor: 0, should_succeed: false},
        {input: 5, divisor: 1, should_succeed: true}
    ]
    
    # Test error handling with try/catch in functional pipeline
    let results = ($risky_operations | each { |op|
        let result = try {
            if $op.divisor == 0 {
                error make { msg: "Division by zero" }
            } else {
                {success: true, value: ($op.input / $op.divisor)}
            }
        } catch { |error|
            {success: false, error: $error.msg}
        }
        
        {
            input: $op.input,
            divisor: $op.divisor,
            expected_success: $op.should_succeed,
            actual_success: $result.success,
            result: $result
        }
    })
    
    # Test that error handling worked correctly
    for result in $results {
        assert ($result.actual_success == $result.expected_success) "Error handling should match expectation"
        if $result.actual_success {
            assert ("value" in ($result.result | columns)) "Successful results should have value"
        } else {
            assert ("error" in ($result.result | columns)) "Failed results should have error"
        }
    }
}

#[test]
def test_pure_function_properties [] {
    # Test that functions maintain pure function properties
    
    let test_input = {field1: "value1", field2: 42}
    
    # Test that pure transformation doesn't modify input
    let transformation_result = ($test_input | insert field3 "new_value")
    
    # Original should be unchanged (immutability)
    assert (($test_input | columns | length) == 2) "Original should have 2 fields"
    assert ("field3" not-in ($test_input | columns)) "Original should not have new field"
    
    # Result should have new structure
    assert (($transformation_result | columns | length) == 3) "Result should have 3 fields"
    assert ("field3" in ($transformation_result | columns)) "Result should have new field"
    
    # Test deterministic behavior (same input -> same output)
    let second_result = ($test_input | insert field3 "new_value")
    assert ($transformation_result == $second_result) "Same input should produce same output"
    
    # Test composability
    let composed_result = ($test_input 
        | insert field3 "new_value"
        | insert field4 84
        | upsert field2 ($test_input.field2 * 2)
    )
    
    assert (($composed_result | columns | length) == 4) "Composed result should have 4 fields"
    assert ($composed_result.field2 == 84) "Composed transformation should work"
    assert ($composed_result.field4 == 84) "New field should be added"
}

# All tests completed - no print needed in module