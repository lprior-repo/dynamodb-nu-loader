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
  print "    restore <file>      Restore data from a snapshot file (JSON/CSV)"
  print "    wipe [--force]      Delete all items from the DynamoDB table"
  print "    seed                Load default seed data into the table"
  print "    status              Show table status and item count"
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
  print ""
  print "🔗 More info: Check README.md for installation and setup"
}

# Show enhanced help when called without arguments
def main []: nothing -> nothing {
  show_enhanced_help
}

# AWS DynamoDB Operations
def scan_table [
  table_name: string
  --region: string  # AWS region
]: nothing -> list<record> {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  ^aws dynamodb scan --table-name $table_name --region $aws_region | from json | get Items | each { |item|
    let converted = {}
    for field in ($item | columns) {
      let value = $item | get $field
      let field_value = if "S" in ($value | columns) {
        $value.S
      } else if "N" in ($value | columns) {
        $value.N | into float
      } else if "BOOL" in ($value | columns) {
        $value.BOOL
      } else if "SS" in ($value | columns) {
        $value.SS
      } else if "NS" in ($value | columns) {
        $value.NS | each { |n| $n | into float }
      } else if "L" in ($value | columns) {
        $value.L
      } else if "M" in ($value | columns) {
        $value.M
      } else {
        $value
      }
      $converted | insert $field $field_value
    }
    $converted
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
  let batches = ($items | chunks 25)
  
  for batch in $batches {
    let dynamodb_items = ($batch | each { |item|
      let converted_item = ($item | transpose key value | reduce -f {} { |row, acc|
        let field_name = $row.key
        let field_value = $row.value
        let dynamodb_value = match ($field_value | describe) {
          "string" => { "S": $field_value },
          "int" => { "N": ($field_value | into string) },
          "float" => { "N": ($field_value | into string) },
          "bool" => { "BOOL": $field_value },
          "list" => { "SS": $field_value },
          _ => { "S": ($field_value | into string) }
        }
        $acc | insert $field_name $dynamodb_value
      })
      { "PutRequest": { "Item": $converted_item } }
    })
    
    let batch_request = {
      "RequestItems": {
        $table_name: $dynamodb_items
      }
    }
    
    let temp_file = $"/tmp/batch_request_(random chars --length 8).json"
    $batch_request | to json | save $temp_file
    
    try {
      ^aws dynamodb batch-write-item --cli-input-json $"file://($temp_file)" --region $aws_region
      rm $temp_file
    } catch { |error|
      rm $temp_file
      error make { msg: $"Batch write failed: ($error.msg)" }
    }
  }
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
  let items = scan_table $table_name --region $aws_region
  
  if ($items | length) == 0 {
    print "Table is already empty"
    return
  }
  
  print $"Deleting ($items | length) items from ($table_name)..."
  let batches = ($items | chunks 25)
  
  for batch in $batches {
    let delete_requests = ($batch | each { |item|
      {
        "DeleteRequest": {
          "Key": {
            "id": { "S": $item.id },
            "sort_key": { "S": $item.sort_key }
          }
        }
      }
    })
    
    let delete_request = {
      "RequestItems": {
        $table_name: $delete_requests
      }
    }
    
    let temp_file = $"/tmp/delete_request_(random chars --length 8).json"
    $delete_request | to json | save $temp_file
    
    try {
      let result = ^aws dynamodb batch-write-item --cli-input-json $"file://($temp_file)" --region $aws_region
      $result | from json
      rm $temp_file
    } catch { |error|
      rm $temp_file
      error make { msg: $"Batch delete failed: ($error.msg)" }
    }
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
]: nothing -> nothing {
  let aws_region = $region | default $env.AWS_REGION?
  
  if $aws_region == null {
    error make { msg: "AWS region must be provided via --region flag or AWS_REGION environment variable" }
  }
  let items = scan_table $table_name --region $aws_region
  let snapshot = {
    metadata: {
      table_name: $table_name,
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S"),
      item_count: ($items | length),
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
  
  save_snapshot $table_name $output_file --region $aws_region
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
  
  let description = ^aws dynamodb describe-table --table-name $table_name --region $aws_region | from json
  let items = scan_table $table_name --region $aws_region
  
  let table_info = {
    table_name: $description.Table.TableName,
    status: $description.Table.TableStatus,
    item_count: ($items | length),
    creation_time: $description.Table.CreationDateTime,
    size_bytes: $description.Table.TableSizeBytes
  }
  
  print $"Table: ($table_info.table_name)"
  print $"Status: ($table_info.status)"
  print $"Items: ($table_info.item_count)"
  print $"Size: ($table_info.size_bytes) bytes"
  print $"Created: ($table_info.creation_time)"
  
  $table_info
}