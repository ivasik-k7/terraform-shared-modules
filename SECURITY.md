# Security Policy

To make this table look more professional and visually clear for a GitHub repository, we can add **Status** and **Security Support** columns. This helps users understand at a glance whether they should migrate or if their current version is safe.

## Supported Versions

We are committed to providing security updates for the current major release. To ensure your infrastructure remains secure, please use the latest versions.

| Version      | Status          | Security Updates   | Recommended Action                |
| ------------ | --------------- | ------------------ | --------------------------------- |
| **v1.x.x**   | 🟢 Active       | :white_check_mark: | Use latest stable release         |
| **v0.x.x**   | 🔴 End of Life  | :x:                | **Upgrade to v1.x.x immediately** |
| **Beta/Dev** | 🟡 Experimental | :warning:          | Use for testing only              |

---

### Why this is better:

- **Status Indicators:** Emojis (🟢/🔴) provide an instant visual cue that doesn't rely solely on reading the text.
- **Recommended Action:** It tells the user exactly what to do if they are on an unsupported version, which reduces support questions.
- **Clearer Versioning:** Adding the `v` prefix and bold text makes the versions stand out better in Markdown.

Would you like me to add a section below this table that explains **how** users should handle breaking changes when moving from `< 1.0` to `1.x.x`?

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in this project, please report it responsibly.

### How to Report

**Please do NOT create a public GitHub issue for security vulnerabilities.**

Instead, please report security issues by emailing:

📧 **kovtun.ivan@proton.me**

**Please include the following information:**

- **Description** of the vulnerability
- **Steps to reproduce** the issue
- **Potential impact** assessment
- **Suggested fix** (if available)

### What to Expect

1. **Acknowledgment** - We'll acknowledge receipt within 48 hours.
2. **Assessment** - We'll assess the vulnerability within 5 business days.
3. **Resolution** - We'll work on a fix and coordinate disclosure.
4. **Credit** - We'll credit you in the security advisory (if desired).

---

## Security Considerations for Infrastructure Code

### High-Risk Areas

- **IAM Policies** - Overly permissive access controls.
- **Security Groups** - Open ingress rules (e.g., `0.0.0.0/0`).
- **Encryption** - Missing or weak encryption configurations.
- **Secrets Management** - Hardcoded credentials or keys.
- **Network Security** - Insecure network configurations.

### Common Vulnerabilities

- **Privilege Escalation** - IAM roles with excessive permissions.
- **Data Exposure** - Unencrypted storage or transmission.
- **Network Exposure** - Resources accessible from the internet.
- **Credential Leakage** - Secrets in code or logs.
- **Misconfiguration** - Insecure default settings.

---

## Security Best Practices

### For Contributors

- Never commit secrets, API keys, or credentials.
- Use `sensitive = true` for sensitive variables.
- Follow the principle of least privilege for IAM.
- Enable encryption by default where available.
- Validate input parameters to prevent injection.
- Use secure defaults in module configurations.

### For Users

- Review all module configurations before deployment.
- Use AWS Config Rules to monitor compliance.
- Enable CloudTrail for audit logging.
- Regularly rotate credentials and access keys.
- Monitor AWS Security Hub for security findings.
- Keep Terraform and provider versions updated.

---

## Security Testing

We recommend using these tools to scan infrastructure code:

- **Checkov** - Static analysis for Terraform
- **tfsec** - Security scanner for Terraform
- **Terrascan** - Policy as code scanner
- **AWS Config** - Compliance monitoring
- **AWS Security Hub** - Centralized security findings

---

## Disclosure Policy

- We follow responsible disclosure practices.
- Security patches will be backported to supported versions.
- We'll publish security advisories for confirmed vulnerabilities.
- We may request coordinated disclosure timing for critical issues.

## Contact Information

For security-related questions or concerns:

- **Email**: [kovtun.ivan@proton.me](mailto:kovtun.ivan@proton.me)
- **Subject**: `[SECURITY] Brief description`
- **PGP Key**: Available upon request.

## Hall of Fame

We recognize security researchers who help improve our project:

_No security issues have been reported yet._
