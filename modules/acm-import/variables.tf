# -----------------------------------------------------------------------------
# AWS Certificate Manager (ACM) - Certificate Import Module
# Purpose: Import one or multiple external certificates into ACM
# -----------------------------------------------------------------------------

variable "certificates" {
  description = "Map of certificates to import. Key is a unique identifier for the certificate."
  type = map(object({
    certificate_body_path  = optional(string)
    certificate_body       = optional(string)
    private_key_path       = optional(string)
    private_key            = optional(string)
    certificate_chain_path = optional(string)
    certificate_chain      = optional(string)
    name                   = optional(string)
    tags                   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.certificates : (v.certificate_body != null || v.certificate_body_path != null)])
    error_message = "Each certificate must have either certificate_body or certificate_body_path defined."
  }

  validation {
    condition     = alltrue([for k, v in var.certificates : (v.private_key != null || v.private_key_path != null)])
    error_message = "Each certificate must have either private_key or private_key_path defined."
  }

  validation {
    condition     = alltrue([for k, v in var.certificates : !(v.certificate_body != null && v.certificate_body_path != null)])
    error_message = "Each certificate must have only one of certificate_body or certificate_body_path, not both."
  }

  validation {
    condition     = alltrue([for k, v in var.certificates : !(v.private_key != null && v.private_key_path != null)])
    error_message = "Each certificate must have only one of private_key or private_key_path, not both."
  }

  validation {
    condition     = alltrue([for k, v in var.certificates : !(v.certificate_chain != null && v.certificate_chain_path != null)])
    error_message = "Each certificate must have only one of certificate_chain or certificate_chain_path, not both."
  }
}

variable "tags" {
  description = "Map of tags to assign to all certificates (can be overridden per certificate)"
  type        = map(string)
  default     = {}
}
