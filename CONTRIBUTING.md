# Contributing to AWS Infrastructure Terraform Modules

Thank you for your interest in contributing to this project! This guide will help you understand our workflow and how to contribute effectively.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)
- [Module Standards](#module-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)
- [Release Process](#release-process)

---

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

- **Terraform** >= 1.5.0
- **AWS CLI** configured with appropriate credentials
- **Git** for version control
- **Make** (optional, for automation)

### Development Setup

1. **Fork** the repository on GitHub.
2. **Clone** your fork:

   ```bash
   git clone [https://github.com/YOUR_USERNAME/tf-modules.git](https://github.com/YOUR_USERNAME/tf-modules.git)
   cd tf-modules
   ```

3. **Create a feature branch**:

   ```bash
   git checkout -b feature/your-feature-name
   ```

## Contributing Guidelines

### Types of Contributions

- **Bug fixes** - Fix issues in existing modules.
- **New modules** - Add support for new AWS services.
- **Enhancements** - Improve existing module functionality.
- **Documentation** - Improve or add documentation.
- **Examples** - Add usage examples.

### Before You Start

1. Check existing [Issues](https://www.google.com/search?q=../../issues) and [Pull Requests](https://www.google.com/search?q=../../pulls).
2. Create an issue to discuss major changes before starting work.
3. Follow the module standards outlined below.

---

## Module Standards

### File Structure

Each module must follow this standard directory structure:

```text
modules/service-name/
├── main.tf          # Primary resources
├── variables.tf     # Input variables
├── outputs.tf       # Output values
├── versions.tf      # Provider requirements
├── README.md        # Module documentation
└── examples/        # Usage examples
    └── basic/
        ├── main.tf
        └── README.md
```

### Code Standards

- **Formatting:** Use `terraform fmt -recursive` before committing.
- **Variable Naming:** Use descriptive names (e.g., `cluster_identifier` instead of `name`). Use `snake_case`.
- **Resource Naming:** Use `this` for primary resources (e.g., `aws_sns_topic.this`).
- **Documentation:** Add `description` to all variables and outputs.

### Example Variable Definition

```hcl
variable "cluster_identifier" {
  description = "The cluster identifier for the Aurora cluster"
  type        = string

  validation {
    condition     = length(var.cluster_identifier) > 0 && length(var.cluster_identifier) <= 63
    error_message = "Cluster identifier must be between 1 and 63 characters."
  }
}
```

### Security Requirements

- **No hardcoded secrets** - Use variables marked as `sensitive = true`.
- **Encryption by default** - Enable encryption where available.
- **Least privilege** - Follow principle of least privilege for IAM.

---

## Testing

### Local Testing

Run these commands locally before submitting a PR:

1. **Validation**: `terraform validate`
2. **Formatting**: `terraform fmt -check -recursive`
3. **Plan Testing**: `terraform plan` (requires AWS credentials)

### Integration Testing

- Test with real AWS resources in a sandbox/development account.
- Verify resource creation, updates (idempotency), and destruction.

---

## Documentation

### README Requirements

Each module must include a `README.md` containing:

- **Description** & **Features**.
- **Usage examples**.
- **Inputs/Outputs** (Automatically generated).

### Documentation Generation

We use [terraform-docs](https://terraform-docs.io/) to maintain consistency:

```bash
terraform-docs markdown table --output-file README.md .
```

---

## Pull Request Process

### PR Requirements

- **Clear title** - Describe the impact.
- **Detailed description** - Explain the "why" and "how".
- **Test results** - Include a summary of your `terraform plan` output.

### PR Template

```markdown
## Description

Brief description of changes

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing

- [ ] terraform validate passes
- [ ] terraform fmt passes
- [ ] Tested with real AWS resources
```

---

## Release Process

### Versioning

We follow [Semantic Versioning (SemVer)](https://semver.org/):

- **MAJOR**: Breaking changes (e.g., removing a required variable).
- **MINOR**: New features (backward compatible).
- **PATCH**: Bug fixes.

## Getting Help

- **Issues**: Create an issue for bugs.
- **Discussions**: Use GitHub Discussions for Q&A.
- **Email**: Contact [kovtun.ivan@proton.me](mailto:kovtun.ivan@proton.me).

## License

By contributing, you agree that your contributions will be licensed under the project's **MIT License**.

---

Thank you for contributing to making infrastructure as code better! 🚀
