# Commands Reference

Complete documentation for all DynamoDB Nu-Loader commands.

## 📋 Command Summary

| Command | Safety | Purpose | Data Impact |
|---------|--------|---------|-------------|
| [`status`](#status) | ✅ Safe | Table information | None |
| [`snapshot`](#snapshot) | ✅ Safe | Create backup | None |
| [`seed`](#seed) | ⚠️ Destructive | Load test data | **Wipes table** |
| [`restore`](#restore) | ⚠️ Destructive | Restore backup | **Wipes table** |
| [`wipe`](#wipe) | ⚠️ Destructive | Delete all data | **Wipes table** |

---

## status

Shows table information and approximate item count.

### Usage
```bash
nu main.nu status [OPTIONS]
```

### Options
- `--table <name>` - DynamoDB table name (or use `$TABLE_NAME`)
- `--region <region>` - AWS region (or use `$AWS_REGION`)

### Examples
```bash
# Using environment variables
export TABLE_NAME=my-table
export AWS_REGION=us-east-1
nu main.nu status

# Using command flags
nu main.nu status --table my-table --region us-west-2
```

### Output
```
Table: my-table
Status: ACTIVE
Items (approximate): 1,234
Size: 52,428 bytes
Created: 2024-01-15T10:30:00Z

ℹ️  Item count is approximate and updated by AWS every ~6 hours
   For exact count, use: nu main.nu snapshot --dry-run
```

### Safety
- ✅ **SAFE**: Only reads table metadata
- No data modification or deletion
- Can be run anytime without risk

### Related Links
- [DynamoDB DescribeTable API](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_DescribeTable.html)
- [Table Status Values](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.TableClasses.html)

---

## snapshot

Creates a backup snapshot of all table data.

### Usage
```bash
nu main.nu snapshot [file] [OPTIONS]
```

### Arguments
- `file` - Output filename (default: `snapshots/snapshot_YYYYMMDD_HHMMSS.json`)

### Options
- `--table <name>` - DynamoDB table name
- `--region <region>` - AWS region  
- `--snapshots-dir <dir>` - Snapshots directory (or use `$SNAPSHOTS_DIR`)
- `--dry-run` - Count items exactly but don't save snapshot
- `--exact-count` - Use exact count in metadata (slower, more expensive)

### Examples
```bash
# Basic snapshot with auto-generated filename
nu main.nu snapshot

# Custom filename
nu main.nu snapshot my-backup

# Exact item count (slower but precise)
nu main.nu snapshot --exact-count

# Count items without creating file
nu main.nu snapshot --dry-run
```

### Output Format
```json
{
  "metadata": {
    "table_name": "my-table",
    "timestamp": "2024-01-15 14:30:25",
    "item_count": 1234,
    "item_count_exact": true,
    "tool": "dynamodb-nu-loader",
    "version": "1.0"
  },
  "data": [
    {
      "id": "user1",
      "sort_key": "profile",
      "name": "John Doe",
      "email": "john@example.com"
    }
  ]
}
```

### Safety
- ✅ **SAFE**: Only reads data from DynamoDB
- Creates backup files, no data modification
- Can be run anytime without risk

### Performance Notes
- Large tables are automatically paginated
- Default uses AWS's approximate count (faster)
- Use `--exact-count` for precise metadata (slower)

### Related Links
- [DynamoDB Scan API](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html)
- [Pagination in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Query.Pagination.html)

---

## seed

Loads test/seed data into the table.

### Usage
```bash
nu main.nu seed [file] [OPTIONS]
```

### Arguments
- `file` - Seed data file (default: `seed-data.json`)

### Options
- `--table <name>` - DynamoDB table name
- `--region <region>` - AWS region

### Examples
```bash
# Load default seed data
nu main.nu seed

# Load custom seed data
nu main.nu seed my-test-data.json

# Load CSV data
nu main.nu seed users.csv
```

### ⚠️ DESTRUCTIVE OPERATION

**This command WIPES ALL EXISTING DATA before loading seed data.**

Process:
1. **Deletes all items** from the table
2. Loads data from the specified file
3. Uses batch operations for efficiency

### Supported File Formats

**JSON Array:**
```json
[
  {"id": "user1", "sort_key": "profile", "name": "John"},
  {"id": "user2", "sort_key": "profile", "name": "Jane"}
]
```

**CSV:**
```csv
id,sort_key,name,email
user1,profile,John Doe,john@example.com
user2,profile,Jane Smith,jane@example.com
```

**Snapshot Format:**
```json
{
  "metadata": {...},
  "data": [
    {"id": "user1", "sort_key": "profile", "name": "John"}
  ]
}
```

### Safety Recommendations
```bash
# ✅ RECOMMENDED: Create backup first
nu main.nu snapshot pre-seed-backup
nu main.nu seed test-data.json

# If something goes wrong:
nu main.nu restore pre-seed-backup.json
```

### Related Links
- [DynamoDB BatchWriteItem API](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchWriteItem.html)
- [DynamoDB Data Types](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.NamingRulesDataTypes.html)

---

## restore

Restores table data from a backup file.

### Usage
```bash
nu main.nu restore <file> [OPTIONS]
```

### Arguments
- `file` - **Required** snapshot file to restore from

### Options
- `--table <name>` - DynamoDB table name
- `--region <region>` - AWS region

### Examples
```bash
# Restore from snapshot
nu main.nu restore backup-2024-01-15.json

# Restore from CSV backup
nu main.nu restore data-export.csv

# Different table/region
nu main.nu restore backup.json --table other-table --region us-west-2
```

### ⚠️ DESTRUCTIVE OPERATION

**This command WIPES ALL EXISTING DATA before restoring.**

Process:
1. **Deletes all items** from the table
2. Loads data from the backup file
3. Uses batch operations for efficiency

### Use Cases
```bash
# Reset to clean state after tests
nu main.nu restore clean-baseline.json

# Recover from accidental data corruption
nu main.nu restore last-good-backup.json

# Copy data between environments
# (export from prod, import to staging)
nu main.nu restore prod-snapshot.json --table staging-table
```

### Error Handling
The command will fail safely if:
- Backup file doesn't exist
- File format is invalid
- AWS permissions are insufficient
- Table doesn't exist

### Related Links
- [File Formats Documentation](./formats.md)
- [DynamoDB BatchWriteItem Limits](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Limits.html#limits-api)

---

## wipe

Permanently deletes all items from the DynamoDB table.

### Usage
```bash
nu main.nu wipe [OPTIONS]
```

### Options
- `--force` or `-f` - Skip confirmation prompt (dangerous!)
- `--table <name>` - DynamoDB table name
- `--region <region>` - AWS region

### Examples
```bash
# Interactive confirmation
nu main.nu wipe
# Are you sure you want to delete all data from my-table? y/N: 

# Skip confirmation (dangerous!)
nu main.nu wipe --force

# Specific table
nu main.nu wipe --table temp-table --force
```

### ⚠️ MOST DESTRUCTIVE OPERATION

**This command PERMANENTLY DELETES ALL TABLE DATA.**

This is the most dangerous command in the tool. Use with extreme caution.

### Safety Features
- **Confirmation prompt** by default (unless `--force` used)
- Requires exact table name
- Will not proceed if table doesn't exist

### Use Cases
```bash
# Clean up after testing
nu main.nu wipe --force

# Reset development environment
nu main.nu snapshot backup-before-reset
nu main.nu wipe --force
# ... do development work ...
nu main.nu restore backup-before-reset.json
```

### Production Safety
```bash
# ❌ NEVER do this in production
export TABLE_NAME=production-users
nu main.nu wipe --force

# ✅ Use specific table names to avoid accidents
nu main.nu wipe --table test-table --force
```

### Related Links
- [DynamoDB DeleteItem API](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_DeleteItem.html)
- [Best Practices for DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)

---

## Global Options

All commands support these options:

### Environment Variables
```bash
export TABLE_NAME=my-table        # Default table name
export AWS_REGION=us-east-1       # Default AWS region  
export SNAPSHOTS_DIR=./snapshots  # Default snapshots directory
```

### Command Line Flags
- `--table <name>` - Override `$TABLE_NAME`
- `--region <region>` - Override `$AWS_REGION`
- `--snapshots-dir <dir>` - Override `$SNAPSHOTS_DIR` (snapshot command only)

### Help
```bash
# General help
nu main.nu

# Command-specific help
nu main.nu <command> --help
```

## 🔗 Nushell Command Reference

The commands in this tool use these Nushell concepts:

- **[Custom Commands](https://www.nushell.sh/book/custom_commands.html)** - How our `main.nu` commands are defined
- **[External Commands](https://www.nushell.sh/book/externs.html)** - Running AWS CLI with `^aws`
- **[Error Handling](https://www.nushell.sh/book/working_with_errors.html)** - `try`/`catch` patterns
- **[Environment Variables](https://www.nushell.sh/book/environment.html)** - `$env.TABLE_NAME` access
- **[String Interpolation](https://www.nushell.sh/book/working_with_strings.html)** - `$"variable ($value)"` syntax