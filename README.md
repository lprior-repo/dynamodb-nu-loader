# 🧩 DynamoDB Nu-Loader

A minimal, production-ready test data management tool for DynamoDB tables built with [Nushell](https://www.nushell.sh/). Features functional programming principles, comprehensive testing, and efficient data operations.

## 🚀 Getting Started

### Prerequisites
- **[Nushell](https://www.nushell.sh/book/installation.html)** v0.98+ installed ([download](https://github.com/nushell/nushell/releases))
- **[AWS CLI](https://aws.amazon.com/cli/)** configured with credentials ([setup guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html))
- **DynamoDB table** with `id` (string) and `sort_key` (string) as primary keys ([table creation guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/getting-started-step-1.html))

### Quick Start
```bash
# Set environment variables
export TABLE_NAME=your-table-name
export AWS_REGION=us-east-1
export SNAPSHOTS_DIR=./snapshots

# Basic operations
nu main.nu status                    # Check table status
nu main.nu seed seed-data.json       # Load test data
nu main.nu snapshot backup-name      # Create snapshot
nu main.nu restore backup-name.json  # Restore from snapshot
nu main.nu wipe --force             # Clear all data
```

### 📁 File Format Support
- **JSON**: Snapshot format `{"metadata": {...}, "data": [...]}` or raw arrays `[{...}]`
- **CSV**: Auto-detected by `.csv` extension
- **All DynamoDB types**: Strings, numbers, booleans, null, sets, maps, lists

## 🤔 Why This Tool Exists

**DynamoDB Nu-Loader solves specific problems that Terraform and other tools don't address:**

### 1. **End-to-End Testing with Data Mutation**
- Quick snapshot/restore cycles for test data reset
- No infrastructure rebuilding needed

### 2. **SDLC Speed for DynamoDB Applications** 
- Instant data operations that complement IaC workflows
- Faster development cycles with immediate data state management

### 3. **Opinionated CLI Experience**
- Simple, powerful CLI with sensible defaults
- Functional programming principles built-in

## 📖 Documentation

- **[Complete Guide](./docs/README.md)** - Comprehensive usage documentation
- **[GitHub Actions](./docs/github-actions.md)** - CI/CD pipeline integration
- **[All Commands](./docs/commands.md)** - Detailed command reference
- **[File Formats](./docs/formats.md)** - Supported data formats
- **[Examples](./docs/examples.md)** - Common usage patterns
- **[Nushell Guide](./docs/nushell-guide.md)** - Understanding the code for newcomers

## ⚡ Commands Overview

| Command | Data Safety | Description | Example |
|---------|-------------|-------------|---------|
| `status` | ✅ **SAFE** | Check table status and metadata | `nu main.nu status` |
| `snapshot [name]` | ✅ **SAFE** | Create backup of all table data | `nu main.nu snapshot backup` |
| `seed [file]` | ⚠️ **DESTRUCTIVE** | **WIPES TABLE** then loads test data | `nu main.nu seed data.json` |
| `restore <file>` | ⚠️ **DESTRUCTIVE** | **WIPES TABLE** then restores from backup | `nu main.nu restore backup.json` |
| `wipe [--force]` | ⚠️ **DESTRUCTIVE** | **PERMANENTLY DELETES** all table data | `nu main.nu wipe --force` |

### ⚠️ Data Destructive Operations

**These commands will delete ALL existing data in your table:**

- **`seed`**: Clears table → Loads seed data from file
- **`restore`**: Clears table → Loads backup data from file  
- **`wipe`**: Permanently deletes all table data

**Safe operations** that only read data:
- **`status`**: Shows table information
- **`snapshot`**: Creates backup files

## 🔧 Configuration

```bash
# Environment variables (recommended)
export TABLE_NAME=your-table-name
export AWS_REGION=us-east-1
export SNAPSHOTS_DIR=./snapshots

# Or use command flags
nu main.nu status --table my-table --region us-west-2
```

## ⚠️ Safety First

**Always create snapshots before destructive operations:**

```bash
# ✅ RECOMMENDED: Create backup before making changes
nu main.nu snapshot backup-before-changes
nu main.nu seed test-data.json         # This wipes existing data
# If something goes wrong:
nu main.nu restore backup-before-changes.json
```

**Production Safety:**
- Use `--dry-run` flags to preview operations
- Test commands on non-production tables first
- Environment variables prevent accidental table targeting

## 🎯 Example Workflow

```bash
# Development workflow
terraform apply                        # Set up infrastructure
nu main.nu snapshot clean-state        # Create baseline backup
nu main.nu seed                       # Load test data  
./run-e2e-tests.sh                    # Run tests that mutate data
nu main.nu restore clean-state.json   # Reset data instantly
./run-more-tests.sh                   # Continue development
```

## 🛡️ Features

- **Batch Operations**: Handles DynamoDB's 25-item limit automatically
- **Type Safety**: Complete DynamoDB type conversion (S, N, BOOL, NULL, SS, NS, BS, L, M)
- **Error Handling**: Comprehensive AWS error handling with retry logic
- **Pagination**: Full support for large table scans
- **Zero Dependencies**: Only requires Nushell and AWS CLI
- **Production Ready**: 800+ lines with comprehensive testing

## 🏗️ Design Decisions & AWS References

Our implementation follows AWS DynamoDB best practices:

**Batch Operations (25-item limit)**
- AWS enforces a [25-item limit per BatchWriteItem request](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchWriteItem.html)
- We automatically chunk operations and handle [unprocessed items](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Programming.Errors.html#Programming.Errors.BatchOperations)

**Data Type Conversion**
- DynamoDB uses [attribute value format](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_AttributeValue.html) (`{"S": "string"}`, `{"N": "123"}`, etc.)
- We convert between DynamoDB and Nushell types automatically

**Pagination & Scanning**
- DynamoDB [Scan operations](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Scan.html) return max 1MB per request
- We handle [pagination automatically](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Query.Pagination.html) using `LastEvaluatedKey`

**Error Handling**
- Comprehensive handling of [DynamoDB exceptions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Programming.Errors.html)
- Exponential backoff for [throttling scenarios](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Programming.Errors.html#Programming.Errors.RetryAndBackoff)

## 📋 Requirements

- **[Nushell](https://www.nushell.sh/)**: v0.98+ ([installation guide](https://www.nushell.sh/book/installation.html))
- **[AWS CLI](https://aws.amazon.com/cli/)**: Latest version ([installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **AWS Permissions**: [`dynamodb:Scan`](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html), [`dynamodb:BatchWriteItem`](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchWriteItem.html), [`dynamodb:DescribeTable`](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_DescribeTable.html), [`dynamodb:DeleteItem`](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_DeleteItem.html)

## 📚 Nushell Learning Resources

New to Nushell? These resources will help you understand the code:

- **[Nushell Book](https://www.nushell.sh/book/)** - Complete programming guide
- **[Quick Tour](https://www.nushell.sh/book/quick_tour.html)** - 10-minute introduction
- **[Types & Values](https://www.nushell.sh/book/types_of_data.html)** - Understanding Nushell data types
- **[Pipeline Syntax](https://www.nushell.sh/book/pipelines.html)** - How `|` operators work
- **[Functions](https://www.nushell.sh/book/custom_commands.html)** - Creating custom commands
- **[Error Handling](https://www.nushell.sh/book/working_with_errors.html)** - `try`/`catch` patterns used in our code
- **[External Commands](https://www.nushell.sh/book/externs.html)** - Running AWS CLI with `^aws`

---

**DynamoDB Nu-Loader** - Minimal, powerful, and reliable test data management for DynamoDB.

📚 **[View Full Documentation →](./docs/README.md)**