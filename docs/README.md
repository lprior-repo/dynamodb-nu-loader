# DynamoDB Nu-Loader Documentation

Complete guide to using DynamoDB Nu-Loader for test data management.

## 📖 Table of Contents

- **[Commands Reference](./commands.md)** - Detailed documentation for all commands
- **[File Formats](./formats.md)** - Supported data formats and examples
- **[GitHub Actions](./github-actions.md)** - CI/CD pipeline integration
- **[Examples](./examples.md)** - Common usage patterns and workflows
- **[Nushell Guide](./nushell-guide.md)** - Understanding the code for newcomers

## 🚀 Quick Navigation

### Getting Started
1. [Installation Prerequisites](../README.md#prerequisites)
2. [Quick Start Guide](../README.md#quick-start)
3. [Safety Guidelines](../README.md#safety-first)

### Core Operations
- **Safe Commands**: [`status`](./commands.md#status), [`snapshot`](./commands.md#snapshot)
- **Destructive Commands**: [`seed`](./commands.md#seed), [`restore`](./commands.md#restore), [`wipe`](./commands.md#wipe)

### Advanced Usage
- [Batch Operations](./examples.md#batch-operations)
- [Error Handling](./examples.md#error-handling)
- [CI/CD Integration](./github-actions.md)

## 🔗 External Resources

### AWS Documentation
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)
- [AWS CLI Command Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/dynamodb/index.html)
- [DynamoDB API Reference](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/)

### Nushell Resources
- [Nushell Book](https://www.nushell.sh/book/) - Complete programming guide
- [Command Reference](https://www.nushell.sh/commands/) - All built-in commands
- [Language Guide](https://www.nushell.sh/book/lang-guide.html) - Language fundamentals
- [Community Discord](https://discord.gg/NtAbbGn) - Get help from the community

## 🎯 Use Cases

This tool is designed for:

1. **Test Data Management**: Quick setup and teardown of test datasets
2. **Development Workflows**: Instant data resets between test runs
3. **CI/CD Pipelines**: Automated data seeding and cleanup
4. **Data Migration**: Backup and restore operations
5. **Environment Management**: Syncing data between environments

## 📝 Contributing

Found a bug or want to contribute? See our [contributing guidelines](../CONTRIBUTING.md).

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.