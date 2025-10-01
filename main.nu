#!/usr/bin/env nu

# DynamoDB Nu-Loader: Minimal test data management tool
# Provides snapshot, restore, wipe, and seed operations for DynamoDB tables

# Enhanced help function
def show_enhanced_help []: nothing -> nothing {
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
def main []: nothing -> nothing {
  show_enhanced_help
}

# Enhanced Error Handling Functions
def with_temp_file [
  data: any
  operation: closure
]: nothing -> any {
  let temp_file = $"/tmp/dynamodb_nu_loader_(random chars --length 12).json"
  
  try {
    # Save data to temp file
    $data | to json | save $temp_file
    
    # Execute operation with temp file
    do $operation $temp_file
  } catch { |error|
    # Ensure cleanup even on error
    if ($temp_file | path exists) {
      try { rm $temp_file } catch { |_| }
    }
    # Re-throw the original error
    error make { msg: $error.msg }
  }
  
  # Normal cleanup
  if ($temp_file | path exists) {
    try { rm $temp_file } catch { |_| }
  }
}
def handle_aws_error [
  error_output: string
  operation: string
]: nothing -> nothing {
  # Parse common AWS error patterns from CLI output
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
    # Generic error with the original output
    error make { 
      msg: $"AWS operation failed during ($operation): ($error_output)"
    }
  }
}

def validate_aws_credentials []: nothing -> nothing {
  try {
    let result = ^aws sts get-caller-identity
    let exit_code = $env.LAST_EXIT_CODE
    
    if $exit_code != 0 {
      error make { 
        msg: "AWS credentials are not configured or invalid. Run 'aws configure' to set up your credentials."
      }
    }
    
    print "✅ AWS credentials validated"
  } catch { |error|
    error make { 
      msg: $"Failed to validate AWS credentials: ($error.msg). Ensure AWS CLI is installed and credentials are configured."
    }
  }
}

def validate_table_exists [
  table_name: string
  region: string
]: nothing -> nothing {
  try {
    let result = ^aws dynamodb describe-table --table-name $table_name --region $region
    let exit_code = $env.LAST_EXIT_CODE
    
    if $exit_code != 0 {
      error make { msg: $"Failed to describe table ($table_name). Exit code: ($exit_code)" }
    }
    
    print $"✅ Table ($table_name) exists and is accessible"
  } catch { |error|
    error make { 
      msg: $"Table validation failed: ($error.msg)"
    }
  }
}

# AWS DynamoDB Operations
def get_table_key_schema [
  table_name: string
  --region: string  # AWS region
]: nothing -> record {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  try {
    let result = ^aws dynamodb describe-table --table-name $table_name --region $aws_region
    let exit_code = $env.LAST_EXIT_CODE
    
    if $exit_code != 0 {
      error make { msg: $"Failed to describe table ($table_name). Exit code: ($exit_code)" }
    }
    
    let table_description = $result | from json
    {
      key_schema: $table_description.Table.KeySchema,
      attribute_definitions: $table_description.Table.AttributeDefinitions
    }
  } catch { |error|
    error make { msg: $"Error describing table ($table_name): ($error.msg)" }
  }
}

def get_key_attributes_for_item [
  item: record
  key_schema: list<record>
  attribute_definitions: list<record>
]: nothing -> record {
  # Build the key object dynamically based on the table's schema
  $key_schema | reduce -f {} { |key_def, acc|
    let attr_name = $key_def.AttributeName
    let attr_value = $item | get $attr_name
    
    # Find the attribute type from the table definition
    let attr_type = ($attribute_definitions | where AttributeName == $attr_name | first).AttributeType
    
    let dynamodb_value = match $attr_type {
      "S" => { "S": ($attr_value | into string) },
      "N" => { "N": ($attr_value | into string) },
      "B" => { "B": $attr_value }
    }
    
    $acc | insert $attr_name $dynamodb_value
  }
}

def convert_from_dynamodb_value [dynamodb_value: record]: nothing -> any {
  let value_type = ($dynamodb_value | columns | first)
  let value_data = $dynamodb_value | get $value_type
  
  match $value_type {
    "S" => $value_data,
    "N" => {
      # Try to parse as int first, then float
      try {
        $value_data | into int
      } catch {
        $value_data | into float
      }
    },
    "BOOL" => $value_data,
    "NULL" => null,
    "SS" => $value_data,
    "NS" => ($value_data | each { |n| 
      try {
        $n | into int
      } catch {
        $n | into float
      }
    }),
    "BS" => $value_data,
    "L" => ($value_data | each { |item| convert_from_dynamodb_value $item }),
    "M" => {
      # Convert nested map recursively
      let converted_map = ($value_data | transpose key value | reduce -f {} { |row, acc|
        let converted_value = convert_from_dynamodb_value $row.value
        $acc | insert $row.key $converted_value
      })
      $converted_map
    },
    _ => $value_data  # Fallback for unknown types
  }
}

def scan_table_page [
  table_name: string
  --region: string  # AWS region
  --exclusive-start-key: any  # For pagination (can be null or record)
]: nothing -> record {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  try {
    let result = if $exclusive_start_key == null {
      ^aws dynamodb scan --table-name $table_name --region $aws_region
    } else {
      with_temp_file $exclusive_start_key { |temp_file|
        ^aws dynamodb scan --table-name $table_name --region $aws_region --exclusive-start-key $"file://($temp_file)"
      }
    }
    
    let exit_code = $env.LAST_EXIT_CODE
    
    if $exit_code != 0 {
      error make { msg: $"Failed to scan table ($table_name). Exit code: ($exit_code)" }
    }
    
    let scan_result = $result | from json
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

def scan_table [
  table_name: string
  --region: string  # AWS region
]: nothing -> list<record> {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  print $"Scanning table ($table_name)..."
  
  mut all_items = []
  mut last_evaluated_key = null
  mut total_scanned = 0
  mut page_count = 0
  
  loop {
    let page_result = scan_table_page $table_name --region $aws_region --exclusive-start-key $last_evaluated_key
    
    $all_items = ($all_items | append $page_result.items)
    $total_scanned = $total_scanned + $page_result.scanned_count
    $page_count = $page_count + 1
    
    print $"  Page ($page_count): Found ($page_result.count) items (scanned ($page_result.scanned_count))"
    
    $last_evaluated_key = $page_result.last_evaluated_key
    
    if $last_evaluated_key == null {
      break
    }
  }
  
  print $"Scan complete: ($all_items | length) total items across ($page_count) pages"
  $all_items
}

def convert_to_dynamodb_value [value: any]: any -> record {
  if $value == null {
    { "NULL": true }
  } else {
    let value_type = ($value | describe)
    if ($value_type | str starts-with "list") or ($value_type | str starts-with "table") {
      # Handle list/table types
      if ($value | length) == 0 {
        { "L": [] }
      } else {
        let first_item = ($value | first)
        let first_type = ($first_item | describe)
        
        # Check if all items are the same primitive type
        let all_same_type = ($value | all { |item| ($item | describe) == $first_type })
        
        if $all_same_type {
          match $first_type {
            "string" => { "SS": $value },
            "int" | "float" => { "NS": ($value | each { |n| $n | into string }) },
            _ => { "L": ($value | each { |item| convert_to_dynamodb_value $item }) }
          }
        } else {
          # Mixed types - use List format
          { "L": ($value | each { |item| convert_to_dynamodb_value $item }) }
        }
      }
    } else if ($value_type | str starts-with "record") {
      # Convert nested record to Map (M) format
      let converted_map = ($value | transpose key value | reduce -f {} { |row, acc|
        let nested_value = convert_to_dynamodb_value $row.value
        $acc | insert $row.key $nested_value
      })
      { "M": $converted_map }
    } else {
      # Handle primitive types
      match $value_type {
        "string" => { "S": $value },
        "int" => { "N": ($value | into string) },
        "float" => { "N": ($value | into string) },
        "bool" => { "BOOL": $value },
        _ => { "S": ($value | into string) }  # Fallback to string
      }
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
  
  mut remaining_items = $dynamodb_items
  mut retry_count = 0
  
  while (($remaining_items | length) > 0 and $retry_count <= $max_retries) {
    let batch_request = {
      "RequestItems": {
        $table_name: $remaining_items
      }
    }
    
    let result = try {
      with_temp_file $batch_request { |temp_file|
        let aws_result = ^aws dynamodb batch-write-item --cli-input-json $"file://($temp_file)" --region $aws_region
        let exit_code = $env.LAST_EXIT_CODE
        
        if $exit_code != 0 {
          { success: false, error: $"Batch write failed with exit code: ($exit_code)" }
        } else {
          let response = $aws_result | from json
          { success: true, response: $response }
        }
      }
    } catch { |error|
      { success: false, error: $error.msg }
    }
    
    if $result.success {
      let response = $result.response
      
      # Check for unprocessed items
      let unprocessed = $response | get -o UnprocessedItems
      if $unprocessed != null and ($table_name in ($unprocessed | columns)) {
        $remaining_items = $unprocessed | get $table_name
        $retry_count = $retry_count + 1
        
        if ($remaining_items | length) > 0 {
          print $"  Retrying ($remaining_items | length) unprocessed items (attempt ($retry_count)/($max_retries))"
          
          # Exponential backoff: wait 2^retry_count seconds
          let wait_time = ([1, 2, 4, 8, 16] | get ($retry_count - 1))
          print $"  Waiting ($wait_time) seconds before retry..."
          sleep ($wait_time * 1sec)
        } else {
          # No more unprocessed items
          break
        }
      } else {
        # All items processed successfully
        break
      }
    } else {
      # Error occurred
      if $retry_count < $max_retries {
        $retry_count = $retry_count + 1
        print $"  Batch write error, retrying (attempt ($retry_count)/($max_retries)): ($result.error)"
        
        let wait_time = ([1, 2, 4, 8, 16] | get ($retry_count - 1))
        sleep ($wait_time * 1sec)
      } else {
        error make { msg: $"Batch write failed after ($max_retries) retries: ($result.error)" }
      }
    }
  }
  
  if ($remaining_items | length) > 0 {
    error make { msg: $"Failed to process ($remaining_items | length) items after ($max_retries) retries" }
  }
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
  
  print $"Writing ($items | length) items to ($table_name)..."
  
  let batches = ($items | chunks 25)
  let total_batches = ($batches | length)
  mut batch_num = 0
  
  for batch in $batches {
    $batch_num = $batch_num + 1
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
  }
  
  print $"Successfully wrote all ($items | length) items to ($table_name)"
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
  
  print $"Deleting ($items | length) items from ($table_name)..."
  let batches = ($items | chunks 25)
  
  let total_batches = ($batches | length)
  mut batch_num = 0
  
  for batch in $batches {
    $batch_num = $batch_num + 1
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
  }
}

# Data Operations
def detect_and_process [file: string]: nothing -> list<record> {
  if ($file | str ends-with ".csv") {
    open $file  # Nushell auto-detects CSV
  } else {
    # Parse as JSON
    let data = open $file | from json
    # Check if data is a record with 'data' field (snapshot format)
    if ($data | describe) =~ "record" and ("data" in ($data | columns)) {
      $data.data  # JSON snapshot format
    } else {
      $data  # Raw JSON array
    }
  }
}

def save_snapshot [
  table_name: string
  file: string
  --region: string  # AWS region
  --exact-count: bool = false  # Use exact count (slower, more expensive)
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  # Get table description for metadata
  let description_result = ^aws dynamodb describe-table --table-name $table_name --region $aws_region
  let exit_code = $env.LAST_EXIT_CODE
  
  if $exit_code != 0 {
    error make { msg: $"Failed to describe table ($table_name). Exit code: ($exit_code)" }
  }
  
  let description = $description_result | from json
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
def "main snapshot" [
  file?: string  # Output file (default: snapshots/snapshot-TIMESTAMP.json)
  --table: string  # DynamoDB table name
  --region: string  # AWS region
  --snapshots-dir: string  # Snapshots directory
  --dry-run: bool = false  # Count items exactly but don't save snapshot
  --exact-count: bool = false  # Use exact count (slower, more expensive)
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
  print $"Snapshot saved to ($output_file) (JSON format, ($items | length) items)"
}

def "main restore" [
  file: string  # Snapshot file to restore from
  --table: string  # DynamoDB table name
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
  
  let items = detect_and_process $file
  print $"Clearing table ($table_name)..."
  delete_all $table_name --region $aws_region
  
  print $"Restoring ($items | length) items to ($table_name)..."
  batch_write $table_name $items --region $aws_region
  print "Restore completed successfully"
}

def "main wipe" [
  --force (-f)  # Skip confirmation prompt
  --table: string  # DynamoDB table name
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
  
  if not $force {
    print $"Are you sure you want to delete all data from ($table_name)? y/N: " --no-newline
    let confirm = (input)
    if $confirm != "y" {
      print "Operation cancelled"
      return
    }
  }
  
  print $"Wiping all data from table ($table_name)..."
  delete_all $table_name --region $aws_region
  print "Table wiped successfully"
}

def "main seed" [
  file?: string  # Seed data file (default: seed-data.json)
  --table: string  # DynamoDB table name
  --region: string  # AWS region
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
  let seed_data = detect_and_process $seed_file
  
  print $"Clearing table ($table_name)..."
  delete_all $table_name --region $aws_region
  
  print $"Loading ($seed_data | length) items into ($table_name)..."
  batch_write $table_name $seed_data --region $aws_region
  print $"Seeded ($seed_data | length) items successfully"
}

def "main status" [
  --table: string  # DynamoDB table name
  --region: string  # AWS region
]: nothing -> record {
  let table_name = $table | default $env.TABLE_NAME?
  let aws_region = $region | default $env.AWS_REGION?
  
  if $table_name == null {
    error make { msg: "Table name must be provided via --table flag or TABLE_NAME environment variable" }
  }
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  
  try {
    let result = ^aws dynamodb describe-table --table-name $table_name --region $aws_region
    let exit_code = $env.LAST_EXIT_CODE
    
    if $exit_code != 0 {
      error make { msg: $"Failed to describe table ($table_name). Exit code: ($exit_code)" }
    }
    
    let description = $result | from json
    
    let table_info = {
      table_name: $description.Table.TableName,
      status: $description.Table.TableStatus,
      item_count_approx: $description.Table.ItemCount,
      creation_time: $description.Table.CreationDateTime,
      size_bytes: $description.Table.TableSizeBytes
    }
    
    print $"Table: ($table_info.table_name)"
    print $"Status: ($table_info.status)"
    print $"Items (approximate): ($table_info.item_count_approx)"
    print $"Size: ($table_info.size_bytes) bytes"
    print $"Created: ($table_info.creation_time)"
    print ""
    print "ℹ️  Item count is approximate and updated by AWS every ~6 hours"
    print "   For exact count, use: nu main.nu snapshot --dry-run"
    
    $table_info
  } catch { |error|
    error make { msg: $"Error getting table status for ($table_name): ($error.msg)" }
  }
}