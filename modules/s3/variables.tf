variable "create" {
  description = "Create the bucket and everything around it. false plans nothing and leaves every output null."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = <<-EOT
    The bucket name, or with name_suffix = "account-region" (the default) the
    part before the suffix the module adds: "<name>-<account>-<region>".
    Lowercase letters, digits and hyphens. Changing it replaces the bucket.
  EOT
  type        = string
  nullable    = false

  validation {
    # Periods break virtual-hosted HTTPS and Transfer Acceleration; the affixes are reserved by S3.
    # https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html
    condition = alltrue([
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name)),
      !strcontains(var.name, "--"),
      !anytrue([for p in ["xn--", "sthree-", "amzn-s3-demo-"] : startswith(var.name, p)]),
      !anytrue([for s in ["-s3alias", "--ol-s3", "--x-s3", "--table-s3", "-an"] : endswith(var.name, s)]),
    ])
    error_message = "name must be 3-63 lowercase letters, digits and single hyphens, start and end with a letter or digit, and avoid AWS's reserved prefixes (xn--, sthree-, amzn-s3-demo-) and suffixes (-s3alias, --ol-s3, --x-s3, --table-s3, -an). Dots are not offered."
  }
}

variable "name_suffix" {
  description = <<-EOT
    account-region (default): append "-<account>-<region>", so the same name
    is unique per account and region and readable in logs and bills. none:
    use name as given. Bucket names are global: either way another account
    could create the name first, or reuse it after a delete. (S3's account
    regional namespace, which prevents that, needs provider v6; see README.)
    Changing it replaces the bucket.
  EOT
  type        = string
  default     = "account-region"
  nullable    = false

  validation {
    condition     = contains(["account-region", "none"], var.name_suffix)
    error_message = "name_suffix must be account-region or none."
  }
}

variable "tags" {
  description = "Tags for every resource the module creates. The module adds ManagedBy, Module and Bucket last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "force_destroy" {
  description = "Let terraform destroy delete the bucket with every object and version in it. Off: a destroy fails on a non-empty bucket, which is the point."
  type        = bool
  default     = false
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Names of advisory checks whose warning is intended here (README, \"Advisory checks\"). An acknowledged check stays silent and is listed in output.governance."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for c in var.acknowledged_checks : contains([
      "versioning_is_on", "old_versions_expire", "access_is_logged", "data_uses_a_customer_key",
      "the_bucket_survives_a_destroy", "acls_are_disabled", "replication_is_monitored",
    ], c)])
    error_message = "acknowledged_checks names a check that does not exist. README \"Advisory checks\" lists them."
  }
}

variable "versioning" {
  description = "Keep every version of every object. On by default; off suspends it (S3 never fully disables versioning once on). Replication and Object Lock need it."
  type        = bool
  default     = true
  nullable    = false
}

variable "kms_key_arn" {
  description = "Customer managed key for default encryption (SSE-KMS, with an S3 Bucket Key). Empty: SSE-S3. output.kms_key_policy_requirements says what the key policy must allow."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (an alias resolves in the caller's account, not the bucket's)."
  }
}

variable "encryption" {
  description = <<-EOT
    Encryption details.

      dsse                  dual-layer SSE-KMS (aws:kms:dsse) instead of SSE-KMS.
                            Needs kms_key_arn; S3 Bucket Keys do not apply,
                            so every request calls KMS (billed).
      bucket_key            S3 Bucket Key for SSE-KMS: far fewer KMS requests.
      enforce_kms_key       deny PutObject naming any other algorithm or KMS
                            key, so a caller cannot write under a key you do
                            not control.

    SSE-C (customer-provided keys) stays as S3 sets it: blocked on new
    buckets since April 2026. Managing that setting needs provider v6.
  EOT
  type = object({
    dsse            = optional(bool, false)
    bucket_key      = optional(bool, true)
    enforce_kms_key = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "object_lock" {
  description = <<-EOT
    Object Lock (WORM): versions cannot be deleted or overwritten until their
    retention ends. Once on it cannot be turned off, and versioning cannot be
    suspended. The module turns it on with the configuration resource, so
    enabling it on an existing bucket updates it in place.

      mode   GOVERNANCE (users with s3:BypassGovernanceRetention may remove)
             or COMPLIANCE (nobody, not even root, until it expires).
      days / years  default retention for new versions; 0/0 for none (each
             object then sets its own).
  EOT
  type = object({
    enabled = optional(bool, false)
    mode    = optional(string, "GOVERNANCE")
    days    = optional(number, 0)
    years   = optional(number, 0)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock.mode),
      var.object_lock.days >= 0 && floor(var.object_lock.days) == var.object_lock.days,
      var.object_lock.years >= 0 && floor(var.object_lock.years) == var.object_lock.years,
      var.object_lock.days == 0 || var.object_lock.years == 0,
    ])
    error_message = "object_lock: mode GOVERNANCE or COMPLIANCE; days or years (whole numbers), not both."
  }
}

variable "object_ownership" {
  description = "BucketOwnerEnforced (default): ACLs are disabled and the bucket owns every object - access is policy only. BucketOwnerPreferred or ObjectWriter re-enable ACLs, which only legacy writers need (CloudFront standard logging v1, some partner tools)."
  type        = string
  default     = "BucketOwnerEnforced"
  nullable    = false

  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be BucketOwnerEnforced, BucketOwnerPreferred or ObjectWriter."
  }
}

variable "public_access_block" {
  description = "S3 Block Public Access for this bucket, all four on by default. Turning any off needs allow_public_access = true."
  type = object({
    block_public_acls       = optional(bool, true)
    block_public_policy     = optional(bool, true)
    ignore_public_acls      = optional(bool, true)
    restrict_public_buckets = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "allow_public_access" {
  description = "Acknowledge that public_access_block turns protections off. A public bucket is almost always a mistake: serve public content through CloudFront (cloudfront_distribution_arns) instead."
  type        = bool
  default     = false
  nullable    = false
}

variable "minimum_tls_version" {
  description = "Deny requests over TLS older than this (s3:TlsVersion). Requests without TLS are always denied."
  type        = string
  default     = "1.2"
  nullable    = false

  validation {
    condition     = contains(["1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be 1.2 or 1.3."
  }
}

variable "grants" {
  description = <<-EOT
    Bucket policy grants to principals, keyed by a statement label. Use them
    for other accounts' roles; principals in this account are better granted
    by IAM with output.read_policy_json / write_policy_json.

      principals  IAM role or account ARNs (no "*").
      access      read, write or read_write.
      prefixes    object key prefixes, "" for the whole bucket.

    With kms_key_arn, each grant also appears in kms_key_policy_requirements.
  EOT
  type = map(object({
    principals = list(string)
    access     = string
    prefixes   = optional(list(string), [""])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.grants) : can(regex("^[A-Za-z0-9]{1,64}$", k))])
    error_message = "grants keys are 1-64 letters or digits (they become statement IDs)."
  }

  validation {
    condition = alltrue([for g in values(var.grants) : alltrue([
      contains(["read", "write", "read_write"], g.access),
      length(g.principals) > 0,
      alltrue([for p in g.principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))]),
      alltrue([for p in g.prefixes : !startswith(p, "/") && !strcontains(p, "*")]),
    ])])
    error_message = "grants: access is read, write or read_write; principals are IAM role, user or account root ARNs; prefixes do not start with / or contain *."
  }
}

variable "cloudfront_distribution_arns" {
  description = "CloudFront distributions that read the bucket through Origin Access Control. Each gets s3:GetObject, conditioned on its ARN; with kms_key_arn the key contract includes CloudFront."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", a))])
    error_message = "cloudfront_distribution_arns must be CloudFront distribution ARNs."
  }
}

variable "access_log_sources" {
  description = "Make this a server access log bucket: these source buckets (same account and region, as S3 requires) may deliver their access logs here. S3 refuses a log bucket with SSE-KMS (it would encrypt with a key you cannot read), Object Lock or Requester Pays; the plan refuses them first."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.access_log_sources : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", a))])
    error_message = "access_log_sources must be S3 bucket ARNs."
  }
}

variable "vpc_endpoint_ids" {
  description = "Deny object reads and writes that do not arrive through these S3 VPC endpoints. Bucket configuration calls (Terraform's own) are not restricted, so the module cannot lock its deployer out; AWS services acting for this account (replication, logging, CloudFront) are exempt, and so are requests a service makes with the caller's own credentials (Athena, Glue). Empty: no restriction."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for e in var.vpc_endpoint_ids : can(regex("^vpce-[0-9a-f]{8,17}$", e))])
    error_message = "vpc_endpoint_ids must be VPC endpoint IDs (vpce-...)."
  }
}

variable "organization_id" {
  description = "Deny object reads and writes by principals outside this AWS Organization (aws:PrincipalOrgID). AWS services are exempt, and so is this account's root. Empty: no restriction."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.organization_id == "" ? true : can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must be empty or an organization ID (o-...)."
  }
}

variable "policy_statements" {
  description = "Further bucket policy statements, merged after the module's. Each needs a sid; resources may use the placeholders BUCKET_ARN and OBJECTS_ARN (the bucket and \"<bucket>/*\")."
  type = list(object({
    sid        = string
    effect     = optional(string, "Allow")
    principals = optional(map(list(string)), {})
    actions    = list(string)
    resources  = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([for s in var.policy_statements : alltrue([
      can(regex("^[A-Za-z0-9]{1,100}$", s.sid)),
      contains(["Allow", "Deny"], s.effect),
      length(s.actions) > 0 && length(s.resources) > 0,
      alltrue([for k in keys(s.principals) : contains(["AWS", "Service", "Federated", "CanonicalUser"], k)]),
      length(flatten(values(s.principals))) > 0,
    ])])
    error_message = "policy_statements: sid alphanumeric, effect Allow or Deny, actions and resources not empty, at least one principal, principal types AWS, Service, Federated or CanonicalUser."
  }

  validation {
    condition = alltrue([for s in var.policy_statements : s.effect == "Deny" ? true : !anytrue([
      for p in flatten(values(s.principals)) : p == "*"
    ])])
    error_message = "policy_statements allows principal \"*\": a public bucket. Name the principals, or use cloudfront_distribution_arns."
  }
}

variable "default_lifecycle" {
  description = <<-EOT
    The whole-bucket rule the module adds, bounding what grows unseen. 0 turns
    an item off.

      noncurrent_version_expiration_days  delete old versions this long after
                         they stop being current. With versioning on, every
                         overwrite and delete keeps a billed copy forever
                         without it. Default 90.
      newer_noncurrent_versions  keep this many old versions regardless.
      abort_incomplete_multipart_days  delete the parts of uploads that
                         never finished (billed, and invisible in listings).
      expired_object_delete_marker  remove delete markers with no versions
                         left behind them.
  EOT
  type = object({
    noncurrent_version_expiration_days = optional(number, 90)
    newer_noncurrent_versions          = optional(number, 0)
    abort_incomplete_multipart_days    = optional(number, 7)
    expired_object_delete_marker       = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.default_lifecycle.noncurrent_version_expiration_days >= 0,
      var.default_lifecycle.newer_noncurrent_versions >= 0 && var.default_lifecycle.newer_noncurrent_versions <= 100,
      var.default_lifecycle.abort_incomplete_multipart_days >= 0,
    ])
    error_message = "default_lifecycle: days from 0, newer_noncurrent_versions 0-100."
  }
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules, keyed by rule ID. A rule applies to every object that
    matches all of its filters (prefix, tags, size); none for the whole bucket.

      transitions             [{ days, storage_class }]: STANDARD_IA,
                              ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR,
                              GLACIER, DEEP_ARCHIVE. Moving out of a class
                              before its minimum storage duration (90 days
                              GLACIER_IR and GLACIER, 180 DEEP_ARCHIVE) is
                              billed as if it stayed.
      expiration_days         delete current versions after this long.
      noncurrent_transitions  [{ days, storage_class, newer_versions }].
      noncurrent_expiration_days, noncurrent_newer_versions.
  EOT
  type = map(object({
    enabled                    = optional(bool, true)
    prefix                     = optional(string, "")
    tags                       = optional(map(string), {})
    object_size_greater_than   = optional(number, 0)
    object_size_less_than      = optional(number, 0)
    transitions                = optional(list(object({ days = number, storage_class = string })), [])
    expiration_days            = optional(number, 0)
    noncurrent_transitions     = optional(list(object({ days = number, storage_class = string, newer_versions = optional(number, 0) })), [])
    noncurrent_expiration_days = optional(number, 0)
    noncurrent_newer_versions  = optional(number, 0)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.lifecycle_rules) <= 999 && alltrue([for k in keys(var.lifecycle_rules) : can(regex("^[A-Za-z0-9._-]{1,255}$", k)) && k != "module-defaults"])
    error_message = "lifecycle_rules: at most 999 (with the module's rule, S3 allows 1000), keys 1-255 letters, digits, . _ -, and not module-defaults."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.lifecycle_rules) : [
      for t in concat(r.transitions, r.noncurrent_transitions) : contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)
    ]]))
    error_message = "lifecycle_rules: transition storage classes are STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER or DEEP_ARCHIVE."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.lifecycle_rules) : concat(
      # concat() of the two object types yields list(map(string)), so days would compare as strings.
      [for t in r.transitions : t.days >= 0 && floor(t.days) == t.days],
      [for t in r.noncurrent_transitions : t.days >= 0 && floor(t.days) == t.days],
      [for t in r.noncurrent_transitions : t.newer_versions >= 0 && t.newer_versions <= 100],
      [r.noncurrent_newer_versions >= 0 && r.noncurrent_newer_versions <= 100, r.expiration_days >= 0, r.noncurrent_expiration_days >= 0],
      [r.object_size_greater_than >= 0, r.object_size_less_than >= 0],
      [r.object_size_greater_than == 0 || r.object_size_less_than == 0 ? true : r.object_size_greater_than < r.object_size_less_than],
    )]))
    error_message = "lifecycle_rules: whole days from 0; newer versions 0-100 (0 = not set); object_size_greater_than below object_size_less_than when both are set."
  }

  validation {
    condition = alltrue([for r in values(var.lifecycle_rules) : (
      length(r.transitions) + length(r.noncurrent_transitions) > 0 || r.expiration_days > 0 || r.noncurrent_expiration_days > 0
    )])
    error_message = "lifecycle_rules: each rule needs at least one transition or expiration."
  }
}

variable "transition_default_minimum_object_size" {
  description = "Objects smaller than this are not transitioned by lifecycle rules: all_storage_classes_128K (S3's default; small objects cost more in colder classes than they save) or varies_by_storage_class."
  type        = string
  default     = "all_storage_classes_128K"
  nullable    = false

  validation {
    condition     = contains(["all_storage_classes_128K", "varies_by_storage_class"], var.transition_default_minimum_object_size)
    error_message = "transition_default_minimum_object_size must be all_storage_classes_128K or varies_by_storage_class."
  }
}

variable "intelligent_tiering" {
  description = "S3 Intelligent-Tiering archive configurations, keyed by name: objects in INTELLIGENT_TIERING not accessed for archive_days (90-730) move to Archive Access, for deep_archive_days (180-730) to Deep Archive Access. 0 skips a tier. Reading an archived object needs a restore."
  type = map(object({
    enabled           = optional(bool, true)
    prefix            = optional(string, "")
    tags              = optional(map(string), {})
    archive_days      = optional(number, 0)
    deep_archive_days = optional(number, 0)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for t in values(var.intelligent_tiering) : alltrue([
      t.archive_days == 0 ? true : (t.archive_days >= 90 && t.archive_days <= 730),
      t.deep_archive_days == 0 ? true : (t.deep_archive_days >= 180 && t.deep_archive_days <= 730),
      t.archive_days + t.deep_archive_days > 0,
      t.archive_days == 0 || t.deep_archive_days == 0 ? true : t.deep_archive_days > t.archive_days,
    ])])
    error_message = "intelligent_tiering: archive_days 90-730, deep_archive_days 180-730 and above archive_days, at least one set."
  }
}

variable "access_logging" {
  description = "Server access logs of this bucket, to target_bucket (same account and region; not this bucket). target_prefix defaults to \"<bucket>/\", one folder per source bucket. Partitioned keys by event_time or delivery_time make the logs queryable by date. Setting the object turns logging on; enabled = false turns it off (the default)."
  type = object({
    enabled               = optional(bool, true)
    target_bucket         = optional(string, "")
    target_prefix         = optional(string, "")
    partition_date_source = optional(string, "EventTime")
  })
  default  = { enabled = false }
  nullable = false

  validation {
    condition     = var.access_logging.enabled ? var.access_logging.target_bucket != "" : true
    error_message = "access_logging needs target_bucket; set enabled = false to turn logging off."
  }

  validation {
    condition     = contains(["EventTime", "DeliveryTime"], var.access_logging.partition_date_source)
    error_message = "access_logging.partition_date_source must be EventTime or DeliveryTime."
  }

  validation {
    condition     = var.access_logging.target_bucket == "" ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logging.target_bucket))
    error_message = "access_logging.target_bucket must be a bucket name."
  }
}

variable "replication" {
  description = <<-EOT
    Replication rules, keyed by rule ID, to destination buckets in any region
    or account. Needs versioning here and on each destination. The module
    creates the replication role; to bring one, set create_role = false and
    role_arn. Each destination owner needs
    output.replication_destination_requirements.

      destination_bucket_arn    the destination. In another account, give
                                that bucket Object Ownership "bucket owner
                                enforced": it then owns the replicas, which
                                is what AWS recommends over owner override.
      storage_class             at the destination; empty keeps the source's.
      prefix / tags             filter; none for the whole bucket.
      priority                  higher wins where rules overlap.
      replica_kms_key_arn       destination key, in the destination's
                                region; required to replicate SSE-KMS
                                objects (S3 skips them otherwise). Across
                                accounts it must be a customer managed key.
      replication_time_control  S3 RTC: 99.99% replicated in 15 minutes, with
                                metrics (billed per GB).
      delete_markers            replicate delete markers.
  EOT
  type = object({
    create_role = optional(bool, true)
    role_arn    = optional(string, "")
    rules = optional(map(object({
      destination_bucket_arn   = string
      storage_class            = optional(string, "")
      prefix                   = optional(string, "")
      tags                     = optional(map(string), {})
      priority                 = optional(number, 0)
      replica_kms_key_arn      = optional(string, "")
      replication_time_control = optional(bool, false)
      delete_markers           = optional(bool, true)
      enabled                  = optional(bool, true)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.replication.role_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.replication.role_arn))
    error_message = "replication.role_arn must be empty or an IAM role ARN."
  }

  validation {
    condition     = var.replication.create_role ? var.replication.role_arn == "" : var.replication.role_arn != ""
    error_message = "replication.role_arn goes with create_role = false; with create_role = true the module creates the role and role_arn must be empty."
  }

  validation {
    condition = alltrue([for k, r in var.replication.rules : alltrue([
      can(regex("^[A-Za-z0-9._-]{1,255}$", k)),
      can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", r.destination_bucket_arn)),
      contains(["", "STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE", "REDUCED_REDUNDANCY"], r.storage_class),
      r.replica_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", r.replica_kms_key_arn)),
      r.priority >= 0,
    ])])
    error_message = "replication.rules: keys 1-255 of letters, digits, . _ -; destination_bucket_arn an S3 bucket ARN; a valid storage class; replica_kms_key_arn a KMS key ARN; priority from 0."
  }

  validation {
    condition     = length(distinct([for r in values(var.replication.rules) : r.priority])) == length(var.replication.rules)
    error_message = "replication.rules need distinct priorities: S3 rejects two rules with the same one."
  }
}

variable "notifications" {
  description = <<-EOT
    Event notifications. eventbridge sends every event to the account's
    default bus (filter with rules there). topics, queues and lambda_functions
    are keyed by label, each { arn, events, prefix, suffix }; their owners
    need output.notification_destination_requirements before the apply, or
    S3 refuses the configuration. Standard queues and topics only.
  EOT
  type = object({
    eventbridge = optional(bool, false)
    topics = optional(map(object({
      arn    = string
      events = list(string)
      prefix = optional(string, "")
      suffix = optional(string, "")
    })), {})
    queues = optional(map(object({
      arn    = string
      events = list(string)
      prefix = optional(string, "")
      suffix = optional(string, "")
    })), {})
    lambda_functions = optional(map(object({
      arn    = string
      events = list(string)
      prefix = optional(string, "")
      suffix = optional(string, "")
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue(concat(
      [for t in values(var.notifications.topics) : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", t.arn))],
      [for q in values(var.notifications.queues) : can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", q.arn))],
      [for l in values(var.notifications.lambda_functions) : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+(:[A-Za-z0-9_$-]+)?$", l.arn))],
    ))
    error_message = "notifications: topics take standard SNS topic ARNs, queues standard SQS queue ARNs (FIFO is not supported), lambda_functions function ARNs."
  }

  validation {
    condition = alltrue(flatten([for d in concat(values(var.notifications.topics), values(var.notifications.queues), values(var.notifications.lambda_functions)) : [
      length(d.events) > 0, [for e in d.events : can(regex("^s3:[A-Za-z]+(:[A-Za-z*]+)?$", e))]
    ]]))
    error_message = "notifications: each destination needs events such as s3:ObjectCreated:* or s3:ObjectRemoved:Delete."
  }
}

variable "notification_dependencies" {
  description = "IDs of the topic, queue and function policies that grant S3 output.notification_destination_requirements, when they live in the same root. S3 tests each destination when the configuration is written, so the notification waits for these. A module-wide depends_on would form a cycle with that output."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "inventory" {
  description = "S3 Inventory reports, keyed by name, to destination_bucket_arn in the same region (any account; that bucket needs output.inventory_destination_requirements). frequency Daily or Weekly; format CSV, ORC or Parquet; include_versions All or Current. destination_kms_key encrypts the reports with a customer managed key (the AWS managed aws/s3 key is not supported); empty: SSE-S3. The first report can take 48 hours."
  type = map(object({
    destination_bucket_arn = string
    destination_account_id = optional(string, "")
    destination_prefix     = optional(string, "")
    destination_kms_key    = optional(string, "")
    format                 = optional(string, "Parquet")
    frequency              = optional(string, "Weekly")
    include_versions       = optional(string, "Current")
    prefix                 = optional(string, "")
    optional_fields        = optional(list(string), ["Size", "LastModifiedDate", "StorageClass", "EncryptionStatus", "ReplicationStatus", "ObjectLockMode", "ObjectLockRetainUntilDate"])
    enabled                = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for k, i in var.inventory : alltrue([
      can(regex("^[A-Za-z0-9._-]{1,64}$", k)),
      can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", i.destination_bucket_arn)),
      contains(["CSV", "ORC", "Parquet"], i.format),
      contains(["Daily", "Weekly"], i.frequency),
      contains(["All", "Current"], i.include_versions),
      i.destination_kms_key == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", i.destination_kms_key)),
    ])])
    error_message = "inventory: keys 1-64 of letters, digits, . _ -; destination_bucket_arn an S3 bucket ARN; format CSV, ORC or Parquet; frequency Daily or Weekly; include_versions All or Current; destination_kms_key a KMS key ARN."
  }
}

variable "request_metrics" {
  description = "CloudWatch request metrics, keyed by name ($0.30 per metric-month), each for the whole bucket or a prefix/tags filter. Needed for 4xx/5xx and latency per bucket."
  type = map(object({
    prefix = optional(string, "")
    tags   = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.request_metrics) : can(regex("^[A-Za-z0-9._-]{1,64}$", k))])
    error_message = "request_metrics keys are 1-64 letters, digits, . _ -."
  }
}

variable "cors_rules" {
  description = "CORS rules (at most 100), for browsers reading the bucket directly."
  type = list(object({
    id              = optional(string, "")
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), [])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 0)
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(var.cors_rules) <= 100 && alltrue([for r in var.cors_rules : alltrue([for m in r.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])])
    error_message = "cors_rules: at most 100, methods GET, PUT, POST, DELETE or HEAD."
  }
}

variable "transfer_acceleration" {
  description = "S3 Transfer Acceleration (billed per GB transferred, on top of transfer)."
  type        = bool
  default     = false
  nullable    = false
}

variable "requester_pays" {
  description = "The requester, not the bucket owner, pays for requests and data transfer. Every request must then say so (x-amz-request-payer)."
  type        = bool
  default     = false
  nullable    = false
}
