###############################################################################
# General
###############################################################################

variable "name" {
  description = "Name prefix applied to created resources (namespace fallback name, log group)"
  type        = string
}

variable "tags" {
  description = "A map of tags applied to every resource created by this module"
  type        = map(string)
  default     = {}
}

###############################################################################
# Cloud Map namespace (the discovery domain)
###############################################################################

variable "create_namespace" {
  description = "Whether to create a Cloud Map namespace. Set to false to reference an existing one via existing_namespace_arn"
  type        = bool
  default     = true
}

variable "namespace_name" {
  description = "Name of the Cloud Map namespace (e.g. \"internal\" or \"prod.example.local\"). Defaults to var.name when null"
  type        = string
  default     = null
}

variable "namespace_type" {
  description = "Type of namespace to create: \"http\" (recommended for Service Connect) or \"dns_private\" (also resolvable via DNS for non-Service-Connect clients)"
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "dns_private"], var.namespace_type)
    error_message = "namespace_type must be either \"http\" or \"dns_private\"."
  }
}

variable "namespace_description" {
  description = "Description for the created namespace"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID for the namespace. Required when namespace_type is dns_private"
  type        = string
  default     = null
}

variable "existing_namespace_arn" {
  description = "ARN of an existing Cloud Map namespace to use. Required when create_namespace is false"
  type        = string
  default     = null
}

###############################################################################
# Shared Service Connect proxy log group
###############################################################################

variable "create_log_group" {
  description = "Whether to create a shared CloudWatch log group for Service Connect Envoy proxy logs"
  type        = bool
  default     = false
}

variable "log_group_name" {
  description = "Name of the Service Connect log group. Defaults to /ecs/service-connect/<name> when null"
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Retention, in days, for the Service Connect log group. Must be a value CloudWatch accepts"
  type        = number
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_in_days
    )
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs supports (e.g. 1, 3, 5, 7, 14, 30, 90, 365, ... or 0 for never expire)."
  }
}

variable "log_kms_key_id" {
  description = "KMS key ARN to encrypt the Service Connect log group"
  type        = string
  default     = null
}

variable "inject_default_log_configuration" {
  description = <<-EOT
    When a log group is created, inject an awslogs log_configuration into every
    generated service_connect_configuration that does not define its own. This
    captures the Service Connect Envoy proxy logs without per-service wiring.
  EOT
  type        = bool
  default     = true
}

###############################################################################
# Services (the discovery rules)
###############################################################################

variable "services" {
  description = <<-EOT
    Map of ECS service name -> Service Connect configuration. Each entry generates
    a complete service_connect_configuration object (exposed in the
    service_connect_configurations output) ready to plug into an ECS service.

    Attributes:
      enabled  - Whether Service Connect is enabled for the service (default true).
      services - List of ports this service exposes for discovery. Each entry:
        port_name             - Name of a port mapping in the task definition (required).
        discovery_name        - Cloud Map discovery name (defaults to the port_name / service).
        ingress_port_override - Port the Envoy proxy listens on for inbound traffic.
        client_aliases        - How clients reach this service. Each: { port, dns_name }.
        timeout               - { idle_timeout_seconds, per_request_timeout_seconds }.
        tls                   - { aws_pca_authority_arn, kms_key, role_arn } for Service Connect TLS.
      log_configuration - Per-service Envoy log_configuration override.

    A service with an empty services list acts as a pure client (it can reach
    other services in the namespace but exposes nothing).
  EOT
  type = map(object({
    enabled = optional(bool, true)
    services = optional(list(object({
      port_name             = string
      discovery_name        = optional(string)
      ingress_port_override = optional(number)
      client_aliases = optional(list(object({
        port     = number
        dns_name = optional(string)
      })), [])
      timeout = optional(object({
        idle_timeout_seconds        = optional(number)
        per_request_timeout_seconds = optional(number)
      }))
      tls = optional(object({
        aws_pca_authority_arn = string
        kms_key               = optional(string)
        role_arn              = optional(string)
      }))
    })), [])
    log_configuration = optional(object({
      log_driver = string
      options    = optional(map(string), {})
      secret_option = optional(list(object({
        name       = string
        value_from = string
      })), [])
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for s in values(var.services) : alltrue([
        for svc in s.services : svc.port_name != null && svc.port_name != ""
      ])
    ])
    error_message = "Every exposed service must set a non-empty port_name."
  }

  validation {
    condition = alltrue([
      for s in values(var.services) : alltrue([
        for svc in s.services : alltrue([
          for ca in svc.client_aliases : ca.port > 0 && ca.port <= 65535
        ])
      ])
    ])
    error_message = "client_aliases port must be between 1 and 65535."
  }

  # Self-consistency: a port_name must be unique within a single service.
  validation {
    condition = alltrue([
      for s in values(var.services) :
      length([for svc in s.services : svc.port_name]) == length(distinct([for svc in s.services : svc.port_name]))
    ])
    error_message = "port_name values must be unique within each service."
  }

  # Self-consistency: discovery names must be unique across the whole namespace.
  validation {
    condition = length(flatten([
      for s in values(var.services) : [for svc in s.services : coalesce(svc.discovery_name, svc.port_name)]
      ])) == length(distinct(flatten([
        for s in values(var.services) : [for svc in s.services : coalesce(svc.discovery_name, svc.port_name)]
    ])))
    error_message = "discovery_name (or its port_name fallback) must be unique across all services in the namespace."
  }

  # Self-consistency: client endpoints (<dns_name>:<port>) must not collide.
  validation {
    condition = length(flatten([
      for s in values(var.services) : [for svc in s.services : [
        for ca in svc.client_aliases : "${coalesce(ca.dns_name, svc.discovery_name, svc.port_name)}:${ca.port}"
      ]]
      ])) == length(distinct(flatten([
        for s in values(var.services) : [for svc in s.services : [
          for ca in svc.client_aliases : "${coalesce(ca.dns_name, svc.discovery_name, svc.port_name)}:${ca.port}"
        ]]
    ])))
    error_message = "Client endpoints (<dns_name>:<port>) must be unique across all services in the namespace."
  }
}

###############################################################################
# Mesh-wide defaults (scalability)
###############################################################################

variable "default_timeout" {
  description = "Default Service Connect timeout applied to exposed services that do not set their own timeout"
  type = object({
    idle_timeout_seconds        = optional(number)
    per_request_timeout_seconds = optional(number)
  })
  default = null
}

variable "enable_tls" {
  description = "Enable Service Connect TLS (mTLS) for every exposed service that does not define its own tls block. Requires tls_ca_arn"
  type        = bool
  default     = false
}

variable "tls_ca_arn" {
  description = "ARN of the AWS Private CA used to issue Service Connect certificates when enable_tls is true"
  type        = string
  default     = null
}

variable "tls_kms_key" {
  description = "KMS key ARN injected into the mesh-wide Service Connect TLS config"
  type        = string
  default     = null
}

variable "tls_role_arn" {
  description = <<-EOT
    ARN of the IAM role ECS assumes to issue Service Connect certificates from
    AWS Private CA. Injected into every TLS-enabled service that does not set its
    own role_arn. Manage the role itself outside this module (it is certificate
    issuance / IAM, not service discovery). Required whenever TLS is enabled.
  EOT
  type        = string
  default     = null
}
