# GitHub Actions Integration

Complete guide to using DynamoDB Nu-Loader in CI/CD pipelines.

## 🔧 Setup

### Prerequisites
- AWS credentials configured in GitHub Secrets
- DynamoDB table already created (use Terraform/CloudFormation)
- Nushell available in the runner environment

### Basic Workflow

```yaml
name: Test with DynamoDB Nu-Loader
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    # Setup Nushell using the official action
    - name: Setup Nushell
      uses: hustcer/setup-nu@v3
      with:
        version: "0.98.0"
    
    # Configure AWS credentials
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-east-1
    
    # Test the tool
    - name: Test DynamoDB operations
      env:
        TABLE_NAME: test-table
        AWS_REGION: us-east-1
        SNAPSHOTS_DIR: ./snapshots
      run: |
        # Test table connectivity
        nu main.nu status
        
        # Create a backup before testing
        nu main.nu snapshot pre-test-backup
        
        # Load test data
        nu main.nu seed seed-data.json
        
        # Run your application tests here
        ./run-tests.sh
        
        # Restore original state (optional)
        nu main.nu restore pre-test-backup.json
```

## 🏗️ Advanced Patterns

### Matrix Testing with Multiple Tables

```yaml
strategy:
  matrix:
    table: [users-test, products-test, orders-test]
    
steps:
- name: Test ${{ matrix.table }}
  env:
    TABLE_NAME: ${{ matrix.table }}
  run: |
    nu main.nu seed data/${{ matrix.table }}.json
    npm test -- --table=${{ matrix.table }}
```

### Conditional Data Seeding

```yaml
- name: Seed data for feature branches
  if: github.ref != 'refs/heads/main'
  run: |
    nu main.nu seed test-data.json
    
- name: Use production-like data for main
  if: github.ref == 'refs/heads/main'
  run: |
    nu main.nu seed production-seed.json
```

### Parallel Testing with Unique Tables

```yaml
jobs:
  test:
    strategy:
      matrix:
        test-suite: [unit, integration, e2e]
    
    steps:
    - name: Create unique table name
      id: table
      run: echo "name=test-${{ matrix.test-suite }}-${{ github.run_id }}" >> $GITHUB_OUTPUT
    
    - name: Test with isolated data
      env:
        TABLE_NAME: ${{ steps.table.outputs.name }}
      run: |
        # Create table (if using Terraform/CDK)
        terraform apply -var="table_name=${{ steps.table.outputs.name }}"
        
        # Seed and test
        nu main.nu seed ${{ matrix.test-suite }}-data.json
        npm test -- --suite=${{ matrix.test-suite }}
        
        # Cleanup
        terraform destroy -var="table_name=${{ steps.table.outputs.name }}"
```

## 🔐 Security Best Practices

### Environment Variables

```yaml
env:
  # Required variables
  TABLE_NAME: ${{ secrets.DYNAMODB_TABLE_NAME }}
  AWS_REGION: ${{ secrets.AWS_REGION }}
  SNAPSHOTS_DIR: ./snapshots
  
  # Optional: Limit AWS permissions
  AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
```

### IAM Permissions

Minimal IAM policy for CI/CD:

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
      "Resource": [
        "arn:aws:dynamodb:*:*:table/test-*",
        "arn:aws:dynamodb:*:*:table/*-test",
        "arn:aws:dynamodb:*:*:table/ci-*"
      ]
    }
  ]
}
```

## 📊 Performance Optimization

### Caching Snapshots

```yaml
- name: Cache test data snapshots
  uses: actions/cache@v3
  with:
    path: snapshots/
    key: test-data-${{ hashFiles('seed-data.json') }}
    
- name: Create snapshot if not cached
  run: |
    if [ ! -f snapshots/baseline.json ]; then
      nu main.nu seed seed-data.json
      nu main.nu snapshot baseline
    fi
```

### Parallel Operations

```yaml
- name: Parallel data operations
  run: |
    # Create multiple snapshots in parallel for different test suites
    nu main.nu seed unit-test-data.json &
    TABLE_NAME=integration-table nu main.nu seed integration-data.json &
    wait
```

## 🐛 Troubleshooting

### Common Issues

**1. Table Not Found**
```yaml
- name: Verify table exists
  run: |
    nu main.nu status || {
      echo "Table $TABLE_NAME not found. Check:"
      echo "1. TABLE_NAME environment variable"
      echo "2. AWS region configuration"
      echo "3. Table creation in infrastructure"
      exit 1
    }
```

**2. Permission Errors**
```yaml
- name: Test AWS permissions
  run: |
    aws sts get-caller-identity
    aws dynamodb describe-table --table-name $TABLE_NAME
```

**3. Nushell Not Available**
```yaml
- name: Verify Nushell installation
  run: |
    nu --version
    which nu
```

## 🔄 Complete Example Workflow

```yaml
name: Full Test Pipeline
on: 
  push:
  pull_request:

env:
  AWS_REGION: us-east-1
  SNAPSHOTS_DIR: ./snapshots

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Setup Nushell
      uses: hustcer/setup-nu@v3
      with:
        version: "0.98.0"
        check-latest: true
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Create unique test table
      id: setup
      run: |
        TABLE_NAME="test-$(date +%s)-${{ github.run_number }}"
        echo "table_name=$TABLE_NAME" >> $GITHUB_OUTPUT
        
        # Create table using AWS CLI
        aws dynamodb create-table \
          --table-name $TABLE_NAME \
          --attribute-definitions \
            AttributeName=id,AttributeType=S \
            AttributeName=sort_key,AttributeType=S \
          --key-schema \
            AttributeName=id,KeyType=HASH \
            AttributeName=sort_key,KeyType=RANGE \
          --billing-mode PAY_PER_REQUEST
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name $TABLE_NAME
    
    - name: Test DynamoDB Nu-Loader
      env:
        TABLE_NAME: ${{ steps.setup.outputs.table_name }}
      run: |
        # Test basic functionality
        nu main.nu status
        
        # Test data operations
        nu main.nu seed seed-data.json
        nu main.nu snapshot test-snapshot
        nu main.nu wipe --force
        nu main.nu restore test-snapshot.json
        
        # Verify data integrity
        ITEM_COUNT=$(nu main.nu snapshot --dry-run 2>&1 | grep "Exact item count" | cut -d: -f2 | tr -d ' ')
        echo "Table contains $ITEM_COUNT items"
        
        if [ "$ITEM_COUNT" -eq "0" ]; then
          echo "❌ Data restore failed - table is empty"
          exit 1
        fi
        
        echo "✅ All tests passed"
    
    - name: Cleanup test table
      if: always()
      env:
        TABLE_NAME: ${{ steps.setup.outputs.table_name }}
      run: |
        aws dynamodb delete-table --table-name $TABLE_NAME || true
    
    - name: Upload snapshots as artifacts
      if: failure()
      uses: actions/upload-artifact@v3
      with:
        name: test-snapshots
        path: snapshots/
```

## 📚 References

- **[Nushell Setup Action](https://github.com/hustcer/setup-nu)** - Official Nushell GitHub Action
- **[AWS Configure Credentials](https://github.com/aws-actions/configure-aws-credentials)** - AWS credential setup
- **[GitHub Actions Documentation](https://docs.github.com/en/actions)** - Complete Actions guide
- **[DynamoDB Table Creation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/getting-started-step-1.html)** - AWS table setup guide