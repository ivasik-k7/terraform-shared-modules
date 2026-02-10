# Terraform AWS Bastion Module

A production-grade, highly configurable Terraform module that provisions a **hardened bastion host** inside your AWS VPC.

## Features

| Category | Capabilities |
|---|---|
| **Access** | SSH over the internet *or* port-less via AWS Systems Manager Session Manager |
| **Compute** | Launch Template → Auto Scaling Group with instance refresh |
| **Security** | Separate security group, IMDSv2, encrypted EBS, SSH hardening |
| **IAM** | Auto-created role with least-privilege policies *or* bring-your-own profile |
| **Observability** | CloudWatch Logs agent, SSM session logs (CW + S3), ASG SNS alerts |
| **Cost saving** | Scheduled scale-up / scale-down (e.g. business hours only) |
| **HA** | Warm pool support, multi-subnet placement |
| **Networking** | Optional EIP attachment (single-instance mode) |

---

## Architecture

```
Internet / VPN
      │  :22 (optional)
      ▼
┌─────────────────────────────────────────────┐
│  Security Group (bastion-sg)                │
│  Ingress: configurable CIDRs / SGs          │
│  Egress:  0.0.0.0/0                         │
└───────────────────┬─────────────────────────┘
                    │
        ┌───────────▼──────────┐
        │  Auto Scaling Group  │
        │  ┌────────────────┐  │
        │  │  EC2 Instance  │  │
        │  │  (AL2023)      │  │
        │  │  SSM Agent ✓   │  │
        │  │  CW Agent  ✓   │  │
        │  └────────────────┘  │
        └──────────────────────┘
                    │
        ┌───────────▼──────────────┐
        │  Private subnets / VPC   │
        │  (RDS, EKS, EC2, etc.)   │
        └──────────────────────────┘
```

---

## Quick Start

### Minimal – SSM only (no public IP, no key pair)

```hcl
module "bastion" {
  source = "path/to/module"

  name        = "myapp"
  environment = "dev"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-aaa", "subnet-bbb"]

  associate_public_ip = false
  ssm_enabled         = true
  key_name            = null
}
```

### Full – see [`examples/full/main.tf`](examples/full/main.tf)

---

## Requirements

| Name | Version |
|---|---|
| Terraform | >= 1.5.0 |
| AWS Provider | >= 5.0.0 |

---

## Variables

### General

| Variable | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — | Base name prefix for all resources |
| `environment` | `string` | `"prod"` | Environment label used in names and tags |
| `tags` | `map(string)` | `{}` | Additional tags for all resources |

### Networking

| Variable | Type | Default | Description |
|---|---|---|---|
| `vpc_id` | `string` | — | Target VPC ID |
| `subnet_ids` | `list(string)` | — | Subnet IDs for the ASG |
| `associate_public_ip` | `bool` | `true` | Assign a public IP to instances |
| `eip_enabled` | `bool` | `false` | Attach an Elastic IP (single-instance only) |

### Instance

| Variable | Type | Default | Description |
|---|---|---|---|
| `ami_id` | `string` | `null` | Custom AMI; `null` = auto-discover latest AL2023 |
| `instance_type` | `string` | `"t3.micro"` | EC2 instance type |
| `key_name` | `string` | `null` | EC2 key pair name; `null` = no key-based SSH |
| `user_data` | `string` | `null` | Full override of the bootstrapping script |
| `user_data_extra` | `string` | `""` | Commands appended to the built-in script |

### Auto Scaling

| Variable | Type | Default | Description |
|---|---|---|---|
| `asg_desired_capacity` | `number` | `1` | Desired instance count |
| `asg_min_size` | `number` | `1` | Minimum instance count |
| `asg_max_size` | `number` | `2` | Maximum instance count |
| `asg_instance_refresh_enabled` | `bool` | `true` | Rolling refresh on launch template changes |
| `asg_warm_pool_enabled` | `bool` | `false` | Pre-warm instances for fast scale-out |
| `schedule_enabled` | `bool` | `false` | Business-hours scheduled scaling |

### Security Groups

| Variable | Type | Default | Description |
|---|---|---|---|
| `allowed_cidr_blocks` | `list(string)` | `[]` | IPv4 CIDRs allowed on `ssh_port` |
| `allowed_ipv6_cidr_blocks` | `list(string)` | `[]` | IPv6 CIDRs allowed on `ssh_port` |
| `allowed_security_group_ids` | `list(string)` | `[]` | SG IDs allowed on `ssh_port` |
| `additional_security_group_ids` | `list(string)` | `[]` | Extra SGs attached to the bastion ENI |
| `ssh_port` | `number` | `22` | Overridable SSH port |

### IAM

| Variable | Type | Default | Description |
|---|---|---|---|
| `iam_instance_profile_arn` | `string` | `null` | Provide your own profile; `null` = module creates one |
| `iam_extra_policy_arns` | `list(string)` | `[]` | Additional policy ARNs for the auto-created role |
| `iam_role_permissions_boundary` | `string` | `null` | Permissions boundary for the auto-created role |

### SSM / Session Manager

| Variable | Type | Default | Description |
|---|---|---|---|
| `ssm_enabled` | `bool` | `true` | Attach `AmazonSSMManagedInstanceCore` policy |
| `ssm_logging_enabled` | `bool` | `false` | Ship session logs to CW / S3 |
| `ssm_cloudwatch_log_group_name` | `string` | `null` | Target CW log group for session logs |
| `ssm_s3_bucket_name` | `string` | `null` | Target S3 bucket for session logs |

### Storage

| Variable | Type | Default | Description |
|---|---|---|---|
| `root_volume_size` | `number` | `20` | Root EBS size in GiB |
| `root_volume_type` | `string` | `"gp3"` | EBS volume type |
| `root_volume_encrypted` | `bool` | `true` | Encrypt root volume |
| `root_volume_kms_key_id` | `string` | `null` | Custom KMS key for root volume |

### CloudWatch Logs

| Variable | Type | Default | Description |
|---|---|---|---|
| `cloudwatch_logs_enabled` | `bool` | `false` | Enable OS log shipping |
| `cloudwatch_log_retention_days` | `number` | `90` | Log retention period |
| `cloudwatch_log_group_kms_key_id` | `string` | `null` | KMS key for log group encryption |

---

## Outputs

| Output | Description |
|---|---|
| `security_group_id` | Bastion security group ID |
| `security_group_arn` | Bastion security group ARN |
| `autoscaling_group_name` | Name of the ASG |
| `autoscaling_group_arn` | ARN of the ASG |
| `launch_template_id` | Launch template ID |
| `iam_role_arn` | IAM role ARN (null if external profile) |
| `iam_instance_profile_arn` | Instance profile ARN in use |
| `cloudwatch_log_group_name` | CW log group name (null if disabled) |
| `eip_public_ip` | EIP public IP (null if disabled) |
| `ami_id` | AMI ID used by the launch template |
| `ssm_connect_command` | Ready-to-run `aws ssm start-session` command |

---

## Connecting

### Via AWS Systems Manager (recommended)

```bash
# One-liner from module output
aws ssm start-session --target <INSTANCE_ID> --region eu-west-1

# Port-forward to a private RDS instance
aws ssm start-session \
  --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["mydb.cluster-xyz.eu-west-1.rds.amazonaws.com"],"portNumber":["5432"],"localPortNumber":["15432"]}'
```

### Via SSH (when `key_name` is set)

```bash
ssh -i ~/.ssh/my-keypair.pem ec2-user@<BASTION_IP>

# ProxyJump to a private instance
ssh -J ec2-user@<BASTION_IP> ec2-user@10.0.1.50
```

---

## Security Considerations

- **IMDSv2** is enforced by default (`metadata_http_tokens = "required"`)
- **Root login** and **password authentication** are disabled by the hardening script
- **EBS volumes** are encrypted by default
- **Key-less access** via SSM eliminates the need to manage SSH key pairs or open port 22 to the internet
- Bastion IAM role follows least-privilege; only SSM and CloudWatch Agent policies are attached by default

---

## License

MIT
