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
  description = "Prefix of what the module names besides repositories: the repository creation role (<name>-ecr-templates) and the event rules (<name>-ecr-*). Repositories are named by their keys in repositories."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on every resource the module creates. Repositories and the repositories ECR creates from templates also get them. The module adds ManagedBy and Module last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "required_tag_keys" {
  description = "Tag keys that must be present and non-empty in tags, such as CostCenter. Without them, image storage is unattributable in Cost Explorer."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\"). An acknowledged check stops warning in plans and HCP Terraform health assessments, and is listed in output.governance."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for c in var.acknowledged_checks : contains([
        "tags_are_immutable",
        "repositories_use_a_customer_key",
        "storage_is_bounded",
        "images_are_scanned",
        "ecr_created_repositories_follow_a_template",
        "cached_images_can_refresh",
        "repositories_are_not_open_to_every_account",
      ], c)
    ])
    error_message = "acknowledged_checks names a check that does not exist. The check names are the check blocks in checks.tf, listed in the README under \"Advisory checks\"."
  }
}

# ---------------------------------------------------------------------------
# Defaults for every repository
# ---------------------------------------------------------------------------

variable "image_tag_mutability" {
  description = "IMMUTABLE (a pushed tag can never point at another image) or MUTABLE, for repositories that do not set their own. A repository's tag_mutability_exclusions turn it into IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION."
  type        = string
  default     = "IMMUTABLE"
  nullable    = false

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key for repositories that do not set their own. Empty: AES-256 with keys Amazon S3 manages. The encryption of a repository is fixed when it is created: changing the key replaces the repository and deletes its images. output.kms_key_policy_requirements says what the key policy must allow."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (not an alias)."
  }
}

variable "scan_on_push" {
  description = "Basic scanning on push for repositories that do not set their own. A registry scanning configuration (registry.scanning) overrides it for every repository it matches."
  type        = bool
  default     = true
  nullable    = false
}

variable "lifecycle_policy" {
  description = <<-EOT
    The lifecycle policy of repositories that do not set their own. Storage is $0.10 per GB-month in eu-west-2 and
    grows with every push, so the default bounds it. A preset:
      untagged_expire_days   delete untagged images this many days after push (0: keep)
      keep_last              keep the newest N images, delete the rest (0: no limit)
      archive_unpulled_days  move images not pulled for N days to archive storage, $0.04 per GB-month, billed for
                             at least 90 days, $0.03 per GB to restore (0: no archiving). Instead of keep_last
      archive_expire_days    delete archived images N days after archiving (0: keep; at least 90)
    or your own rules, which replace the preset. enabled = false sends no policy.
  EOT
  type = object({
    enabled               = optional(bool, true)
    untagged_expire_days  = optional(number, 14)
    keep_last             = optional(number, 100)
    archive_unpulled_days = optional(number, 0)
    archive_expire_days   = optional(number, 0)
    rules = optional(list(object({
      priority      = number
      description   = optional(string, "")
      tag_status    = string
      tag_patterns  = optional(list(string), [])
      tag_prefixes  = optional(list(string), [])
      storage_class = optional(string, "standard")
      count_type    = string
      count         = number
      action        = optional(string, "expire")
    })), [])
  })
  default  = {}
  nullable = false
}

# ---------------------------------------------------------------------------
# Repositories
# ---------------------------------------------------------------------------

variable "repositories" {
  description = <<-EOT
    Repositories, keyed by their full name (orders/api). Each takes, all optional:
      image_tag_mutability       IMMUTABLE or MUTABLE; empty: the module's image_tag_mutability
      tag_mutability_exclusions  up to 5 wildcard patterns that are the exception: mutable tags in an immutable
                                 repository (latest, dev-*), or immutable ones in a mutable repository (v*)
      kms_key_arn                empty: the module's kms_key_arn. Fixed at creation
      scan_on_push               unset: the module's scan_on_push
      force_delete               destroy the repository even with images in it (default false)
      lifecycle_policy           replaces the module's lifecycle_policy for this repository
      access                     the repository policy: who outside IAM may pull and push
        pull_principals, push_principals   IAM role, user or account root ARNs
        pull_organization_ids              every principal in these AWS Organizations may pull
        lambda_accounts                    Lambda functions in these accounts may use the images
        statements                         further policy statements, as JSON
      tags                       added to the repository's tags
  EOT
  type = map(object({
    image_tag_mutability      = optional(string, "")
    tag_mutability_exclusions = optional(list(string), [])
    kms_key_arn               = optional(string, "")
    scan_on_push              = optional(bool)
    force_delete              = optional(bool, false)
    lifecycle_policy = optional(object({
      enabled               = optional(bool, true)
      untagged_expire_days  = optional(number, 14)
      keep_last             = optional(number, 100)
      archive_unpulled_days = optional(number, 0)
      archive_expire_days   = optional(number, 0)
      rules = optional(list(object({
        priority      = number
        description   = optional(string, "")
        tag_status    = string
        tag_patterns  = optional(list(string), [])
        tag_prefixes  = optional(list(string), [])
        storage_class = optional(string, "standard")
        count_type    = string
        count         = number
        action        = optional(string, "expire")
      })), [])
    }))
    access = optional(object({
      pull_principals       = optional(list(string), [])
      push_principals       = optional(list(string), [])
      pull_organization_ids = optional(list(string), [])
      lambda_accounts       = optional(list(string), [])
      statements            = optional(list(string), [])
    }), {})
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    # https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_CreateRepository.html
    condition     = alltrue([for k, r in var.repositories : can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", k)) ? (length(k) >= 2 ? length(k) <= 256 : false) : false])
    error_message = "repositories keys are repository names: 2-256 characters of lowercase letters and digits, separated by single . _ - within a part and / between parts (orders/api)."
  }

  validation {
    condition = alltrue([for k, r in var.repositories : alltrue([
      contains(["", "IMMUTABLE", "MUTABLE"], r.image_tag_mutability),
      length(r.tag_mutability_exclusions) <= 5,
      alltrue([for f in r.tag_mutability_exclusions : can(regex("^[0-9a-zA-Z._*-]{1,128}$", f)) ? length(regexall("\\*", f)) <= 2 : false]),
    ])])
    error_message = "repositories[*]: image_tag_mutability is empty, IMMUTABLE or MUTABLE; tag_mutability_exclusions holds at most 5 patterns of 1-128 letters, digits and . _ * -, with at most two * each."
  }

  validation {
    condition     = alltrue([for k, r in var.repositories : r.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", r.kms_key_arn))])
    error_message = "repositories[*].kms_key_arn must be empty or a KMS key ARN (not an alias)."
  }

  validation {
    condition = alltrue([for k, r in var.repositories : alltrue([
      alltrue([for p in concat(r.access.pull_principals, r.access.push_principals) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))]),
      alltrue([for o in r.access.pull_organization_ids : can(regex("^o-[a-z0-9]{10,32}$", o))]),
      alltrue([for a in r.access.lambda_accounts : can(regex("^[0-9]{12}$", a))]),
      alltrue([for s in r.access.statements : can(jsondecode(s).Effect) ? can(jsondecode(s).Action) : false]),
    ])])
    error_message = "repositories[*].access: principals are IAM role, user or account root ARNs (a wildcard is not accepted: use pull_organization_ids); organization IDs are o-...; lambda_accounts are 12-digit account IDs; statements are JSON policy statements with Effect and Action."
  }
}

# ---------------------------------------------------------------------------
# The registry: one per account and Region
# ---------------------------------------------------------------------------

variable "registry" {
  description = <<-EOT
    The registry's own settings, of which an account has one set per Region: manage them from exactly one
    workspace (enabled = true), or two workspaces overwrite each other. All optional:
      scanning                     type ENHANCED (Amazon Inspector, billed per image) or BASIC, and the rules:
                                   frequency (CONTINUOUS_SCAN, SCAN_ON_PUSH, MANUAL) for repository filters
      replication                  rules of destinations ({ region, account_id }) and repository prefixes
      replication_source_accounts  accounts allowed to replicate into this registry
      pull_through_cache           keyed by the local repository prefix: upstream (docker-hub, ecr-public, quay,
                                   k8s, github-container-registry, gitlab-container-registry,
                                   azure-container-registry, chainguard, ecr), url (azure and ecr only),
                                   credential_secret_arn (ecr-pullthroughcache/...), upstream_prefix, role_arn (ecr)
      pull_through_cache_principals  IAM principals allowed to create cache repositories and import images
      creation_templates           keyed by prefix (or ROOT): the settings of repositories ECR creates for pull
                                   through cache, replication or create on push
      policy_statements            further registry policy statements, as JSON
      pull_time_update_exclusions  IAM roles whose pulls do not update an image's last pull time (scanners)
      account_settings             basic_scan_type_version (AWS_NATIVE), registry_policy_scope (V2),
                                   blob_mounting (ENABLED, DISABLED); empty: not managed
  EOT
  type = object({
    enabled = optional(bool, false)
    scanning = optional(object({
      type = optional(string, "ENHANCED")
      rules = optional(list(object({
        frequency = string
        filters   = list(string)
      })), [{ frequency = "CONTINUOUS_SCAN", filters = ["*"] }])
    }))
    replication = optional(list(object({
      destinations = list(object({
        region     = string
        account_id = optional(string, "")
      }))
      repository_prefixes = optional(list(string), [])
    })), [])
    replication_source_accounts = optional(list(string), [])
    pull_through_cache = optional(map(object({
      upstream              = string
      url                   = optional(string, "")
      credential_secret_arn = optional(string, "")
      upstream_prefix       = optional(string, "")
      role_arn              = optional(string, "")
    })), {})
    pull_through_cache_principals = optional(list(string), [])
    creation_templates = optional(map(object({
      applied_for               = list(string)
      description               = optional(string, "")
      image_tag_mutability      = optional(string, "IMMUTABLE")
      tag_mutability_exclusions = optional(list(string), [])
      kms_key_arn               = optional(string, "")
      repository_policy         = optional(string, "")
      tags                      = optional(map(string), {})
      lifecycle_policy = optional(object({
        enabled               = optional(bool, true)
        untagged_expire_days  = optional(number, 14)
        keep_last             = optional(number, 100)
        archive_unpulled_days = optional(number, 0)
        archive_expire_days   = optional(number, 0)
        rules = optional(list(object({
          priority      = number
          description   = optional(string, "")
          tag_status    = string
          tag_patterns  = optional(list(string), [])
          tag_prefixes  = optional(list(string), [])
          storage_class = optional(string, "standard")
          count_type    = string
          count         = number
          action        = optional(string, "expire")
        })), [])
      }), {})
    })), {})
    policy_statements           = optional(list(string), [])
    pull_time_update_exclusions = optional(list(string), [])
    account_settings = optional(object({
      basic_scan_type_version = optional(string, "")
      registry_policy_scope   = optional(string, "")
      blob_mounting           = optional(string, "")
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = var.registry.scanning == null ? true : alltrue([
      contains(["ENHANCED", "BASIC"], var.registry.scanning.type),
      length(var.registry.scanning.rules) <= 2,
      alltrue([for r in var.registry.scanning.rules : contains(var.registry.scanning.type == "BASIC" ? ["SCAN_ON_PUSH", "MANUAL"] : ["SCAN_ON_PUSH", "CONTINUOUS_SCAN", "MANUAL"], r.frequency)]),
      alltrue([for r in var.registry.scanning.rules : length(r.filters) > 0 ? length(r.filters) <= 100 : false]),
      alltrue([for r in var.registry.scanning.rules : alltrue([for f in r.filters : can(regex("^[0-9a-z*](?:[0-9a-z_./*-]{0,255})$", f))])]),
    ])
    error_message = "registry.scanning: type is ENHANCED or BASIC; at most two rules, each with a frequency (SCAN_ON_PUSH or MANUAL for BASIC; also CONTINUOUS_SCAN for ENHANCED) and 1-100 repository filters of lowercase letters, digits, _ . / - and * wildcards."
  }

  validation {
    # https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html
    condition = alltrue([
      length(var.registry.replication) <= 25,
      length(distinct(flatten([for r in var.registry.replication : [for d in r.destinations : "${d.region}/${d.account_id}"]]))) <= 25,
      alltrue([for r in var.registry.replication : length(r.destinations) > 0 ? length(r.repository_prefixes) <= 100 : false]),
      alltrue([for r in var.registry.replication : alltrue([for d in r.destinations : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", d.region)) ? (d.account_id == "" ? true : can(regex("^[0-9]{12}$", d.account_id))) : false])]),
      alltrue([for r in var.registry.replication : alltrue([for p in r.repository_prefixes : can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/?)+$", p))])]),
      alltrue([for a in var.registry.replication_source_accounts : can(regex("^[0-9]{12}$", a))]),
    ])
    error_message = "registry.replication: at most 25 rules and 25 distinct destinations; each rule has at least one destination (a Region, and a 12-digit account_id or empty for this account) and at most 100 repository prefixes. replication_source_accounts are 12-digit account IDs."
  }

  validation {
    # https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_CreatePullThroughCacheRule.html
    condition = alltrue([for prefix, c in var.registry.pull_through_cache : alltrue([
      can(regex("^[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*(/[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*)*$", prefix)) ? (length(prefix) >= 2 ? length(prefix) <= 30 : false) : false,
      contains(["docker-hub", "ecr-public", "quay", "k8s", "github-container-registry", "gitlab-container-registry", "azure-container-registry", "chainguard", "ecr"], c.upstream),
      contains(["docker-hub", "github-container-registry", "gitlab-container-registry", "azure-container-registry", "chainguard"], c.upstream) ? can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:ecr-pullthroughcache/", c.credential_secret_arn)) : c.credential_secret_arn == "",
      c.upstream == "azure-container-registry" ? can(regex("^[a-z0-9]+\\.azurecr\\.io$", c.url)) : (c.upstream == "ecr" ? can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com$", c.url)) : c.url == ""),
      c.role_arn == "" ? true : (c.upstream == "ecr" ? can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", c.role_arn)) : false),
      c.upstream_prefix == "" ? true : (c.upstream == "ecr" ? can(regex("^[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*(/[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*)*$", c.upstream_prefix)) : false),
    ])])
    error_message = "registry.pull_through_cache: keys are 2-30 character repository prefixes; upstream is one of docker-hub, ecr-public, quay, k8s, github-container-registry, gitlab-container-registry, azure-container-registry, chainguard, ecr. Docker Hub, GitHub, GitLab, Azure and Chainguard need credential_secret_arn, a Secrets Manager secret named ecr-pullthroughcache/...; the others take none. url is <name>.azurecr.io for Azure, <account>.dkr.ecr.<region>.amazonaws.com for ecr, and empty otherwise. role_arn and upstream_prefix are only for ecr."
  }

  validation {
    # https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_CreateRepositoryCreationTemplate.html
    condition = alltrue([for prefix, t in var.registry.creation_templates : alltrue([
      prefix == "ROOT" ? true : (can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", prefix)) ? (length(prefix) >= 2 ? length(prefix) <= 256 : false) : false),
      length(t.applied_for) > 0,
      alltrue([for a in t.applied_for : contains(["PULL_THROUGH_CACHE", "REPLICATION", "CREATE_ON_PUSH"], a)]),
      length(t.description) <= 256,
      contains(["IMMUTABLE", "MUTABLE"], t.image_tag_mutability),
      length(t.tag_mutability_exclusions) <= 5,
      alltrue([for f in t.tag_mutability_exclusions : can(regex("^[0-9a-zA-Z._*-]{1,128}$", f)) ? length(regexall("\\*", f)) <= 2 : false]),
      t.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", t.kms_key_arn)),
      t.repository_policy == "" ? true : can(jsondecode(t.repository_policy).Statement),
    ])])
    error_message = "registry.creation_templates: keys are a repository prefix (orders, or team/orders) or ROOT; applied_for lists PULL_THROUGH_CACHE, REPLICATION and/or CREATE_ON_PUSH; description at most 256 characters; image_tag_mutability IMMUTABLE or MUTABLE with at most 5 exclusion patterns; kms_key_arn empty or a key ARN; repository_policy empty or a policy document."
  }

  validation {
    condition = alltrue([
      alltrue([for p in var.registry.pull_through_cache_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))]),
      alltrue([for s in var.registry.policy_statements : can(jsondecode(s).Effect) ? can(jsondecode(s).Action) : false]),
      # https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_RegisterPullTimeUpdateExclusion.html
      alltrue([for p in var.registry.pull_time_update_exclusions : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/[\\w+=,.@-]+(/[\\w+=,.@-]+)*$", p)) ? length(p) <= 200 : false]),
      contains(["", "AWS_NATIVE"], var.registry.account_settings.basic_scan_type_version),
      contains(["", "V2"], var.registry.account_settings.registry_policy_scope),
      contains(["", "ENABLED", "DISABLED"], var.registry.account_settings.blob_mounting),
    ])
    error_message = "registry: pull_through_cache_principals are IAM ARNs; policy_statements are JSON statements with Effect and Action; pull_time_update_exclusions are IAM role or user ARNs (at most 200 characters); account_settings: basic_scan_type_version empty or AWS_NATIVE, registry_policy_scope empty or V2, blob_mounting empty, ENABLED or DISABLED."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "SNS topic for EventBridge rules: images whose basic scan finds CRITICAL vulnerabilities, and (with registry.enabled) replications and pull through cache syncs that did not succeed. Empty: no rules. output.notification_requirements is the topic policy they need."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_arn == "" ? true : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be empty or an SNS topic ARN."
  }
}
