#!/usr/bin/env nu
# ^ Shebang line - tells the system to use Nushell to execute this script

# DynamoDB Nu-Loader: Minimal test data management tool
# Provides snapshot, restore, wipe, and seed operations for DynamoDB tables
#
# ⚠️ IMPORTANT - COMMANDS THAT WIPE TABLE DATA:
# - 'restore <file>': CLEARS ALL DATA before restoring from file
# - 'seed [file]': CLEARS ALL DATA before loading seed data  
# - 'wipe --force': DELETES ALL DATA (this is the explicit purpose)
#
# ✅ SAFE COMMANDS (no data loss):
# - 'status': Only reads table information
# - 'snapshot [name]': Only reads data to create backup files
# - 'snapshot --dry-run': Only counts items, creates no files

# Enhanced help function - displays comprehensive usage information
# In Nushell:
# - 'def' defines a function: https://www.nushell.sh/book/custom_commands.html
# - []: nothing -> nothing means no parameters and returns nothing (void)
# - Functions are pure by default - they don't modify global state
# Learn more: https://www.nushell.sh/book/types_of_data.html#nothing
def show_enhanced_help []: nothing -> nothing {
  # 'print' command outputs text to stdout
  # Nushell supports Unicode characters and emojis in strings
  print "🧩 DynamoDB Nu-Loader v1.0"
  print "=========================="
  print ""
  print "A minimal test data management tool for DynamoDB tables"
  print ""
  print "✨ FEATURES:"
  print "  • Snapshot and restore DynamoDB data"
  print "  • Support for JSON and CSV formats with auto-detection"
  print "  • Batch operations respecting DynamoDB limits"
  print "  • Functional programming principles with type safety"
  print ""
  print "📋 USAGE:"
  print "    nu main.nu <COMMAND> [OPTIONS]"
  print ""
  print "🔧 COMMANDS:"
  print "    snapshot <name>     Create a snapshot of the DynamoDB table"
  print "      --dry-run         Count items exactly without saving snapshot"
  print "      --exact-count     Use exact count in metadata (slower)"
  print "    restore <file>      Restore data from a snapshot file (JSON/CSV)"
  print "    wipe [--force]      Delete all items from the DynamoDB table"
  print "    seed                Load default seed data into the table"
  print "    status              Show table status and approximate item count"
  print ""
  print "🚩 GLOBAL FLAGS:"
  print "    --table <name>      DynamoDB table name (required: use flag or $TABLE_NAME env var)"
  print "    --region <region>   AWS region (required: use flag or $AWS_REGION env var)"
  print "    --snapshots-dir <dir>  Snapshots directory (required for snapshot: use flag or $SNAPSHOTS_DIR env var)"
  print ""
  print "📖 EXAMPLES:"
  print "    # Set environment variables:"
  print "    export TABLE_NAME=test-table"
  print "    export AWS_REGION=us-east-1"
  print "    export SNAPSHOTS_DIR=./snapshots"
  print ""
  print "    # Or use command line flags:"
  print "    nu main.nu status --table test-table --region us-east-1"
  print "    nu main.nu snapshot backup-2024 --table my-table --region us-west-2 --snapshots-dir ./backups"
  print "    nu main.nu snapshot --dry-run --table my-table --region us-west-2  # Get exact count only"
  print "    nu main.nu restore backup-2024.json --table my-table --region us-west-2"
  print "    nu main.nu wipe --force --table my-table --region us-west-2"
  print "    nu main.nu seed --table my-table --region us-west-2"
  print ""
  print "💡 TIPS:"
  print "  • For command-specific help: nu main.nu <command> --help"
  print "  • JSON files support both snapshot format and raw arrays"
  print "  • CSV files are auto-detected by .csv extension"
  print "  • Create snapshots before wiping data"
  print "  • Use 'seed' to quickly set up test data"
  print "  • Use 'snapshot --dry-run' for exact item counts without creating files"
  print ""
  print "🔗 More info: Check README.md for installation and setup"
}

# Show enhanced help when called without arguments
# 'main' is a special function name - it's called when script runs without subcommands
def main []: nothing -> nothing {
  show_enhanced_help
}

# Enhanced Error Handling Functions

# Creates a temporary file, executes an operation with it, then cleans up
# Key Nushell concepts:
# - 'closure' type: https://www.nushell.sh/book/types_of_data.html#closures-blocks
# - 'any' type: https://www.nushell.sh/book/types_of_data.html#any
# - Function handles both success and error cases with proper cleanup
def with_temp_file [
  data: any           # Data to write to temp file
  operation: closure  # Block of code to execute with the temp file
]: nothing -> any {
  # Create unique temp file name using string interpolation ($"...")
  # 'random chars' generates random characters for uniqueness
  let temp_file = $"/tmp/dynamodb_nu_loader_(random chars --length 12).json"
  
  # 'try' block for error handling: https://www.nushell.sh/book/working_with_errors.html
  let result = try {
    # Nushell pipeline: https://www.nushell.sh/book/pipelines.html
    # $data | to json converts data to JSON string
    # | save $temp_file writes the JSON to the file
    $data | to json | save $temp_file
    
    # 'do' executes the closure: https://www.nushell.sh/book/custom_commands.html#closures
    do $operation $temp_file
  } catch { |error|
    # Cleanup on error - ensure temp file is removed
    # 'path exists' checks if file exists
    if ($temp_file | path exists) {
      # Nested try/catch - ignore cleanup errors (|_| discards error)
      try { rm $temp_file } catch { |_| }
    }
    # 'error make' creates a new error with custom message
    # Re-throw the original error to preserve error information
    error make { msg: $error.msg }
  }
  
  # Normal cleanup - remove temp file after successful operation
  if ($temp_file | path exists) {
    try { rm $temp_file } catch { |_| }
  }
  
  # Return the result from the operation
  # In Nushell, the last expression is automatically returned
  $result
}

# Parses AWS CLI error output and provides helpful error messages
# This function improves error messages from cryptic AWS errors to user-friendly explanations
def handle_aws_error [
  error_output: string  # Raw error output from AWS CLI
  operation: string     # Name of operation that failed (for context)
]: nothing -> nothing {
  # Parse common AWS error patterns from CLI output
  # 'str contains' checks if a string contains a substring
  # Each 'if' checks for specific AWS error patterns and provides helpful explanations
  # String interpolation: $"text ($variable)" embeds variable values in strings
  if ($error_output | str contains "ResourceNotFoundException") {
    error make { 
      msg: $"Table not found during ($operation). Please verify the table name exists and is in the correct region."
    }
  } else if ($error_output | str contains "ProvisionedThroughputExceededException") {
    error make { 
      msg: $"Throughput exceeded during ($operation). The request rate is too high for the provisioned capacity. Consider using exponential backoff or increasing provisioned capacity."
    }
  } else if ($error_output | str contains "ThrottlingException") {
    error make { 
      msg: $"Request throttled during ($operation). DynamoDB is temporarily throttling requests. This is usually temporary - retry with exponential backoff."
    }
  } else if ($error_output | str contains "RequestLimitExceeded") {
    error make { 
      msg: $"Request limit exceeded during ($operation). Throughput exceeds current account quota. Contact AWS Support to request a quota increase."
    }
  } else if ($error_output | str contains "InternalServerError") {
    error make { 
      msg: $"AWS internal server error during ($operation). This is a temporary AWS-side issue. Retry the operation."
    }
  } else if ($error_output | str contains "ValidationException") {
    error make { 
      msg: $"Validation error during ($operation). Request parameters are invalid. Check table name, key attributes, and data types."
    }
  } else if ($error_output | str contains "ItemCollectionSizeLimitExceededException") {
    error make { 
      msg: $"Item collection size limit exceeded during ($operation). The total size of items with the same partition key exceeds 10 GB limit."
    }
  } else if ($error_output | str contains "ReplicatedWriteConflictException") {
    error make { 
      msg: $"Replicated write conflict during ($operation). Items are being modified by requests in another region. Retry with exponential backoff."
    }
  } else if ($error_output | str contains "AccessDeniedException") {
    error make { 
      msg: $"Access denied during ($operation). Check your AWS credentials and IAM permissions for DynamoDB operations."
    }
  } else if ($error_output | str contains "UnrecognizedClientException") {
    error make { 
      msg: $"Unrecognized client during ($operation). AWS credentials may be invalid or expired. Run 'aws configure' to set up credentials."
    }
  } else {
    # Generic fallback error with the original AWS output
    error make { 
      msg: $"AWS operation failed during ($operation): ($error_output)"
    }
  }
}

# Validates that AWS credentials are properly configured
# ✅ SAFE FUNCTION: Only reads AWS account information, no data modification
def validate_aws_credentials []: nothing -> nothing {
  try {
    # '^' prefix runs external command: https://www.nushell.sh/book/externs.html
    # 'complete' captures stdout, stderr, and exit code: https://www.nushell.sh/commands/docs/complete.html
    let result = (^aws sts get-caller-identity | complete)
    
    # Check exit code - 0 means success, non-zero means error
    if $result.exit_code != 0 {
      handle_aws_error $result.stderr "validate-credentials"
    }
    
    print "✅ AWS credentials validated"
  } catch { |error|
    # Catch any other errors (like aws CLI not installed)
    error make { 
      msg: $"Failed to validate AWS credentials: ($error.msg). Ensure AWS CLI is installed and credentials are configured."
    }
  }
}

# Validates that a DynamoDB table exists and is accessible
# ✅ SAFE FUNCTION: Only reads table metadata, no data modification
def validate_table_exists [
  table_name: string  # Name of DynamoDB table to check
  region: string      # AWS region where table should exist
]: nothing -> nothing {
  try {
    # Call AWS CLI to describe the table - this checks existence and permissions
    let result = (^aws dynamodb describe-table --table-name $table_name --region $region | complete)
    
    # Check if the AWS CLI command succeeded
    if $result.exit_code != 0 {
      handle_aws_error $result.stderr "describe-table"
    }
    
    print $"✅ Table ($table_name) exists and is accessible"
  } catch { |error|
    error make { 
      msg: $"Table validation failed: ($error.msg)"
    }
  }
}

# AWS DynamoDB Operations

# Gets the key schema (primary key structure) for a DynamoDB table
# ✅ SAFE FUNCTION: Only reads table schema, no data modification
def get_table_key_schema [
  table_name: string    # DynamoDB table name
  --region: string      # AWS region (optional flag, uses env var if not provided)
]: nothing -> record {
  # '| default' provides fallback value: https://www.nushell.sh/commands/docs/default.html
  # '$env.AWS_REGION?' safely accesses environment variable: https://www.nushell.sh/book/environment.html
  let aws_region = $region | default $env.AWS_REGION?
  
  # Input validation - ensure we have a region before making AWS calls
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  try {
    # Get detailed table information from AWS
    let result = (^aws dynamodb describe-table --table-name $table_name --region $aws_region | complete)
    
    if $result.exit_code != 0 {
      handle_aws_error $result.stderr "describe-table"
    }
    
    # Parse JSON response from AWS CLI
    # 'from json' converts JSON string to Nushell data: https://www.nushell.sh/commands/docs/from_json.html
    let table_description = $result.stdout | from json
    
    # Return a record (like a struct/object) with key schema information
    # This data is needed for building proper delete requests later
    {
      key_schema: $table_description.Table.KeySchema,
      attribute_definitions: $table_description.Table.AttributeDefinitions
    }
  } catch { |error|
    error make { msg: $"Error describing table ($table_name): ($error.msg)" }
  }
}

# Extracts key attributes from an item for DynamoDB delete operations
# DynamoDB requires exact key values to delete items
def get_key_attributes_for_item [
  item: record                        # The item to extract keys from
  key_schema: list<record>           # Table's key schema (partition key, sort key)
  attribute_definitions: list<record> # Table's attribute definitions (types)
]: nothing -> record {
  # Build the key object dynamically based on the table's schema
  # 'reduce' accumulates values: https://www.nushell.sh/commands/docs/reduce.html
  # '-f {}' starts with empty record and builds up the key object
  # Each iteration adds one key attribute to the accumulator
  $key_schema | reduce -f {} { |key_def, acc|
    let attr_name = $key_def.AttributeName
    let attr_value = $item | get $attr_name
    
    # Find the attribute type from the table definition
    # 'where' filters records: https://www.nushell.sh/commands/docs/where.html
    # 'first' gets the first match: https://www.nushell.sh/commands/docs/first.html
    let attr_type = ($attribute_definitions | where AttributeName == $attr_name | first).AttributeType
    
    # Convert to DynamoDB's format based on attribute type
    # DynamoDB uses type-annotated values: {"S": "string"}, {"N": "number"}, etc.
    # 'match' pattern matching: https://www.nushell.sh/book/control_flow.html#match
    let dynamodb_value = match $attr_type {
      "S" => { "S": ($attr_value | into string) },  # String type
      "N" => { "N": ($attr_value | into string) },  # Number type (stored as string)
      "B" => { "B": $attr_value }                   # Binary type
    }
    
    # 'insert' adds a new field to the record: https://www.nushell.sh/commands/docs/insert.html
    $acc | insert $attr_name $dynamodb_value
  }
}

# Converts DynamoDB's type-annotated values back to normal Nushell values
# DynamoDB stores data as {"S": "text"}, {"N": "123"}, etc. - this converts back to "text", 123
# ✅ SAFE FUNCTION: Pure data conversion, no side effects
def convert_from_dynamodb_value [dynamodb_value: record]: nothing -> any {
  # Get the type key (S, N, BOOL, etc.) from the DynamoDB value
  # 'columns' returns the field names of a record
  let value_type = ($dynamodb_value | columns | first)
  let value_data = $dynamodb_value | get $value_type
  
  # Handle each DynamoDB type appropriately
  # 'match' is like switch/case in other languages
  match $value_type {
    "S" => $value_data,                               # String - return as-is
    "N" => {                                          # Number - parse back to int/float
      # Try to parse as int first, then float
      try {
        $value_data | into int
      } catch {
        $value_data | into float
      }
    },
    "BOOL" => $value_data,                           # Boolean - return as-is
    "NULL" => null,                                   # Null value
    "SS" => $value_data,                             # String Set - return as list
    "NS" => ($value_data | each { |n|                # Number Set - convert each number
      try {
        $n | into int
      } catch {
        $n | into float
      }
    }),
    "BS" => $value_data,                             # Binary Set - return as-is
    "L" => ($value_data | each { |item| convert_from_dynamodb_value $item }), # List - recursive conversion
    "M" => {                                         # Map (nested object) - recursive conversion
      # Convert nested map recursively
      # 'transpose' converts record to list of {key, value} records
      let converted_map = ($value_data | transpose key value | reduce -f {} { |row, acc|
        let converted_value = convert_from_dynamodb_value $row.value
        $acc | insert $row.key $converted_value
      })
      $converted_map
    },
    _ => $value_data  # Fallback for unknown types
  }
}

# Scans one page of a DynamoDB table (DynamoDB limits to 1MB per scan)
# ✅ SAFE FUNCTION: Only reads data, no modifications
def scan_table_page [
  table_name: string            # Name of DynamoDB table to scan
  --region: string              # AWS region
  --exclusive-start-key: any    # For pagination (can be null or record)
]: nothing -> record {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  try {
    let result = if $exclusive_start_key == null {
      (^aws dynamodb scan --table-name $table_name --region $aws_region | complete)
    } else {
      with_temp_file $exclusive_start_key { |temp_file|
        (^aws dynamodb scan --table-name $table_name --region $aws_region --exclusive-start-key $"file://($temp_file)" | complete)
      }
    }
    
    if $result.exit_code != 0 {
      handle_aws_error $result.stderr "scan-table"
    }
    
    let scan_result = $result.stdout | from json
    let items = $scan_result | get Items | each { |item|
      let converted = ($item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let dynamodb_value = $row.value
        let field_value = convert_from_dynamodb_value $dynamodb_value
        $acc | insert $field_name $field_value
      })
      $converted
    }
    
    {
      items: $items,
      last_evaluated_key: ($scan_result | get -o LastEvaluatedKey),
      scanned_count: ($scan_result | get ScannedCount),
      count: ($scan_result | get Count)
    }
  } catch { |error|
    error make { msg: $"Error scanning table ($table_name): ($error.msg)" }
  }
}

# Functional helper for recursive scanning
def scan_table_recursive [
  table_name: string
  aws_region: string
  accumulator: record
  --exclusive-start-key: any = null
]: nothing -> record {
  let page_result = scan_table_page $table_name --region $aws_region --exclusive-start-key $exclusive_start_key
  
  let updated_accumulator = {
    items: ($accumulator.items | append $page_result.items),
    total_scanned: ($accumulator.total_scanned + $page_result.scanned_count),
    page_count: ($accumulator.page_count + 1)
  }
  
  let page_count = $updated_accumulator.page_count
  let found_count = $page_result.count
  let scanned_count = $page_result.scanned_count
  let message = $"  Page ($page_count): Found ($found_count) items " + "(scanned " + ($scanned_count | into string) + ")"
  print $message
  
  if $page_result.last_evaluated_key == null {
    $updated_accumulator
  } else {
    scan_table_recursive $table_name $aws_region $updated_accumulator --exclusive-start-key $page_result.last_evaluated_key
  }
}

def scan_table [
  table_name: string
  --region: string  # AWS region
]: nothing -> list<record> {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  print $"Scanning table ($table_name)..."
  
  let initial_accumulator = {
    items: [],
    total_scanned: 0,
    page_count: 0
  }
  
  let final_result = scan_table_recursive $table_name $aws_region $initial_accumulator
  
  let total_items = ($final_result.items | length)
  print $"Scan complete: ($total_items) total items across ($final_result.page_count) pages"
  $final_result.items
}

# Converts normal Nushell values to DynamoDB's type-annotated format
# DynamoDB requires all values to have explicit types: {"S": "text"}, {"N": "123"}, etc.
# ✅ SAFE FUNCTION: Pure data conversion, no side effects
def convert_to_dynamodb_value [value: any]: any -> record {
  if $value == null {
    { "NULL": true }  # DynamoDB null representation
  } else {
    # 'describe' returns the type of a value as a string
    let value_type = ($value | describe)
    
    # Handle lists and tables (Nushell's structured data)
    if ($value_type | str starts-with "list") or ($value_type | str starts-with "table") {
      # Handle empty collections
      if ($value | length) == 0 {
        { "L": [] }  # Empty List in DynamoDB
      } else {
        let first_item = ($value | first)
        let first_type = ($first_item | describe)
        
        # Check if all items are the same primitive type
        # 'all' checks if all items in a list satisfy a condition
        let all_same_type = ($value | all { |item| ($item | describe) == $first_type })
        
        if $all_same_type {
          # Use DynamoDB Sets for homogeneous primitive types
          match $first_type {
            "string" => { "SS": $value },  # String Set
            "int" | "float" => { "NS": ($value | each { |n| $n | into string }) },  # Number Set
            _ => { "L": ($value | each { |item| convert_to_dynamodb_value $item }) }   # Mixed List
          }
        } else {
          # Mixed types - use List format with recursive conversion
          { "L": ($value | each { |item| convert_to_dynamodb_value $item }) }
        }
      }
    } else if ($value_type | str starts-with "record") {
      # Convert nested record to Map (M) format recursively
      let converted_map = ($value | transpose key value | reduce -f {} { |row, acc|
        let nested_value = convert_to_dynamodb_value $row.value
        $acc | insert $row.key $nested_value
      })
      { "M": $converted_map }  # Map type in DynamoDB
    } else {
      # Handle primitive types
      match $value_type {
        "string" => { "S": $value },                        # String
        "int" => { "N": ($value | into string) },          # Number (as string)
        "float" => { "N": ($value | into string) },        # Number (as string)
        "bool" => { "BOOL": $value },                      # Boolean
        _ => { "S": ($value | into string) }               # Fallback to string
      }
    }
  }
}

# Functional helper for recursive batch writing with retry
def batch_write_recursive [
  table_name: string
  aws_region: string
  remaining_items: list<record>
  retry_count: int
  max_retries: int
]: nothing -> nothing {
  if ($remaining_items | length) == 0 {
    return  # Success - all items processed
  }
  
  if $retry_count > $max_retries {
    let remaining_count = ($remaining_items | length)
    error make { msg: $"Failed to process ($remaining_count) items after ($max_retries) retries" }
  }
  
  let batch_request = {
    "RequestItems": {
      $table_name: $remaining_items
    }
  }
  
  let result = try {
    with_temp_file $batch_request { |temp_file|
      let aws_result = (^aws dynamodb batch-write-item --cli-input-json $"file://($temp_file)" --region $aws_region | complete)
      
      if $aws_result.exit_code != 0 {
        { success: false, error: $"Batch write failed: ($aws_result.stderr)" }
      } else {
        let response = $aws_result.stdout | from json
        { success: true, response: $response }
      }
    }
  } catch { |error|
    { success: false, error: $error.msg }
  }
  
  if $result.success {
    let response = $result.response
    
    # Check for unprocessed items - simplified logic
    let unprocessed = $response | get -o UnprocessedItems
    if $unprocessed != null {
      if ($table_name in ($unprocessed | columns)) {
        let remaining_items = ($unprocessed | get $table_name)
        if ($remaining_items | length) > 0 {
          print $"  Retrying unprocessed items..."
          # Exponential backoff: wait 2^retry_count seconds
          let wait_time = ([1, 2, 4, 8, 16] | get $retry_count)
          print $"  Waiting ($wait_time) seconds before retry..."
          sleep ($wait_time * 1sec)
          
          batch_write_recursive $table_name $aws_region $remaining_items ($retry_count + 1) $max_retries
        }
      }
    }
    # else: All items processed successfully
  } else {
    # Error occurred - retry with original items
    if $retry_count < $max_retries {
      let current_attempt = ($retry_count + 1)
      let retry_message = $"  Batch write error, retrying " + "(attempt " + ($current_attempt | into string) + "/" + ($max_retries | into string) + "): " + $result.error
      print $retry_message
      
      let wait_time = ([1, 2, 4, 8, 16] | get $retry_count)
      sleep ($wait_time * 1sec)
      
      batch_write_recursive $table_name $aws_region $remaining_items ($retry_count + 1) $max_retries
    } else {
      error make { msg: $"Batch write failed after ($max_retries) retries: ($result.error)" }
    }
  }
}

def batch_write_with_retry [
  table_name: string
  dynamodb_items: list<record>
  --region: string  # AWS region
  --max-retries: int = 3  # Maximum number of retries
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  batch_write_recursive $table_name $aws_region $dynamodb_items 0 $max_retries
}

def batch_write [
  table_name: string
  items: list<record>
  --region: string  # AWS region
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  let items_count = ($items | length)
  print $"Writing ($items_count) items to ($table_name)..."
  
  let batches = ($items | chunks 25)
  let total_batches = ($batches | length)
  
  $batches | enumerate | each { |batch_data|
    let batch_num = ($batch_data.index + 1)
    let batch = $batch_data.item
    let batch_size = ($batch | length)
    print $"  Processing batch ($batch_num)/($total_batches) - ($batch_size) items"
    
    let dynamodb_items = ($batch | each { |item|
      let converted_item = ($item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = convert_to_dynamodb_value $field_value
        $acc | insert $field_name $dynamodb_value
      })
      { "PutRequest": { "Item": $converted_item } }
    })
    
    batch_write_with_retry $table_name $dynamodb_items --region $aws_region
  } | ignore
  
  print $"Successfully wrote all ($items_count) items to ($table_name)"
}

def delete_all [
  table_name: string
  --region: string  # AWS region
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  print $"Deleting all items from ($table_name)..."
  
  # Get the table's key schema dynamically
  let table_info = get_table_key_schema $table_name --region $aws_region
  let key_schema = $table_info.key_schema
  let attribute_definitions = $table_info.attribute_definitions
  
  let items = scan_table $table_name --region $aws_region
  
  if ($items | length) == 0 {
    print "Table is already empty"
    return
  }
  
  let items_to_delete = ($items | length)
  print $"Deleting ($items_to_delete) items from ($table_name)..."
  let batches = ($items | chunks 25)
  
  let total_batches = ($batches | length)
  
  $batches | enumerate | each { |batch_data|
    let batch_num = ($batch_data.index + 1)
    let batch = $batch_data.item
    let batch_size = ($batch | length)
    print $"  Processing delete batch ($batch_num)/($total_batches) - ($batch_size) items"
    
    let delete_requests = ($batch | each { |item|
      let key_object = get_key_attributes_for_item $item $key_schema $attribute_definitions
      {
        "DeleteRequest": {
          "Key": $key_object
        }
      }
    })
    
    batch_write_with_retry $table_name $delete_requests --region $aws_region
  } | ignore
}

# Data Operations

# Automatically detects file format and extracts data for processing
# Supports both CSV and JSON formats with intelligent format detection
# ✅ SAFE FUNCTION: Only reads files, no side effects
def detect_and_process [file: string]: nothing -> list<record> {
  # Check file extension for format detection
  if ($file | str ends-with ".csv") {
    # Nushell automatically detects and parses CSV format
    open $file
  } else {
    # Handle JSON files (with or without .json extension)
    let data = try {
      # Try to parse as JSON first
      open $file | from json
    } catch {
      # Fallback: open as raw text if JSON parsing fails
      open $file
    }
    
    # Handle different JSON structures:
    # 1. Snapshot format: {"metadata": {...}, "data": [...]}
    # 2. Raw array format: [{...}, {...}, ...]
    # '=~' is the regex match operator
    if ($data | describe) =~ "record" and ("data" in ($data | columns)) {
      $data.data  # Extract data array from snapshot format
    } else {
      $data       # Use raw array format as-is
    }
  }
}

# Creates a snapshot file with table data and metadata
# ✅ SAFE FUNCTION: Only reads data, creates backup files
def save_snapshot [
  table_name: string        # DynamoDB table to snapshot
  file: string             # Output file path
  --region: string         # AWS region
  --exact-count = false    # Use exact count (slower, more expensive)
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  # Get table description for metadata
  let description_result = (^aws dynamodb describe-table --table-name $table_name --region $aws_region | complete)
  
  if $description_result.exit_code != 0 {
    handle_aws_error $description_result.stderr "describe-table"
  }
  
  let description = $description_result.stdout | from json
  let items = scan_table $table_name --region $aws_region
  
  let item_count = if $exact_count {
    ($items | length)
  } else {
    $description.Table.ItemCount
  }
  
  let snapshot = {
    metadata: {
      table_name: $table_name,
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: $item_count,
      item_count_exact: $exact_count,
      tool: "dynamodb-nu-loader",
      version: "1.0"
    },
    data: $items
  }
  
  $snapshot | to json | save $file
}

# CLI Commands

# Creates a backup snapshot of all table data
# ✅ SAFE COMMAND: Only reads data from DynamoDB, creates backup files
# ⚠️ --dry-run flag: Counts items but doesn't create any files
def "main snapshot" [
  file?: string                 # Output file (default: snapshots/snapshot-TIMESTAMP.json)
  --table: string              # DynamoDB table name  
  --region: string             # AWS region
  --snapshots-dir: string      # Snapshots directory
  --dry-run                    # Count items exactly but don't save snapshot
  --exact-count                # Use exact count (slower, more expensive)
]: nothing -> nothing {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  let snapshots_directory = $snapshots_dir | default $env.SNAPSHOTS_DIR?
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  if $dry_run {
    print $"Performing dry run - counting items in table ($table_name)..."
    let items = scan_table $table_name --region $aws_region
    let exact_count = ($items | length)
    print $"Exact item count: ($exact_count)"
    return
  }
  
  if $snapshots_directory == null {
    error make { msg: "Snapshots directory must be provided via --snapshots-dir flag or SNAPSHOTS_DIR environment variable" }
  }
  
  print $"Creating snapshot of table ($table_name)..."
  
  # Create snapshots directory if it doesn't exist
  if not ($snapshots_directory | path exists) {
    mkdir $snapshots_directory
  }
  
  let output_file = if $file != null {
    $file
  } else {
    let timestamp = (date now | format date "%Y%m%d_%H%M%S")
    $"($snapshots_directory)/snapshot_($timestamp).json"
  }
  
  save_snapshot $table_name $output_file --region $aws_region --exact-count $exact_count
  let items = scan_table $table_name --region $aws_region
  let saved_items = ($items | length)
  print $"Snapshot saved to ($output_file) - JSON format, ($saved_items) items"
}

# Restores table data from a backup file
# ⚠️ DESTRUCTIVE COMMAND: CLEARS ALL EXISTING DATA before restoring
# This command will delete every item in the table, then load data from the file
def "main restore" [
  file: string       # Snapshot file to restore from
  --table: string   # DynamoDB table name
  --region: string  # AWS region
]: nothing -> nothing {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  print $"Restoring table ($table_name) from ($file)..."
  
  if not ($file | path exists) {
    error make { msg: $"File not found: ($file)" }
  }
  
  # Load items from backup file (supports JSON and CSV)
  let items = detect_and_process $file
  
  # ⚠️ DESTRUCTIVE OPERATION: This deletes ALL existing table data
  print $"Clearing table ($table_name)..."
  delete_all $table_name --region $aws_region
  
  # Load the backup data into the now-empty table
  let restore_count = ($items | length)
  print $"Restoring ($restore_count) items to ($table_name)..."
  batch_write $table_name $items --region $aws_region
  print "Restore completed successfully"
}

# Deletes all items from the DynamoDB table
# ⚠️ DESTRUCTIVE COMMAND: PERMANENTLY DELETES ALL TABLE DATA
# This is the most dangerous command - it removes every item from the table
def "main wipe" [
  --force (-f)     # Skip confirmation prompt (dangerous!)
  --table: string  # DynamoDB table name
  --region: string # AWS region
]: nothing -> nothing {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  # Safety check - require user confirmation unless --force is used
  if not $force {
    print $"Are you sure you want to delete all data from ($table_name)? y/N: " --no-newline
    # 'input' waits for user input from stdin
    let confirm = (input)
    if $confirm != "y" {
      print "Operation cancelled"
      return
    }
  }
  
  # ⚠️ DESTRUCTIVE OPERATION: This permanently deletes all table data
  print $"Wiping all data from table ($table_name)..."
  delete_all $table_name --region $aws_region
  print "Table wiped successfully"
}

# Loads test/seed data into the table
# ⚠️ DESTRUCTIVE COMMAND: CLEARS ALL EXISTING DATA before loading seed data
# This command is useful for setting up fresh test data for development
def "main seed" [
  file?: string    # Seed data file (default: seed-data.json)
  --table: string  # DynamoDB table name
  --region: string # AWS region
]: nothing -> nothing {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  let seed_file = if $file != null { $file } else { "seed-data.json" }
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  if not ($seed_file | path exists) {
    error make { msg: $"Seed file not found: ($seed_file). Create a JSON file with your seed data." }
  }
  
  print $"Loading seed data from ($seed_file)..."
  # Load seed data from file (supports JSON and CSV formats)
  let seed_data = detect_and_process $seed_file
  
  # ⚠️ DESTRUCTIVE OPERATION: This deletes ALL existing table data first
  print $"Clearing table ($table_name)..."
  delete_all $table_name --region $aws_region
  
  # Load the seed data into the now-empty table
  let seed_count = ($seed_data | length)
  print $"Loading ($seed_count) items into ($table_name)..."
  batch_write $table_name $seed_data --region $aws_region
  print $"Seeded ($seed_count) items successfully"
}

# Shows table information and approximate item count
# ✅ SAFE COMMAND: Only reads table metadata, no data modification
def "main status" [
  --table: string  # DynamoDB table name
  --region: string # AWS region
]: nothing -> nothing {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  let result = try {
    (^aws dynamodb describe-table --table-name $table_name --region $aws_region | complete)
  } catch { |error|
    error make { msg: $"Error getting table status for ($table_name): ($error.msg)" }
  }
  
  if $result.exit_code != 0 {
    handle_aws_error $result.stderr "describe-table"
  }
  
  let description = ($result.stdout | from json)
  
  let table_name_display = $description.Table.TableName
  let table_status = $description.Table.TableStatus
  let item_count = $description.Table.ItemCount
  let table_size = $description.Table.TableSizeBytes
  let creation_time = $description.Table.CreationDateTime
  
  print $"Table: ($table_name_display)"
  print $"Status: ($table_status)"
  print ("Items (approximate): " + ($item_count | into string))
  print $"Size: ($table_size) bytes"
  print $"Created: ($creation_time)"
  print ""
  print "ℹ️  Item count is approximate and updated by AWS every ~6 hours"
  print "   For exact count, use: nu main.nu snapshot --dry-run"
}