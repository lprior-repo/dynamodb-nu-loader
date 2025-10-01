# 🧩 DynamoDB Nu-Loader

A minimal, production-ready test data management tool for DynamoDB tables built with [Nushell](https://www.nushell.sh/). Features functional programming principles, comprehensive testing, and efficient data operations.

## ⚡ Quick Start

1. **Prerequisites**: Install [Nushell](https://www.nushell.sh/book/installation.html) and [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

2. **Configure AWS**:
   ```bash
   aws configure
   # Or set environment variables
   export AWS_ACCESS_KEY_ID=your_key
   export AWS_SECRET_ACCESS_KEY=your_secret
   export AWS_DEFAULT_REGION=us-east-1
   ```

3. **Set up your DynamoDB table** (any table with `id` as hash key and `sort_key` as range key)

4. **Use the tool**:
   ```bash
   # Set environment variables (recommended)
   export TABLE_NAME=your-table-name
   export AWS_REGION=us-east-1
   
   # Load sample data
   nu main.nu seed
   
   # Check table status
   nu main.nu status
   
   # Create backup
   nu main.nu snapshot my-backup
   
   # Restore from backup
   nu main.nu restore my-backup.json
   ```

## 🔧 Commands

### `help`
Show all available commands and usage information.
```bash
nu main.nu help
nu main.nu status --help  # Command-specific help
```

### `seed [file]`
Load sample data into your table.
```bash
nu main.nu seed                    # Uses default seed-data.json
nu main.nu seed custom-data.json   # Uses custom file
```

### `status`
Show table information and item count.
```bash
nu main.nu status
nu main.nu status --table my-table --region us-west-2
```

### `snapshot [name]`
Create a backup of your table data.
```bash
nu main.nu snapshot                # Auto-generates timestamped name
nu main.nu snapshot my-backup      # Creates my-backup.json
```

**Output format**:
```json
{
  "metadata": {
    "table_name": "my-table",
    "timestamp": "2024-01-01 12:00:00",
    "item_count": 100,
    "tool": "dynamodb-nu-loader",
    "version": "1.0"
  },
  "data": [
    {"id": "item-1", "sort_key": "USER", "name": "Alice"},
    {"id": "item-2", "sort_key": "USER", "name": "Bob"}
  ]
}
```

### `restore <file>`
Restore data from a backup file. Auto-detects file format.
```bash
nu main.nu restore backup.json     # JSON snapshot format
nu main.nu restore data.csv        # CSV format
nu main.nu restore raw-data.json   # Raw JSON array
```

**Supported formats**:
- **JSON snapshot**: With metadata wrapper (created by `snapshot` command)
- **Raw JSON array**: Plain array of objects
- **CSV files**: Auto-detected by `.csv` extension

### `wipe [--force]`
Delete all items from the table.
```bash
nu main.nu wipe           # Interactive confirmation
nu main.nu wipe --force   # Skip confirmation
```
⚠️ **Warning**: This permanently deletes ALL data!

## ⚙️ Configuration

### Environment Variables (Recommended)
```bash
export TABLE_NAME=your-table-name     # DynamoDB table name
export AWS_REGION=us-east-1           # AWS region
export SNAPSHOTS_DIR=./snapshots      # Directory for snapshots (optional)
export AWS_PROFILE=default            # AWS profile (optional)
```

### Command Line Flags
Override environment variables with flags:
```bash
nu main.nu status --table my-table --region us-west-2
nu main.nu snapshot backup --snapshots-dir ./backups
```

**Priority**: Command flags > Environment variables > Error if missing

## 📁 File Formats

### CSV Format
```csv
id,sort_key,name,email
user-1,USER,Alice,alice@example.com
user-2,USER,Bob,bob@example.com
```

### Raw JSON Array
```json
[
  {"id": "user-1", "sort_key": "USER", "name": "Alice"},
  {"id": "user-2", "sort_key": "USER", "name": "Bob"}
]
```

### JSON Snapshot (with metadata)
```json
{
  "metadata": {
    "table_name": "my-table",
    "timestamp": "2024-01-01 12:00:00",
    "item_count": 2,
    "tool": "dynamodb-nu-loader",
    "version": "1.0"
  },
  "data": [
    {"id": "user-1", "sort_key": "USER", "name": "Alice"},
    {"id": "user-2", "sort_key": "USER", "name": "Bob"}
  ]
}
```

## 💡 Usage Examples

### Basic Workflow
```bash
# Start with sample data
nu main.nu seed

# Create backup before changes
nu main.nu snapshot before-changes

# Make changes or test your application
# ...

# Restore to clean state
nu main.nu restore before-changes.json
```

### Data Migration
```bash
# Export from source table
TABLE_NAME=source-table nu main.nu snapshot migration-data

# Import to target table  
TABLE_NAME=target-table nu main.nu wipe --force
TABLE_NAME=target-table nu main.nu restore migration-data.json
```

### Testing Different Datasets
```bash
# Create multiple test datasets
nu main.nu seed && nu main.nu snapshot test-set-1
nu main.nu restore large-dataset.csv && nu main.nu snapshot test-set-2
nu main.nu restore edge-cases.json && nu main.nu snapshot test-set-3

# Switch between them quickly
nu main.nu restore test-set-1.json  # Back to seed data
nu main.nu restore test-set-2.json  # Switch to large dataset
```

### Batch Operations
The tool automatically handles DynamoDB's 25-item batch limit:
```bash
# Import large CSV (automatically chunked into batches)
nu main.nu restore large-dataset.csv

# Export large table (handles pagination automatically)
nu main.nu snapshot large-backup
```

## 🧪 Testing

The project includes comprehensive testing with 700+ lines of test coverage.

### Run Tests
```bash
# Quick validation tests
nu tests/run_simple_tests.nu

# Manual validation
nu tests/manual_test_runner.nu

# Run specific test suites
nu -c "use tests/unit/test_validation.nu"
nu -c "use tests/unit/test_data_ops.nu"
```

### Test Structure
- **Unit Tests**: `tests/unit/` - Function-level testing
- **Integration Tests**: `tests/integration/` - Workflow testing  
- **Test Utilities**: `tests/helpers/test_utils.nu` - Shared test functions
- **Test Fixtures**: `tests/fixtures/` - Sample data files

## 🔥 Features

### Core Capabilities
- **Multiple Format Support**: JSON snapshots, raw JSON arrays, CSV files
- **Auto-Detection**: Automatically detects file format based on content/extension
- **Batch Operations**: Respects DynamoDB API limits (25 items per batch)
- **Type Safety**: Proper type conversion for DynamoDB attribute values
- **Error Handling**: Graceful handling of malformed data and AWS errors

### Technical Features
- **Functional Programming**: Pure functions, immutable data structures
- **Minimal Code**: ~350 lines for complete functionality
- **Zero Dependencies**: Only requires Nushell and AWS CLI
- **Fast Operations**: Efficient scanning and writing with proper pagination
- **Comprehensive Testing**: 66 tests covering all functionality

### Data Operations
- **Smart Type Conversion**: Automatically converts types for DynamoDB
  - Strings → `{S: "value"}`
  - Numbers → `{N: "42"}`
  - Booleans → `{BOOL: true}`
  - Null values → `{NULL: true}`
- **Metadata Tracking**: Snapshots include table info and timestamps
- **Validation**: Ensures data integrity before operations

## 🛡️ Error Handling

The tool provides comprehensive error handling:

- **File Errors**: Clear messages for missing or malformed files
- **AWS Errors**: Proper error propagation with context
- **Data Validation**: Input validation and type checking
- **Network Issues**: Graceful handling of connectivity problems

### Common Error Solutions
```bash
# Permission denied
aws sts get-caller-identity  # Check AWS credentials

# Table not found
aws dynamodb describe-table --table-name your-table  # Verify table exists

# Invalid file format
nu main.nu restore file.json  # Check file contents and format
```

## 🏗️ Architecture

### Design Principles
- **Functional Programming**: Pure functions, no side effects
- **Type Safety**: Complete type signatures
- **Minimal Code**: Essential functionality only
- **Comprehensive Testing**: Test-driven development

### Key Functions
- `scan_table`: Efficiently scans DynamoDB with pagination
- `batch_write`: Writes items in batches respecting API limits  
- `detect_and_process`: Auto-detects and processes file formats
- `save_snapshot`: Creates timestamped snapshots with metadata

### Data Flow
```
Input File → detect_and_process → validate → batch_write → DynamoDB
DynamoDB → scan_table → format → save_snapshot → Output File
```

## 📋 Requirements

### DynamoDB Table Schema
Your table must have:
- **Hash Key**: `id` (String)
- **Range Key**: `sort_key` (String)
- **Optional**: Any additional attributes

### System Requirements
- **Nushell**: v0.98+ ([install guide](https://www.nushell.sh/book/installation.html))
- **AWS CLI**: Latest version ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **AWS Credentials**: Configured via `aws configure` or environment variables

### AWS Permissions
Your AWS credentials need these DynamoDB permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTable",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/your-table-name"
    }
  ]
}
```

## 🚀 Advanced Usage

### Performance Optimization
```bash
# For large tables, create snapshots during low-traffic periods
nu main.nu snapshot large-backup

# Use CSV for fastest import/export of simple data
nu main.nu restore data.csv

# Batch operations are automatically optimized for DynamoDB limits
```

### Automation Scripts
```bash
#!/usr/bin/env nu
# backup-script.nu - Daily backup automation
let date = (date now | format date "%Y%m%d")
let backup_name = $"daily-backup-($date)"
nu main.nu snapshot $backup_name
```

### Integration with CI/CD
```bash
# Reset test data before tests
nu main.nu wipe --force
nu main.nu seed

# Run your tests
./run-integration-tests.sh

# Cleanup
nu main.nu wipe --force
```

---

**DynamoDB Nu-Loader** - Minimal, powerful, and reliable test data management for DynamoDB.

For questions or issues, check the test files in `tests/` for usage examples.