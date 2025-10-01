# Usage Examples

Practical examples and common workflows for DynamoDB Nu-Loader.

## 🎯 Quick Start Examples

### Basic Operations
```bash
# Check table status
nu main.nu status

# Create backup
nu main.nu snapshot backup-$(date +%Y%m%d)

# Add test data (non-destructive)
nu main.nu seed test-data.json

# Complete reset (wipe + seed)
nu main.nu reset test-data.json

# Reset to clean state from backup
nu main.nu restore baseline.json
```

## 🏗️ Industry Standard Patterns

Our commands follow established patterns from popular frameworks:

| Framework | Reset Command | Seed Command | Pattern |
|-----------|---------------|---------------|---------|
| **Laravel** | `migrate:fresh --seed` | `db:seed` | Reset = Destructive, Seed = Additive |
| **Prisma** | `db reset` | Custom scripts | Reset = Complete refresh |
| **Rails** | `db:reset` | `db:seed` | Reset = Drop + Create + Seed |
| **Nu-Loader** | `reset` | `seed` | **Reset = Wipe + Seed, Seed = Add only** |

### Why This Design?

**Problems with old design:**
- `seed` was destructive (confusing)
- `--force` flag was redundant
- No single command for complete reset

**Industry-standard solution:**
- `seed` is now **non-destructive** (adds data)
- `reset` handles **complete refresh** (wipe + seed)
- `wipe` requires confirmation (no bypass flag needed)

### Environment Setup
```bash
# Set environment variables (recommended)
export TABLE_NAME=my-test-table
export AWS_REGION=us-east-1  
export SNAPSHOTS_DIR=./backups

# Now commands use these defaults
nu main.nu status
nu main.nu snapshot
```

## 🔄 Development Workflows

### Test-Driven Development
```bash
#!/bin/bash
# test-workflow.sh

echo "Setting up test environment..."

# Create baseline backup
nu main.nu snapshot baseline-clean

# Reset with fresh test data (wipe + seed)
nu main.nu reset integration-test-data.json

echo "Running tests..."
npm test

echo "Checking for data corruption..."
nu main.nu snapshot post-test

# Compare item counts
BASELINE_COUNT=$(jq '.metadata.item_count' snapshots/baseline-clean.json)
POSTTEST_COUNT=$(jq '.metadata.item_count' snapshots/post-test.json)

if [ "$BASELINE_COUNT" != "$POSTTEST_COUNT" ]; then
  echo "⚠️  Data count changed during tests!"
  echo "Baseline: $BASELINE_COUNT, Post-test: $POSTTEST_COUNT"
fi

echo "Restoring clean state..."
nu main.nu restore baseline-clean.json
echo "✅ Environment reset complete"
```

### Feature Branch Testing
```bash
#!/bin/bash
# feature-test.sh

FEATURE_NAME=$1
if [ -z "$FEATURE_NAME" ]; then
  echo "Usage: $0 <feature-name>"
  exit 1
fi

echo "Testing feature: $FEATURE_NAME"

# Create feature-specific backup
nu main.nu snapshot "pre-feature-$FEATURE_NAME"

# Reset with feature test data
nu main.nu reset "features/$FEATURE_NAME-data.json"

# Run feature tests
npm test -- --grep "$FEATURE_NAME"

# Restore original state
nu main.nu restore "pre-feature-$FEATURE_NAME.json"

echo "✅ Feature test complete"
```

## 🏭 Production-like Workflows

### Environment Synchronization
```bash
#!/bin/bash
# sync-environments.sh

SOURCE_TABLE="production-users"
TARGET_TABLE="staging-users"

echo "Syncing $SOURCE_TABLE → $TARGET_TABLE"

# Backup production data
TABLE_NAME=$SOURCE_TABLE nu main.nu snapshot prod-sync-$(date +%Y%m%d)

# Copy to staging
TABLE_NAME=$TARGET_TABLE nu main.nu restore "snapshots/prod-sync-$(date +%Y%m%d).json"

echo "✅ Environment sync complete"
```

### Data Migration Testing
```bash
#!/bin/bash
# migration-test.sh

echo "Testing data migration..."

# Create pre-migration backup
nu main.nu snapshot pre-migration

# Reset with production-like data for clean test
nu main.nu reset production-like-data.json

# Run migration script
./run-migration.sh

# Create post-migration snapshot
nu main.nu snapshot post-migration

# Validate migration results
python validate-migration.py \
  --before snapshots/pre-migration.json \
  --after snapshots/post-migration.json

if [ $? -eq 0 ]; then
  echo "✅ Migration validation passed"
else
  echo "❌ Migration validation failed"
  echo "Restoring pre-migration state..."
  nu main.nu restore pre-migration.json
  exit 1
fi
```

## 🧪 Testing Scenarios

### Load Testing Setup
```bash
#!/bin/bash
# load-test-setup.sh

# Generate large dataset for load testing
echo "Generating load test data..."

# Create 10,000 user records
cat > generate-load-data.nu << 'EOF'
1..10000 | each { |i|
  {
    id: $"user($i)",
    sort_key: "profile",
    name: $"User ($i)",
    email: $"user($i)@loadtest.com",
    created_at: (date now | format date "%Y-%m-%d"),
    active: (($i mod 2) == 0),
    metadata: {
      test_run: "load-test-2024",
      batch: ($i / 1000 | math floor)
    }
  }
} | to json
EOF

nu generate-load-data.nu > load-test-data.json

# Reset with load test data and measure performance
echo "Loading data..."
time nu main.nu reset load-test-data.json

# Run load tests
echo "Running load tests..."
artillery run load-test-config.yml

# Clean up
echo "Cleaning up..."
nu main.nu wipe
rm load-test-data.json generate-load-data.nu
```

### Edge Case Testing
```bash
#!/bin/bash
# edge-case-tests.sh

test_cases=(
  "edge-cases-unicode.json"
  "edge-cases-large-items.json" 
  "edge-cases-empty-values.json"
  "edge-cases-numeric-limits.json"
)

for test_case in "${test_cases[@]}"; do
  echo "Testing: $test_case"
  
  # Load edge case data
  nu main.nu seed "test-data/$test_case"
  
  # Run application with edge case data
  npm test -- --config edge-cases
  
  if [ $? -ne 0 ]; then
    echo "❌ Failed: $test_case"
    # Save failure snapshot for debugging
    nu main.nu snapshot "failed-$test_case"
    exit 1
  fi
  
  echo "✅ Passed: $test_case"
done

echo "✅ All edge case tests passed"
```

## 📊 Data Management Patterns

### Versioned Data Sets
```bash
#!/bin/bash
# versioned-datasets.sh

VERSION=$1
if [ -z "$VERSION" ]; then
  VERSION=$(date +%Y%m%d)
fi

# Create versioned snapshot
nu main.nu snapshot "dataset-v$VERSION"

# Tag with metadata
jq --arg version "$VERSION" \
   --arg description "Dataset version for release $VERSION" \
   '.metadata.version = $version | .metadata.description = $description' \
   "snapshots/dataset-v$VERSION.json" > "snapshots/dataset-v$VERSION-tagged.json"

echo "✅ Created dataset version: $VERSION"
```

### Multi-Environment Management
```bash
#!/bin/bash
# multi-env.sh

environments=("dev" "staging" "prod")
operation=$1
file=$2

case $operation in
  "backup")
    for env in "${environments[@]}"; do
      echo "Backing up $env..."
      TABLE_NAME="$env-users" \
      AWS_REGION="us-east-1" \
      nu main.nu snapshot "$env-backup-$(date +%Y%m%d)"
    done
    ;;
    
  "restore")
    if [ -z "$file" ]; then
      echo "Usage: $0 restore <backup-file>"
      exit 1
    fi
    
    for env in "${environments[@]}"; do
      echo "Restoring $env from $file..."
      TABLE_NAME="$env-users" \
      AWS_REGION="us-east-1" \
      nu main.nu restore "$file"
    done
    ;;
    
  "seed")
    for env in "${environments[@]}"; do
      echo "Adding seed data to $env..."
      TABLE_NAME="$env-users" \
      AWS_REGION="us-east-1" \
      nu main.nu seed "seed-data/$env-data.json"
    done
    ;;
    
  "reset")
    if [ -z "$file" ]; then
      file="seed-data/default-data.json"
    fi
    
    for env in "${environments[@]}"; do
      echo "Resetting $env with fresh data..."
      TABLE_NAME="$env-users" \
      AWS_REGION="us-east-1" \
      nu main.nu reset "$file"
    done
    ;;
    
  *)
    echo "Usage: $0 {backup|restore|seed|reset} [file]"
    exit 1
    ;;
esac
```

## 🔍 Monitoring and Validation

### Data Integrity Checks
```bash
#!/bin/bash
# integrity-check.sh

echo "Running data integrity checks..."

# Get current item count
CURRENT_COUNT=$(nu main.nu snapshot --dry-run 2>&1 | grep "Exact item count" | cut -d: -f2 | tr -d ' ')

# Check against expected count
EXPECTED_COUNT=$(cat expected-count.txt)

if [ "$CURRENT_COUNT" -eq "$EXPECTED_COUNT" ]; then
  echo "✅ Item count matches: $CURRENT_COUNT"
else
  echo "❌ Item count mismatch!"
  echo "Expected: $EXPECTED_COUNT"
  echo "Actual: $CURRENT_COUNT"
  exit 1
fi

# Create validation snapshot
nu main.nu snapshot "validation-$(date +%Y%m%d-%H%M%S)"

# Run custom validation script
python validate-data-structure.py

echo "✅ Data integrity check complete"
```

### Performance Monitoring
```bash
#!/bin/bash
# performance-monitor.sh

operations=("seed" "snapshot" "restore")
data_file="performance-test-data.json"

echo "Performance monitoring started..."
echo "timestamp,operation,duration_seconds,item_count" > performance.csv

for op in "${operations[@]}"; do
  echo "Testing operation: $op"
  
  # Prepare for operation
  case $op in
    "seed"|"restore")
      # Ensure we have test data
      [ ! -f "$data_file" ] && echo "Error: $data_file not found" && exit 1
      ;;
  esac
  
  # Time the operation
  start_time=$(date +%s)
  
  case $op in
    "seed")
      nu main.nu seed "$data_file" ;;
    "snapshot")
      nu main.nu snapshot "perf-test-$(date +%s)" ;;
    "restore")
      nu main.nu restore "$data_file" ;;
  esac
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Get item count
  item_count=$(nu main.nu snapshot --dry-run 2>&1 | grep "Exact item count" | cut -d: -f2 | tr -d ' ')
  
  # Log results
  echo "$(date +%Y-%m-%d-%H:%M:%S),$op,$duration,$item_count" >> performance.csv
  
  echo "Operation $op completed in ${duration}s with $item_count items"
done

echo "✅ Performance monitoring complete"
echo "Results saved to performance.csv"
```

## 🚨 Error Recovery

### Automated Recovery
```bash
#!/bin/bash
# auto-recovery.sh

MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES"
  
  if nu main.nu seed production-data.json; then
    echo "✅ Seed operation successful"
    break
  else
    echo "❌ Seed operation failed"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Waiting 30 seconds before retry..."
      sleep 30
      
      # Try to restore from backup and retry
      echo "Restoring from last known good backup..."
      nu main.nu restore last-known-good.json
    fi
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ All retry attempts failed"
  echo "Manual intervention required"
  exit 1
fi
```

### Health Check Script
```bash
#!/bin/bash
# health-check.sh

echo "Running DynamoDB Nu-Loader health check..."

# Check AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo "❌ AWS credentials not configured"
  exit 1
fi

# Check table exists and is accessible
if ! nu main.nu status > /dev/null 2>&1; then
  echo "❌ Cannot access DynamoDB table"
  exit 1
fi

# Check Nushell version
NU_VERSION=$(nu --version | head -1 | cut -d' ' -f2)
echo "Nushell version: $NU_VERSION"

# Test basic operations
echo "Testing basic operations..."

# Test snapshot creation
if nu main.nu snapshot health-check-$(date +%s) > /dev/null 2>&1; then
  echo "✅ Snapshot operation working"
else
  echo "❌ Snapshot operation failed"
  exit 1
fi

# Test data loading (with small dataset)
echo '[{"id": "health", "sort_key": "check", "timestamp": "'$(date +%s)'"}]' > health-check.json

if nu main.nu seed health-check.json > /dev/null 2>&1; then
  echo "✅ Seed operation working"
else
  echo "❌ Seed operation failed"
  exit 1
fi

# Cleanup
rm health-check.json

echo "✅ All health checks passed"
```

## 🔗 Integration Examples

### With Terraform
```bash
#!/bin/bash
# terraform-integration.sh

echo "Deploying infrastructure..."
terraform apply -auto-approve

# Wait for table to be ready
TABLE_NAME=$(terraform output -raw dynamodb_table_name)
aws dynamodb wait table-exists --table-name "$TABLE_NAME"

echo "Table created: $TABLE_NAME"

# Load initial data
TABLE_NAME="$TABLE_NAME" nu main.nu seed initial-data.json

echo "✅ Infrastructure deployed and seeded"
```

### With Docker
```dockerfile
# Dockerfile for CI/CD
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Install Nushell
RUN curl -L https://github.com/nushell/nushell/releases/latest/download/nu-linux-x86_64-gnu.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1

# Copy application files
COPY . /app
WORKDIR /app

# Test script
RUN echo '#!/bin/bash\n\
export TABLE_NAME=${TABLE_NAME}\n\
export AWS_REGION=${AWS_REGION}\n\
nu main.nu status\n\
nu main.nu seed test-data.json\n\
# Run your tests here\n\
echo "✅ Tests completed"' > test.sh \
    && chmod +x test.sh

CMD ["./test.sh"]
```

These examples demonstrate real-world usage patterns and can be adapted for your specific needs. Each script includes error handling and follows best practices for production use.