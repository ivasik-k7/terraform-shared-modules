# ============================================================
# GENERAL
# ============================================================

variable "name" {
  description = "Base name used to prefix all created resources."
  type        = string
}

variable "environment" {
  description = "Environment label (e.g. dev, staging, prod). Used in tags and resource names."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}

# ============================================================
# NETWORKING
# ============================================================

variable "vpc_id" {
  description = "ID of the VPC in which the bastion will be deployed."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    List of subnet IDs to place bastion instances/ASG into.
    Provide public subnets for classic SSH-over-internet access,
    or private subnets when using AWS Systems Manager Session Manager only.
  EOT
  type        = list(string)
}

variable "associate_public_ip" {
  description = "Whether to associate a public IP address with bastion instances."
  type        = bool
  default     = true
}

variable "eip_enabled" {
  description = <<-EOT
    Attach an Elastic IP to the bastion (only valid when the ASG desired count is 1).
    Ignored when asg_desired_capacity > 1.
  EOT
  type        = bool
  default     = false
}

# ============================================================
# AMI / INSTANCE
# ============================================================

variable "ami_id" {
  description = <<-EOT
    AMI ID to use for the bastion instance.
    When null the module automatically selects the latest Amazon Linux 2023 AMI
    for the current region.
  EOT
  type        = string
  default     = null
}

variable "ami_owners" {
  description = "List of AMI owner account IDs used when performing automatic AMI lookup."
  type        = list(string)
  default     = ["amazon"]
}

variable "ami_filters" {
  description = <<-EOT
    Map of additional filters used during automatic AMI lookup.
    Keys are filter names; values are lists of filter patterns.
  EOT
  type        = map(list(string))
  default = {
    name                = ["al2023-ami-*-x86_64"]
    virtualization-type = ["hvm"]
    root-device-type    = ["ebs"]
    state               = ["available"]
  }
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Leave null to disable key-based SSH."
  type        = string
  default     = null
}

variable "user_data" {
  description = <<-EOT
    Raw user-data script rendered as a string.
    When provided this completely replaces the built-in bootstrapping script.
  EOT
  type        = string
  default     = null
}

variable "user_data_extra" {
  description = "Extra shell commands appended to the bottom of the built-in bootstrapping script."
  type        = string
  default     = ""
}

# ============================================================
# AUTO SCALING GROUP
# ============================================================

variable "asg_desired_capacity" {
  description = "Desired number of bastion instances."
  type        = number
  default     = 1
}

variable "asg_min_size" {
  description = "Minimum number of bastion instances."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of bastion instances."
  type        = number
  default     = 2
}

variable "asg_health_check_type" {
  description = "Health check type for the ASG. One of EC2 or ELB."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.asg_health_check_type)
    error_message = "asg_health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "asg_health_check_grace_period" {
  description = "Time (seconds) after instance comes into service before checking health."
  type        = number
  default     = 300
}

variable "asg_instance_refresh_enabled" {
  description = "Enable automatic instance refresh when the launch template changes."
  type        = bool
  default     = true
}

variable "asg_instance_refresh_min_healthy_percentage" {
  description = "Minimum percentage of healthy instances during an instance refresh."
  type        = number
  default     = 50
}

variable "asg_termination_policies" {
  description = "List of policies for selecting instances to terminate on scale-in."
  type        = list(string)
  default     = ["OldestLaunchTemplate", "Default"]
}

variable "asg_warm_pool_enabled" {
  description = "Enable a warm pool to reduce scale-out latency."
  type        = bool
  default     = false
}

variable "asg_warm_pool_min_size" {
  description = "Minimum number of instances kept in the warm pool."
  type        = number
  default     = 0
}

variable "asg_warm_pool_state" {
  description = "State of warm pool instances. One of: Stopped, Running, Hibernated."
  type        = string
  default     = "Stopped"
}

# ============================================================
# SECURITY GROUPS
# ============================================================

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to SSH into the bastion (port 22)."
  type        = list(string)
  default     = []
}

variable "allowed_ipv6_cidr_blocks" {
  description = "List of IPv6 CIDR blocks allowed to SSH into the bastion (port 22)."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "List of Security Group IDs that are allowed to connect to the bastion on port 22."
  type        = list(string)
  default     = []
}

variable "egress_cidr_blocks" {
  description = "CIDR blocks for egress rules on the bastion security group."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "egress_ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks for egress rules on the bastion security group."
  type        = list(string)
  default     = ["::/0"]
}

variable "additional_security_group_ids" {
  description = "Additional Security Group IDs to attach to the bastion ENI."
  type        = list(string)
  default     = []
}

variable "ssh_port" {
  description = "TCP port used for SSH access. Defaults to 22."
  type        = number
  default     = 22
}

# ============================================================
# IAM
# ============================================================

variable "iam_instance_profile_arn" {
  description = <<-EOT
    ARN of an existing IAM instance profile to attach to the bastion.
    When null the module creates a new role with the policies defined by
    ssm_enabled and iam_extra_policy_arns.
  EOT
  type        = string
  default     = null
}

variable "iam_role_permissions_boundary" {
  description = "ARN of an IAM permissions boundary to attach to the auto-created IAM role."
  type        = string
  default     = null
}

variable "iam_extra_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the auto-created IAM role."
  type        = list(string)
  default     = []
}

variable "iam_role_tags" {
  description = "Additional tags applied only to the IAM role."
  type        = map(string)
  default     = {}
}

# ============================================================
# AWS SYSTEMS MANAGER (SESSION MANAGER)
# ============================================================

variable "ssm_enabled" {
  description = <<-EOT
    Attach the AmazonSSMManagedInstanceCore policy to allow AWS Systems Manager
    Session Manager access (port-less, key-less SSH alternative).
  EOT
  type        = bool
  default     = true
}

variable "ssm_logging_enabled" {
  description = "Send SSM Session Manager logs to CloudWatch and/or S3."
  type        = bool
  default     = false
}

variable "ssm_cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for SSM session logs. Required when ssm_logging_enabled = true."
  type        = string
  default     = null
}

variable "ssm_s3_bucket_name" {
  description = "S3 bucket name for SSM session logs. Optional even when ssm_logging_enabled = true."
  type        = string
  default     = null
}

variable "ssm_s3_key_prefix" {
  description = "S3 key prefix for SSM session logs."
  type        = string
  default     = "ssm-session-logs/"
}

# ============================================================
# STORAGE
# ============================================================

variable "root_volume_size" {
  description = "Size (GiB) of the root EBS volume."
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "Type of the root EBS volume. One of: gp2, gp3, io1, io2."
  type        = string
  default     = "gp3"
}

variable "root_volume_iops" {
  description = "IOPS for gp3/io1/io2 root volumes."
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "Throughput (MiB/s) for gp3 root volumes."
  type        = number
  default     = 125
}

variable "root_volume_encrypted" {
  description = "Encrypt the root EBS volume."
  type        = bool
  default     = true
}

variable "root_volume_kms_key_id" {
  description = "KMS key ID/ARN for root volume encryption. Defaults to the AWS-managed key when null."
  type        = string
  default     = null
}

variable "root_volume_delete_on_termination" {
  description = "Delete the root EBS volume when the instance is terminated."
  type        = bool
  default     = true
}

# ============================================================
# METADATA / IMDS
# ============================================================

variable "metadata_http_tokens" {
  description = <<-EOT
    IMDSv2 token requirement. 'required' enforces IMDSv2 (recommended).
    Set to 'optional' only for legacy workloads.
  EOT
  type        = string
  default     = "required"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be 'required' or 'optional'."
  }
}

variable "metadata_http_put_response_hop_limit" {
  description = "IMDSv2 hop limit for PUT responses."
  type        = number
  default     = 1
}

variable "metadata_instance_metadata_tags" {
  description = "Enable access to instance tags via the IMDS."
  type        = string
  default     = "enabled"
}

# ============================================================
# SSH HARDENING & AUTHORIZED KEYS
# ============================================================

variable "ssh_authorized_keys" {
  description = <<-EOT
    List of SSH public keys to add to the ec2-user's authorized_keys file
    via the built-in bootstrapping script.
  EOT
  type        = list(string)
  default     = []
}

variable "ssh_hardening_enabled" {
  description = "Apply basic SSH hardening (disable root login, disable password auth, etc.)."
  type        = bool
  default     = true
}

# ============================================================
# CLOUDWATCH
# ============================================================

variable "cloudwatch_logs_enabled" {
  description = "Ship /var/log/secure and /var/log/messages to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for OS logs. Auto-generated when null."
  type        = string
  default     = null
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period in days for the CloudWatch Log Group."
  type        = number
  default     = 90
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "KMS key ARN for CloudWatch Log Group encryption."
  type        = string
  default     = null
}

# ============================================================
# SNS NOTIFICATIONS
# ============================================================

variable "sns_notifications_enabled" {
  description = "Send ASG lifecycle notifications to an SNS topic."
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to receive ASG notifications."
  type        = string
  default     = null
}

variable "sns_notification_types" {
  description = "List of ASG notification types to forward to the SNS topic."
  type        = list(string)
  default = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
}

# ============================================================
# SCHEDULED SCALING (COST SAVING)
# ============================================================

variable "schedule_enabled" {
  description = "Enable scheduled scale-in / scale-out actions (e.g. business hours only)."
  type        = bool
  default     = false
}

variable "schedule_scale_up_recurrence" {
  description = "Cron expression for scaling up (UTC). Example: '0 7 * * MON-FRI'."
  type        = string
  default     = "0 7 * * MON-FRI"
}

variable "schedule_scale_up_desired" {
  description = "Desired capacity during scale-up window."
  type        = number
  default     = 1
}

variable "schedule_scale_down_recurrence" {
  description = "Cron expression for scaling down (UTC). Example: '0 19 * * MON-FRI'."
  type        = string
  default     = "0 19 * * MON-FRI"
}

variable "schedule_scale_down_desired" {
  description = "Desired capacity during scale-down window (typically 0)."
  type        = number
  default     = 0
}
