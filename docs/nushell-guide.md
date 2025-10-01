# Nushell Guide for DynamoDB Nu-Loader

Complete guide to understanding the Nushell concepts used in this project.

## 🚀 New to Nushell?

This guide explains the Nushell concepts used throughout DynamoDB Nu-Loader's code. Each concept links to official Nushell documentation for deeper learning.

## 📚 Core Concepts

### Functions and Commands

**[Custom Commands](https://www.nushell.sh/book/custom_commands.html)**
```nu
# Define a function with type annotations
def my_function [
  param1: string    # Parameter with type
  --flag: string   # Optional flag parameter
]: nothing -> list {  # Return type
  # Function body here
}
```

**Used in our code:**
- `main snapshot`, `main restore`, etc. - CLI subcommands
- `convert_to_dynamodb_value` - Data conversion functions
- `validate_aws_credentials` - Utility functions

### Data Types and Structures

**[Types of Data](https://www.nushell.sh/book/types_of_data.html)**
```nu
let my_string = "hello"           # string
let my_number = 42               # int
let my_float = 3.14             # float
let my_bool = true              # bool
let my_list = [1, 2, 3]         # list
let my_record = {name: "John"}   # record (like JSON object)
```

**[Records](https://www.nushell.sh/book/types_of_data.html#records)**
```nu
# Create record
let user = {
  id: "user1",
  name: "John Doe",
  active: true
}

# Access fields
$user.name          # "John Doe"
$user | get name     # "John Doe"
```

### Pipeline Operations

**[Pipelines](https://www.nushell.sh/book/pipelines.html)**
```nu
# Data flows left to right through the pipeline
$data 
| to json              # Convert to JSON string
| save "output.json"   # Save to file

# Multi-step processing
$items 
| where active == true   # Filter active items
| select name email     # Select specific columns
| sort-by name          # Sort by name
```

**Common pipeline commands in our code:**
- `| to json` - Convert data to JSON format
- `| from json` - Parse JSON strings
- `| where` - Filter data
- `| each { }` - Transform each item
- `| reduce` - Accumulate values

### Environment Variables

**[Environment](https://www.nushell.sh/book/environment.html)**
```nu
# Access environment variables
$env.TABLE_NAME         # Get TABLE_NAME env var
$env.AWS_REGION?        # Safe access (won't error if missing)

# Set environment variables
$env.MY_VAR = "value"
```

**Used for configuration:**
- `$env.TABLE_NAME` - Default table name
- `$env.AWS_REGION` - Default AWS region
- `$env.SNAPSHOTS_DIR` - Default snapshots directory

### Error Handling

**[Working with Errors](https://www.nushell.sh/book/working_with_errors.html)**
```nu
# Try/catch pattern
let result = try {
  # Code that might fail
  some_risky_operation
} catch { |error|
  # Handle the error
  print $"Error: ($error.msg)"
}

# Create custom errors
error make { msg: "Something went wrong" }
```

**Used throughout our code for:**
- AWS API error handling
- File operation safety
- Input validation

### External Commands

**[External Commands](https://www.nushell.sh/book/externs.html)**
```nu
# Run external commands with ^
^aws dynamodb scan --table-name my-table

# Capture output with complete
let result = (^aws sts get-caller-identity | complete)
$result.exit_code    # 0 for success
$result.stdout       # Command output
$result.stderr       # Error output
```

**AWS CLI Integration:**
- `^aws dynamodb scan` - Read table data
- `^aws dynamodb batch-write-item` - Write data
- `^aws dynamodb describe-table` - Get table info

### String Operations

**[Working with Strings](https://www.nushell.sh/book/working_with_strings.html)**
```nu
# String interpolation
let name = "World"
$"Hello ($name)!"        # "Hello World!"

# String methods
"filename.json" | str ends-with ".json"    # true
"  text  " | str trim                      # "text"
"TEXT" | str downcase                      # "text"
```

### Control Flow

**[Control Flow](https://www.nushell.sh/book/control_flow.html)**
```nu
# If/else
if $condition {
  print "true"
} else {
  print "false"
}

# Match (pattern matching)
match $value {
  "option1" => { print "first" },
  "option2" => { print "second" },
  _ => { print "default" }
}
```

### Functional Programming

**[Working with Lists](https://www.nushell.sh/book/working_with_lists.html)**
```nu
# Transform each item
$list | each { |item| $item * 2 }

# Filter items
$list | where $it > 5

# Reduce/fold
$list | reduce -f 0 { |item, acc| $acc + $item }

# Find items
$list | find "search term"
```

**Key functional patterns in our code:**
- **Immutability**: Data isn't modified in-place
- **Pure functions**: Same input always produces same output
- **Composition**: Small functions combined for complex operations

### Data Conversion

**[Formats](https://www.nushell.sh/book/loading_data.html)**
```nu
# JSON
$data | to json           # Convert to JSON
$json_string | from json  # Parse JSON

# CSV
open "data.csv"           # Auto-detects CSV
$data | to csv            # Convert to CSV

# Other formats
$data | to yaml
$data | to toml
```

## 🔍 Understanding Our Code

### Function Signatures
```nu
def scan_table [
  table_name: string        # Required parameter
  --region: string         # Optional flag
]: nothing -> list<record> # Returns list of records
```

### Error Handling Patterns
```nu
try {
  let result = (^aws dynamodb scan --table-name $table | complete)
  if $result.exit_code != 0 {
    handle_aws_error $result.stderr "scan"
  }
  # Process successful result
} catch { |error|
  error make { msg: $"Operation failed: ($error.msg)" }
}
```

### Data Transformation
```nu
# Convert Nushell data to DynamoDB format
$items | each { |item|
  $item | transpose key value | reduce -f {} { |row, acc|
    let converted = convert_to_dynamodb_value $row.value
    $acc | insert $row.key $converted
  }
}
```

### Batch Processing
```nu
# Process in chunks of 25 (DynamoDB limit)
$items 
| chunks 25 
| enumerate 
| each { |batch_data|
    let batch_num = ($batch_data.index + 1)
    let batch = $batch_data.item
    process_batch $batch $batch_num
  }
```

## 📖 Learning Resources

### Official Documentation
- **[Nushell Book](https://www.nushell.sh/book/)** - Complete guide
- **[Command Reference](https://www.nushell.sh/commands/)** - All commands
- **[Quick Tour](https://www.nushell.sh/book/quick_tour.html)** - 10-minute intro

### Interactive Learning
- **[Nushell Playground](https://www.nushell.sh/demo/)** - Try Nushell in browser
- **[Examples](https://www.nushell.sh/book/examples.html)** - Practical examples

### Community
- **[GitHub](https://github.com/nushell/nushell)** - Source code and issues
- **[Discord](https://discord.gg/NtAbbGn)** - Community chat
- **[Reddit](https://www.reddit.com/r/Nushell/)** - Discussion forum

## 🎯 Next Steps

1. **Install Nushell**: [Installation Guide](https://www.nushell.sh/book/installation.html)
2. **Try the Quick Tour**: [Quick Tour](https://www.nushell.sh/book/quick_tour.html)
3. **Explore our code**: Start with simple functions like `show_enhanced_help`
4. **Experiment**: Modify functions and see how they work
5. **Read more**: [Language Guide](https://www.nushell.sh/book/lang-guide.html)

## 💡 Tips for Reading Our Code

1. **Start with comments**: We've extensively commented the code
2. **Follow data flow**: Trace how data flows through pipelines
3. **Check types**: Function signatures show what data types are expected
4. **Look for patterns**: Similar operations are repeated throughout
5. **Use the REPL**: Try commands interactively to understand them

Remember: Nushell is designed to be intuitive. If something seems unclear, the [documentation](https://www.nushell.sh/book/) is excellent!