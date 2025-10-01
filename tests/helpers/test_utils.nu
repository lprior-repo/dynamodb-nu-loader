# Test utilities and helper functions for DynamoDB Nu-Loader tests

# Assert functions for testing
export def assert_equal [actual: any, expected: any, message: string]: nothing -> nothing {
  if $actual != $expected {
    error make {
      msg: $"Assertion failed: ($message)",
      label: {
        text: $"Expected ($expected), got ($actual)",
        span: (metadata $actual).span
      }
    }
  }
}

export def assert_type [value: any, expected_type: string, message: string]: nothing -> nothing {
  let actual_type = ($value | describe)
  # Handle both specific types (record<field: type>) and generic types (record)
  let type_matches = if ($expected_type == "record") {
    $actual_type =~ "record"
  } else if ($expected_type == "list") {
    # In Nushell, lists of records are represented as table<...>
    ($actual_type =~ "list") or ($actual_type =~ "table")
  } else {
    $actual_type == $expected_type
  }
  
  if not $type_matches {
    error make {
      msg: $"Type assertion failed: ($message)",
      label: {
        text: $"Expected ($expected_type), got ($actual_type)",
        span: (metadata $value).span
      }
    }
  }
}

export def assert_error [operation: closure, message: string]: nothing -> nothing {
  let result = try {
    do $operation
    false
  } catch {
    true
  }
  
  if not $result {
    error make {
      msg: $"Expected operation to fail: ($message)"
    }
  }
}

export def assert_contains [container: list, item: any, message: string]: nothing -> nothing {
  if not ($item in $container) {
    error make {
      msg: $"Assertion failed: ($message)",
      label: {
        text: $"Expected container to contain ($item)"
      }
    }
  }
}

export def assert [condition: bool, message: string]: nothing -> nothing {
  if not $condition {
    error make {
      msg: $"Assertion failed: ($message)"
    }
  }
}

# Test data generators
export def generate_test_users [count: int]: nothing -> list<record> {
  1..$count | each { |i|
    {
      id: $"user-($i)",
      sort_key: "USER",
      name: $"Test User ($i)",
      email: $"user($i)@example.com",
      age: (20 + ($i mod 40)),
      gsi1_pk: "TEST_USER",
      gsi1_sk: $"2024-01-(if $i < 10 { $'0($i)' } else { $i | into string })"
    }
  }
}

export def generate_test_products [count: int]: nothing -> list<record> {
  let categories = ["Electronics", "Kitchen", "Books", "Clothing"]
  1..$count | each { |i|
    {
      id: $"prod-($i)",
      sort_key: "PRODUCT",
      name: $"Test Product ($i)",
      price: (10.0 + ($i * 5.5)),
      category: ($categories | get (($i - 1) mod ($categories | length))),
      in_stock: (($i mod 2) == 1),
      gsi1_pk: ($categories | get (($i - 1) mod ($categories | length))),
      gsi1_sk: $"PROD_($i)"
    }
  }
}

export def generate_mixed_test_data [user_count: int, product_count: int]: nothing -> list<record> {
  let users = generate_test_users $user_count
  let products = generate_test_products $product_count
  $users | append $products
}

# Mock AWS CLI responses for unit testing
export def mock_aws_scan_response [items: list<record>]: nothing -> string {
  let dynamodb_items = ($items | each { |item|
    $item | transpose key value | reduce -f {} { |row, acc|
      let field_name = $row.key
      let field_value = $row.value
      let dynamodb_value = match ($field_value | describe) {
        "string" => { "S": $field_value },
        "int" => { "N": ($field_value | into string) },
        "float" => { "N": ($field_value | into string) },
        "bool" => { "BOOL": $field_value },
        _ => { "S": ($field_value | into string) }
      }
      $acc | insert $field_name $dynamodb_value
    }
  })
  
  { "Items": $dynamodb_items } | to json
}

export def mock_aws_describe_response [table_name: string]: nothing -> string {
  {
    "Table": {
      "TableName": $table_name,
      "TableStatus": "ACTIVE",
      "CreationDateTime": "2024-01-01T12:00:00.000Z",
      "TableSizeBytes": 1024,
      "ItemCount": 10
    }
  } | to json
}

# File system test helpers
export def create_temp_test_file [content: string, extension: string]: nothing -> string {
  let temp_file = $"/tmp/test_(random chars --length 8)($extension)"
  $content | save $temp_file
  $temp_file
}

export def cleanup_temp_files [files: list<string>]: nothing -> nothing {
  $files | each { |file|
    if ($file | path exists) {
      rm $file
    }
  }
}

# Test configuration
export def get_test_config []: nothing -> record {
  {
    dynamodb: {
      table_name: "test-table-unit",
      region: "us-east-1"
    },
    snapshots: {
      default_directory: "/tmp/test_snapshots",
      default_format: "json"
    },
    aws: {
      profile: "test"
    }
  }
}

# Benchmark helper
export def benchmark_operation [name: string, operation: closure]: nothing -> record {
  let start_time = (date now)
  let result = (do $operation)
  let end_time = (date now)
  let duration = ($end_time - $start_time)
  
  {
    benchmark: $name,
    duration_ms: (($duration | into int) / 1000000),
    result: $result
  }
}