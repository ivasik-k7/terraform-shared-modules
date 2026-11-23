# ---------------------------------------------------------------------------
# Module
# ---------------------------------------------------------------------------

variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of everything the module names: the ECS cluster and manager services, the Auto Scaling groups (<name>-<pool>-...), the security groups, the key pair, the token parameters (/<name>/<pool>/runner-token) and the ECR repositories."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}$", var.name))
    error_message = "name must be 2-19 characters: lowercase letters, digits and hyphens, starting with a letter. Each fleet is named <name>-<pool>, which modules/asg-group caps at 36 characters."
  }
}

variable "tags" {
  description = "Tags on every resource, the job instances and their volumes included. The module adds ManagedBy and Module last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "required_tag_keys" {
  description = "Tag keys that must be present and non-empty in tags, such as CostCenter. Checked by the fleet and manager modules too."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name: this module's (README, \"Advisory checks\") and those of modules/asg-group, modules/ecs and modules/s3 (the cache bucket), which are passed on to them. The checks the autoscaler's design trips by construction are acknowledged already (README)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for c in var.acknowledged_checks : contains([
      "privileged_jobs_get_their_own_instance",
      "fleet_survives_an_az", "spot_fleets_keep_an_on_demand_floor", "volumes_use_a_customer_key", "burstable_credits_are_bounded",
      "instances_have_no_public_ip", "containers_cannot_reach_instance_credentials", "ami_is_pinned", "somebody_hears_a_failure",
      "deployments_roll_back", "images_are_pinned", "log_retention_is_bounded", "logs_use_a_customer_key", "task_costs_are_attributable",
      "running_task_alarms_have_data", "roles_are_not_administrators", "secrets_are_not_in_environment",
      "jobs_hold_aws_credentials", "access_is_logged", "data_uses_a_customer_key",
    ], c)])
    error_message = "acknowledged_checks names a check that does not exist here or in modules/asg-group, modules/ecs or modules/s3."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for every IAM role created: the manager task and execution roles and the instance roles. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

# ---------------------------------------------------------------------------
# GitLab and images
# ---------------------------------------------------------------------------

variable "gitlab_url" {
  description = "The GitLab instance the runners register with, for example https://gitlab.example.com."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/.*)?$", var.gitlab_url))
    error_message = "gitlab_url must be an https:// URL."
  }
}

variable "runner_version" {
  description = "GitLab Runner version in manager_image, as x.y.z. Keep its major.minor equal to GitLab's. The helper image is coupled to it exactly: a mismatch makes every job fail with \"No such image\"."
  type        = string
  nullable    = false

  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version)) ? (
      tonumber(split(".", var.runner_version)[0]) > 17 ? true : (tonumber(split(".", var.runner_version)[0]) == 17 ? tonumber(split(".", var.runner_version)[1]) >= 1 : false)
    ) : false
    error_message = "runner_version must be x.y.z and 17.1.0 or later, where the docker-autoscaler executor is generally available."
  }
}

variable "manager_image" {
  description = "The manager image, built outside the module (images/manager/build.sh in this module is one way): the official gitlab-runner image plus fleeting-plugin-aws and docker-credential-ecr-login, and the entrypoint that writes config.toml. Pin a tag or digest."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})$", var.manager_image)) ? !endswith(var.manager_image, ":latest") : false
    error_message = "manager_image must be a registry image reference with a tag (not latest) or a digest."
  }
}

variable "helper_image" {
  description = "The gitlab-runner-helper image the job instances use, copied outside the module into ECR or a mirror (images/mirror.sh): the default is on registry.gitlab.com, which an isolated network cannot reach. Its tag carries x86_64-v<runner_version>."
  type        = string
  nullable    = false

  validation {
    condition     = strcontains(var.helper_image, "x86_64-v${var.runner_version}")
    error_message = "helper_image must be tagged for this runner_version (…x86_64-v<runner_version>): GitLab couples the two exactly, and a mismatch fails every job."
  }
}

variable "ca_certificate_pem" {
  description = "PEM bundle of the private CA that signs gitlab_url's certificate, if it is not publicly trusted. Written to the manager as tls-ca-file. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ca_certificate_pem == "" ? true : strcontains(var.ca_certificate_pem, "BEGIN CERTIFICATE")
    error_message = "ca_certificate_pem must be empty or PEM certificates."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the job images come from. The manager's docker-credential-ecr-login authenticates pulls with its task role, which may pull exactly these."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", a))])
    error_message = "ecr_repository_arns must be ECR repository ARNs."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC the managers and job instances run in. The module creates their two security groups there."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID."
  }
}

variable "subnet_ids" {
  description = "Private subnets for the managers and job instances, two AZs or more. They need the endpoints in output.network_contract; no public IP is ever assigned."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0 ? alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) : false
    error_message = "subnet_ids must hold one or more subnet IDs."
  }
}

variable "egress_cidr_blocks" {
  description = "Where managers and instances may open 443: the VPC endpoints, GitLab and the registries. Include the VPC's own CIDR, where the interface endpoints live."
  type        = list(string)
  default     = ["10.0.0.0/8"]
  nullable    = false

  validation {
    condition     = length(var.egress_cidr_blocks) > 0 ? alltrue([for c in var.egress_cidr_blocks : can(cidrnetmask(c)) ? c != "0.0.0.0/0" : false]) : false
    error_message = "egress_cidr_blocks must be IPv4 CIDRs, not 0.0.0.0/0."
  }
}

variable "instance_security_group_ids" {
  description = "Further security groups on the job instances, for jobs that must reach something beyond 443 (a database, a deploy target). The module's own group allows SSH from the managers and 443 out."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.instance_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "instance_security_group_ids must be security group IDs."
  }
}

variable "s3_prefix_list_id" {
  description = "The S3 managed prefix list for the egress rules. Empty: looked up by name (com.amazonaws.<region>.s3)."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.s3_prefix_list_id == "" ? true : can(regex("^pl-[0-9a-f]+$", var.s3_prefix_list_id))
    error_message = "s3_prefix_list_id must be empty or a prefix list ID."
  }
}

# ---------------------------------------------------------------------------
# Job instances
# ---------------------------------------------------------------------------

variable "ami_id" {
  description = "AMI of the job instances: one with Docker Engine, such as the Amazon ECS-optimized Amazon Linux 2023 AMI (the module turns its ECS agent off). Pinned, because the fleet is never refreshed: new instances take a new AMI and old ones end at max_use_count."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID."
  }
}

variable "ssh_public_key" {
  description = "Public key the managers connect to the instances with, installed for ec2-user through an EC2 key pair. Static credentials, so neither EC2 Instance Connect nor its endpoint is needed."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/=]+", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "secrets_kms_key_arns" {
  description = "Customer managed keys of the runner token parameters or secrets and of the SSH key secret, if any. The managers' execution roles may decrypt with them through SSM and Secrets Manager only."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for k in var.secrets_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", k))])
    error_message = "secrets_kms_key_arns must be KMS key ARNs."
  }
}

variable "ssh_private_key_secret_arn" {
  description = "Secrets Manager secret holding the matching private key (PEM or OpenSSH), created outside Terraform so it is in no state file. Injected into the managers only."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.ssh_private_key_secret_arn))
    error_message = "ssh_private_key_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key for the manager logs, the instance volumes and the cache bucket the module creates. Empty: AWS-owned or AWS-managed keys. The key policy requirements are in output.kms_key_policy_requirements."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

# ---------------------------------------------------------------------------
# Pools
# ---------------------------------------------------------------------------

variable "pools" {
  description = <<-EOT
    Runner pools, keyed by a short name. Each is one runner in GitLab (its own token and tags), one manager task on
    ECS Fargate, and its own Auto Scaling group: GitLab requires a dedicated group per docker-autoscaler configuration.
      token_arn              the SSM SecureString parameter or Secrets Manager secret holding the runner's glrt- token.
                             Created and written outside Terraform, so the token is in no state file
      job_image              default image for jobs without image:
      privileged             privileged job containers (Docker builds). Each job then gets its own instance, deleted after it
      capacity_per_instance  jobs per instance at once. Unset: 1 when privileged, else 4
      max_use_count          jobs an instance runs before it is deleted (0: unlimited). Unset: 1 when privileged, else 50
      max_instances          the ceiling of the pool, and of its bill
      instance_types         in order of preference; spot = true runs them on Spot above on_demand_base
      idle                   policies by time of day: idle_count is ready job slots, idle_time how long an idle instance lives
      token_revision         bump after replacing the token: the manager reads it only at start
      enabled                false runs no manager (desired count 0), and the stopping manager deletes its instances
      shared_cache           use the cache bucket (var.cache), under the prefix <pool>/, which only this pool's manager may sign for
      aws_access             AWS credentials for every job in the pool, through the instance role (IMDS hop limit 2):
        policies, managed_policies   on the instance role itself
        assume_role_arns             roles jobs may assume; give them output.job_role_trust_policies[<pool>]
      Make a pool with aws_access a protected runner in GitLab, so only protected branches and tags run on it.
    Instances are billed per second while they run (m7i.large $0.11655 per hour in eu-west-2), the manager task at Fargate
    rates (0.5 vCPU / 1 GB: about $20 a month).
  EOT
  type = map(object({
    token_arn             = string
    job_image             = string
    privileged            = optional(bool, false)
    capacity_per_instance = optional(number)
    max_use_count         = optional(number)
    max_instances         = optional(number, 10)
    instance_types        = optional(list(string), ["m7i.large"])
    spot                  = optional(bool, false)
    on_demand_base        = optional(number, 0)
    root_volume_gib       = optional(number, 50)
    docker_volumes        = optional(list(string), [])
    idle = optional(list(object({
      periods            = list(string)
      timezone           = optional(string, "Etc/UTC")
      idle_count         = optional(number, 0)
      idle_time          = optional(string, "10m")
      scale_factor       = optional(number, 0)
      scale_factor_limit = optional(number, 0)
    })), [])
    manager_cpu    = optional(number, 512)
    manager_memory = optional(number, 1024)
    token_revision = optional(number, 1)
    enabled        = optional(bool, true)
    shared_cache   = optional(bool, true)
    aws_access = optional(object({
      policies         = optional(map(string), {})
      managed_policies = optional(map(string), {})
      assume_role_arns = optional(list(string), [])
    }))
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, p in var.pools : can(regex("^[a-z][a-z0-9-]{0,15}$", k))])
    error_message = "pools keys must be 1-16 lowercase letters, digits or hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for k, p in var.pools : can(regex("^arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{12}:parameter/.+$", p.token_arn)) ? true : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", p.token_arn))])
    error_message = "pools[*].token_arn must be the ARN of an SSM parameter or a Secrets Manager secret."
  }

  validation {
    condition = alltrue([for k, p in var.pools : alltrue([
      p.capacity_per_instance == null ? true : (p.capacity_per_instance >= 1 ? p.capacity_per_instance <= 100 : false),
      p.max_use_count == null ? true : p.max_use_count >= 0,
      p.max_instances >= 1, p.max_instances <= 1000,
      alltrue([for n in [p.max_instances, p.on_demand_base, p.root_volume_gib, p.token_revision, coalesce(p.capacity_per_instance, 1), coalesce(p.max_use_count, 0)] : floor(n) == n]),
      p.on_demand_base >= 0, p.on_demand_base <= p.max_instances,
      p.root_volume_gib >= 30, p.root_volume_gib <= 16384,
      length(p.instance_types) > 0,
      alltrue([for t in p.instance_types : can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", t))]),
      p.token_revision >= 1,
    ])])
    error_message = "pools: whole numbers throughout; capacity_per_instance 1-100, max_use_count 0 or more, max_instances 1-1000, on_demand_base 0 to max_instances, root_volume_gib 30-16384 (the ECS-optimized AMI's snapshot is 30 GiB), one or more instance types, token_revision 1 or more."
  }

  validation {
    condition = alltrue([for k, p in var.pools : alltrue([for i in p.idle : alltrue([
      length(i.periods) > 0,
      i.idle_count >= 0, floor(i.idle_count) == i.idle_count,
      can(regex("^[0-9]+(s|m|h)$", i.idle_time)),
      i.scale_factor >= 0,
      i.scale_factor_limit >= 0, floor(i.scale_factor_limit) == i.scale_factor_limit,
    ])])])
    error_message = "pools[*].idle: each policy has one or more cron periods, idle_count a whole number 0 or more, idle_time like 10m, scale_factor 0 or more, and scale_factor_limit a whole number 0 or more."
  }

  validation {
    # Fargate CPU and memory pairs up to 1 vCPU; a manager needs no more.
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html
    condition     = alltrue([for k, p in var.pools : contains(lookup({ "256" = [512, 1024, 2048], "512" = [1024, 2048, 3072, 4096], "1024" = [2048, 3072, 4096, 5120, 6144, 7168, 8192] }, tostring(p.manager_cpu), []), p.manager_memory)])
    error_message = "pools[*].manager_cpu and manager_memory must be a Fargate pair: 256 with 512-2048, 512 with 1024-4096, 1024 with 2048-8192."
  }

  validation {
    condition = alltrue([for k, p in var.pools : p.aws_access == null ? true : alltrue([
      length(p.aws_access.policies) + length(p.aws_access.managed_policies) + length(p.aws_access.assume_role_arns) > 0,
      alltrue([for n, d in p.aws_access.policies : can(regex("^[A-Za-z0-9+=,.@_-]{1,100}$", n)) ? can(jsondecode(d)) : false]),
      alltrue([for n, a in p.aws_access.managed_policies : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", a))]),
      alltrue([for a in p.aws_access.assume_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", a))]),
    ])])
    error_message = "pools[*].aws_access: at least one policy, managed policy or role; policies are name => JSON document, managed_policies IAM policy ARNs, assume_role_arns IAM role ARNs."
  }
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

variable "cache" {
  description = <<-EOT
    The distributed cache: one S3 bucket for every pool with shared_cache, so a job's cache survives the instance it
    ran on. The manager signs each upload and download with its task role; the job instance transfers the archive
    through the S3 gateway endpoint, so the bucket is never reachable from anywhere else that has no signature.
      enabled             false: cache stays on the instance and goes with it
      bucket_name         an existing bucket. Empty: the module creates <name>-runner-cache-<account>-<region>
                          through modules/s3, encrypted with kms_key_arn, unversioned
      bucket_kms_key_arn  the existing bucket's customer key, if it has one (the managers sign with it)
      expiration_days     cache objects are deleted this long after they were last written. Storage is
                          $0.024 per GB-month in eu-west-2 (COSTS.md); this is what bounds it
      compression_level   fastest, fast, default, slow, slowest
      compression_format  zip, tarzstd, zipzstd. tarzstd is smaller and faster to unpack than zip
      max_archive_gib     archives above this are not uploaded (0: no limit)
      vpc_endpoint_ids    deny object access that does not come through these S3 endpoints (created bucket only)
  EOT
  type = object({
    enabled            = optional(bool, true)
    bucket_name        = optional(string, "")
    bucket_kms_key_arn = optional(string, "")
    expiration_days    = optional(number, 14)
    compression_level  = optional(string, "fast")
    compression_format = optional(string, "tarzstd")
    max_archive_gib    = optional(number, 0)
    vpc_endpoint_ids   = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.cache.bucket_name == "" ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.cache.bucket_name)),
      var.cache.bucket_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.cache.bucket_kms_key_arn)),
      var.cache.bucket_kms_key_arn == "" ? true : var.cache.bucket_name != "",
      var.cache.expiration_days >= 1, floor(var.cache.expiration_days) == var.cache.expiration_days,
      contains(["fastest", "fast", "default", "slow", "slowest"], var.cache.compression_level),
      contains(["zip", "tarzstd", "zipzstd"], var.cache.compression_format),
      var.cache.max_archive_gib >= 0,
      alltrue([for e in var.cache.vpc_endpoint_ids : can(regex("^vpce-[0-9a-f]{8,17}$", e))]),
      length(var.cache.vpc_endpoint_ids) == 0 ? true : var.cache.bucket_name == "",
    ])
    error_message = "cache: bucket_name a bucket name; bucket_kms_key_arn a KMS key ARN, only with bucket_name; expiration_days a whole number 1 or more; compression_level fastest, fast, default, slow or slowest; compression_format zip, tarzstd or zipzstd; max_archive_gib 0 or more; vpc_endpoint_ids vpce- IDs, only for a bucket the module creates."
  }
}

variable "docker_registry_mirror" {
  description = "Docker Hub pull-through mirror (https://host[:port], served at the host's root, not under a path) the job instances' Docker uses for images named without a registry, such as alpine:3.20. Merged into /etc/docker/daemon.json by user data. Empty: Docker Hub, which an isolated network cannot reach. Images from other registries are not affected."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.docker_registry_mirror == "" ? true : can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$", var.docker_registry_mirror))
    error_message = "docker_registry_mirror must be empty or https://host[:port], without a path."
  }
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "monitoring" {
  description = <<-EOT
    What watches the runners, per pool, besides the alarms modules/ecs and modules/asg-group create (manager CPU,
    memory and running tasks; failed launches). Alarms notify sns_topic_arn ($0.10 per alarm-month).
      alarms                       manager errors, jobs failed by the runner's own system, the fleet at its ceiling,
                                   and instances billing while their manager is down
      error_threshold              manager error log lines in 15 minutes that raise the errors alarm
      system_failure_threshold     jobs failed with runner_system_failure in 15 minutes that raise that alarm
      ceiling_minutes              minutes at max_instances before the ceiling alarm
      dashboard                    one CloudWatch dashboard for every pool ($3 per month)
      metrics_collector_image      an AWS Distro for OpenTelemetry collector image the subnets can pull. Set: a
                                   sidecar scrapes each manager's Prometheus metrics (jobs, queue, fleeting instances
                                   and tasks) into CloudWatch namespace GitLabRunner, with an alarm on jobs that timed
                                   out waiting for an instance. Each metric and label set is a custom metric
                                   ($0.30 per month). Empty: no sidecar
      metrics_retention_days       retention of the collector's log group
  EOT
  type = object({
    alarms                   = optional(bool, true)
    error_threshold          = optional(number, 5)
    system_failure_threshold = optional(number, 3)
    ceiling_minutes          = optional(number, 30)
    dashboard                = optional(bool, true)
    metrics_collector_image  = optional(string, "")
    metrics_retention_days   = optional(number, 14)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.monitoring.error_threshold >= 1, var.monitoring.system_failure_threshold >= 1,
      var.monitoring.ceiling_minutes >= 5, var.monitoring.ceiling_minutes <= 1440,
      floor(var.monitoring.ceiling_minutes / 5) * 5 == var.monitoring.ceiling_minutes,
      var.monitoring.metrics_collector_image == "" ? true : can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})$", var.monitoring.metrics_collector_image)),
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.monitoring.metrics_retention_days),
    ])
    error_message = "monitoring: thresholds 1 or more; ceiling_minutes a multiple of 5 from 5 to 1440; metrics_collector_image a registry image with a tag or digest; metrics_retention_days a CloudWatch Logs retention up to 365."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "Topic for the fleet and manager alarms and event rules (failed launches, managers that cannot start). Passed to modules/asg-group and modules/ecs. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_arn == "" ? true : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]+$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be empty or an SNS topic ARN."
  }
}

variable "log_retention_days" {
  description = "Days to keep the manager logs ($0.0315 per GB-month in eu-west-2). 0 keeps them forever."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be 0 or a retention period CloudWatch Logs accepts."
  }
}
