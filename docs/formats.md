# File Formats

Complete guide to supported file formats and data structures.

## 📝 Supported Formats

DynamoDB Nu-Loader supports multiple file formats for maximum flexibility:

| Format | Extension | Auto-Detection | Use Case |
|--------|-----------|----------------|----------|
| JSON Array | `.json` | ✅ | Raw data export/import |
| JSON Snapshot | `.json` | ✅ | Full backups with metadata |
| CSV | `.csv` | ✅ | Spreadsheet data, human-readable |

## 🔧 JSON Formats

### JSON Array Format
Direct array of objects - simple and clean.

```json
[
  {
    "id": "user1",
    "sort_key": "profile", 
    "name": "John Doe",
    "email": "john@example.com",
    "active": true,
    "age": 30
  },
  {
    "id": "user2", 
    "sort_key": "profile",
    "name": "Jane Smith",
    "email": "jane@example.com", 
    "active": false,
    "age": 25
  }
]
```

**When to use:**
- Importing external data
- Simple data sets
- Manual data creation

### JSON Snapshot Format
Full backup format with metadata - used by the `snapshot` command.

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

**When to use:**
- Created automatically by `snapshot` command
- Full table backups
- Disaster recovery
- Audit trails

**Metadata fields:**
- `table_name` - Source table name
- `timestamp` - When snapshot was created
- `item_count` - Number of items (approximate or exact)
- `item_count_exact` - Whether count is exact or approximate
- `tool` - Tool that created the snapshot
- `version` - Tool version

## 📊 CSV Format

Standard CSV with headers - great for human readability and spreadsheet editing.

```csv
id,sort_key,name,email,active,age
user1,profile,John Doe,john@example.com,true,30
user2,profile,Jane Smith,jane@example.com,false,25
user3,profile,Bob Wilson,bob@example.com,true,35
```

**When to use:**
- Editing data in spreadsheets
- Human-readable format
- Data from external systems
- Simple data structures

**CSV Limitations:**
- No nested objects (use JSON for complex data)
- All values stored as strings (auto-converted by DynamoDB)
- Boolean values: `true`/`false` as strings

## 🧬 DynamoDB Data Types

All formats support DynamoDB's complete type system:

### Scalar Types
```json
{
  "string_field": "text value",
  "number_field": 123,
  "float_field": 45.67,
  "boolean_field": true,
  "null_field": null
}
```

### Set Types
```json
{
  "string_set": ["apple", "banana", "cherry"],
  "number_set": [1, 2, 3, 4, 5],
  "binary_set": ["binary_data_1", "binary_data_2"]
}
```

### Complex Types
```json
{
  "list_field": [
    "string",
    123,
    true,
    {"nested": "object"}
  ],
  "map_field": {
    "nested_string": "value",
    "nested_number": 456,
    "nested_list": [1, 2, 3]
  }
}
```

## 🔄 Type Conversion

### Automatic Conversions

| Nushell Type | DynamoDB Type | Example |
|--------------|---------------|---------|
| `string` | S (String) | `"hello"` → `{"S": "hello"}` |
| `int` | N (Number) | `42` → `{"N": "42"}` |
| `float` | N (Number) | `3.14` → `{"N": "3.14"}` |
| `bool` | BOOL (Boolean) | `true` → `{"BOOL": true}` |
| `null` | NULL | `null` → `{"NULL": true}` |
| `[string, ...]` | SS (String Set) | `["a", "b"]` → `{"SS": ["a", "b"]}` |
| `[number, ...]` | NS (Number Set) | `[1, 2]` → `{"NS": ["1", "2"]}` |
| `[mixed]` | L (List) | `[1, "a"]` → `{"L": [{"N": "1"}, {"S": "a"}]}` |
| `{...}` | M (Map) | `{x: 1}` → `{"M": {"x": {"N": "1"}}}` |

### Manual Type Specification

For precise control, you can use DynamoDB's native format:

```json
{
  "id": {"S": "user1"},
  "age": {"N": "30"},
  "active": {"BOOL": true},
  "tags": {"SS": ["premium", "verified"]},
  "scores": {"NS": ["85", "92", "78"]},
  "metadata": {"NULL": true},
  "preferences": {
    "M": {
      "theme": {"S": "dark"},
      "notifications": {"BOOL": false}
    }
  }
}
```

## 📋 Examples by Use Case

### User Data
```json
[
  {
    "id": "user123",
    "sort_key": "profile",
    "name": "Alice Johnson",
    "email": "alice@company.com",
    "department": "Engineering",
    "roles": ["developer", "team-lead"],
    "salary": 95000,
    "active": true,
    "metadata": {
      "created_at": "2024-01-15",
      "last_login": "2024-01-20T10:30:00Z",
      "preferences": {
        "theme": "dark",
        "notifications": true
      }
    }
  }
]
```

### Product Catalog
```json
[
  {
    "id": "prod456",
    "sort_key": "item",
    "name": "Wireless Headphones",
    "category": "Electronics",
    "price": 199.99,
    "in_stock": true,
    "tags": ["wireless", "bluetooth", "noise-canceling"],
    "ratings": [4.5, 4.8, 4.2, 5.0],
    "specs": {
      "battery_life": "20 hours",
      "weight": "250g",
      "color_options": ["black", "white", "blue"]
    }
  }
]
```

### Order History
```json
[
  {
    "id": "order789",
    "sort_key": "2024-01-15",
    "customer_id": "user123",
    "total": 299.99,
    "status": "shipped",
    "items": [
      {
        "product_id": "prod456",
        "quantity": 1,
        "price": 199.99
      },
      {
        "product_id": "prod789",
        "quantity": 2,
        "price": 50.00
      }
    ],
    "shipping": {
      "address": "123 Main St, City, State 12345",
      "method": "express",
      "tracking": "1Z999AA1234567890"
    }
  }
]
```

### Test Data with Edge Cases
```json
[
  {
    "id": "edge1",
    "sort_key": "test",
    "empty_string": "",
    "zero_number": 0,
    "false_boolean": false,
    "null_field": null,
    "empty_list": [],
    "empty_object": {},
    "unicode_text": "测试数据 🚀",
    "large_number": 9007199254740991,
    "small_decimal": 0.000001,
    "negative_number": -123.45
  }
]
```

## 🔧 Best Practices

### File Organization
```
project/
├── seed-data/
│   ├── users.json          # User test data
│   ├── products.csv        # Product catalog
│   └── orders.json         # Order history
├── snapshots/
│   ├── baseline.json       # Clean state backup
│   ├── pre-test.json       # Before test runs
│   └── production.json     # Production data copy
└── test-data/
    ├── edge-cases.json     # Edge case testing
    ├── large-dataset.json  # Performance testing
    └── empty.json          # Empty state
```

### Naming Conventions
- **Seed files**: `{entity}-{environment}.json` (e.g., `users-dev.json`)
- **Snapshots**: `{purpose}-{timestamp}.json` (e.g., `baseline-20240115.json`)
- **Test data**: `{test-type}-{scenario}.json` (e.g., `edge-cases-unicode.json`)

### Data Validation
```bash
# Validate JSON format before using
cat data.json | jq '.' > /dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Check CSV headers
head -1 data.csv
```

### Size Considerations
- **Small files** (< 1MB): Any format works well
- **Medium files** (1-10MB): JSON preferred for complex data, CSV for simple
- **Large files** (> 10MB): Consider splitting into multiple files

## 🚨 Common Issues

### CSV Limitations
```bash
# ❌ Won't work - nested objects in CSV
id,sort_key,metadata
user1,profile,{"key": "value"}

# ✅ Works - flat structure
id,sort_key,metadata_key
user1,profile,value
```

### JSON Formatting
```json
// ❌ Invalid - comments not allowed
{
  "id": "user1",  // This is a comment
  "name": "John"
}

// ✅ Valid - no comments
{
  "id": "user1",
  "name": "John"
}
```

### DynamoDB Constraints
- Item size limit: 400 KB per item
- Attribute name length: 64 KB maximum
- Number precision: 38 significant digits

## 🔗 Related Documentation

- **[DynamoDB Data Types](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.NamingRulesDataTypes.html)** - Official AWS documentation
- **[JSON Specification](https://www.json.org/)** - JSON format standard
- **[CSV Specification](https://tools.ietf.org/html/rfc4180)** - CSV format standard
- **[Nushell Data Types](https://www.nushell.sh/book/types_of_data.html)** - Understanding Nushell types