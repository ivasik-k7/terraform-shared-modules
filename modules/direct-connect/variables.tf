variable "create_connection" {
  description = "Whether to create a new Direct Connect connection"
  type        = bool
  default     = false
}

variable "existing_connection_id" {
  description = "ID of an existing Direct Connect connection to use"
  type        = string
  default     = null
}

variable "connection_name" {
  description = "Name of the Direct Connect connection"
  type        = string
  default     = ""
}

variable "bandwidth" {
  description = "Bandwidth of the connection (1Gbps, 10Gbps, 100Gbps)"
  type        = string
  default     = "1Gbps"
  validation {
    condition     = can(regex("^(50Mbps|100Mbps|200Mbps|300Mbps|400Mbps|500Mbps|1Gbps|2Gbps|5Gbps|10Gbps|100Gbps)$", var.bandwidth))
    error_message = "Bandwidth must be a valid Direct Connect bandwidth value."
  }
}

variable "location" {
  description = "AWS Direct Connect location code"
  type        = string
  default     = ""
}

variable "provider_name" {
  description = "Name of the service provider (optional for dedicated connections)"
  type        = string
  default     = null
}

variable "request_macsec" {
  description = "Whether to request MACsec capability for the connection"
  type        = bool
  default     = false
}

variable "skip_destroy" {
  description = "Set to true if you do not wish the connection to be deleted at destroy time"
  type        = bool
  default     = false
}

variable "encryption_mode" {
  description = "Encryption mode for the connection (should_encrypt, must_encrypt, or no_encrypt)"
  type        = string
  default     = "no_encrypt"
  validation {
    condition     = can(regex("^(should_encrypt|must_encrypt|no_encrypt)$", var.encryption_mode))
    error_message = "Encryption mode must be should_encrypt, must_encrypt, or no_encrypt."
  }
}

variable "connection_tags" {
  description = "Additional tags for the connection"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_lag" {
  description = "Whether to create a Link Aggregation Group"
  type        = bool
  default     = false
}

variable "use_lag" {
  description = "Whether to use LAG for virtual interfaces (requires create_lag or existing LAG)"
  type        = bool
  default     = false
}

variable "lag_name" {
  description = "Name of the LAG"
  type        = string
  default     = ""
}

variable "lag_bandwidth" {
  description = "Bandwidth of each connection in the LAG"
  type        = string
  default     = "1Gbps"
}

variable "lag_force_destroy" {
  description = "Force destroy the LAG even if it has virtual interfaces"
  type        = bool
  default     = false
}

variable "lag_tags" {
  description = "Additional tags for the LAG"
  type        = map(string)
  default     = {}
}

variable "lag_connection_associations" {
  description = "Map of existing connection IDs to associate with the LAG"
  type        = map(string)
  default     = {}
}

variable "private_virtual_interfaces" {
  description = "Map of private virtual interfaces to create"
  type = map(object({
    name             = string
    vlan             = number
    bgp_asn          = number
    address_family   = optional(string)
    amazon_address   = optional(string)
    customer_address = optional(string)
    bgp_auth_key     = optional(string)
    dx_gateway_id    = optional(string)
    vpn_gateway_id   = optional(string)
    mtu              = optional(number)
    sitelink_enabled = optional(bool)
    tags             = optional(map(string))
  }))
  default = {}
}

variable "public_virtual_interfaces" {
  description = "Map of public virtual interfaces to create"
  type = map(object({
    name                  = string
    vlan                  = number
    bgp_asn               = number
    amazon_address        = string
    customer_address      = string
    address_family        = optional(string)
    bgp_auth_key          = optional(string)
    route_filter_prefixes = list(string)
    tags                  = optional(map(string))
  }))
  default = {}
}

variable "transit_virtual_interfaces" {
  description = "Map of transit virtual interfaces to create"
  type = map(object({
    name             = string
    vlan             = number
    bgp_asn          = number
    dx_gateway_id    = string
    address_family   = optional(string)
    amazon_address   = optional(string)
    customer_address = optional(string)
    bgp_auth_key     = optional(string)
    mtu              = optional(number)
    sitelink_enabled = optional(bool)
    tags             = optional(map(string))
  }))
  default = {}
}

variable "dx_gateways" {
  description = "Map of Direct Connect Gateways to create"
  type = map(object({
    name            = string
    amazon_side_asn = string
    timeout_create  = optional(string)
    timeout_delete  = optional(string)
  }))
  default = {}
}

variable "dx_gateway_associations" {
  description = "Map of Direct Connect Gateway associations"
  type = map(object({
    dx_gateway_id         = optional(string)
    dx_gateway_key        = optional(string)
    associated_gateway_id = string
    allowed_prefixes      = optional(list(string))
    proposal_id           = optional(string)
    timeout_create        = optional(string)
    timeout_update        = optional(string)
    timeout_delete        = optional(string)
  }))
  default = {}
}

variable "dx_gateway_association_proposals" {
  description = "Map of Direct Connect Gateway association proposals (for cross-account)"
  type = map(object({
    dx_gateway_id               = optional(string)
    dx_gateway_key              = optional(string)
    dx_gateway_owner_account_id = string
    associated_gateway_id       = string
    allowed_prefixes            = optional(list(string))
  }))
  default = {}
}

variable "hosted_connections" {
  description = "Map of hosted connections to create"
  type = map(object({
    name      = string
    bandwidth = string
    vlan      = number
  }))
  default = {}
}

variable "hosted_connection_owner_account_id" {
  description = "Owner account ID for hosted connections"
  type        = string
  default     = ""
}

variable "connection_confirmations" {
  description = "Map of connection confirmations for hosted connections"
  type        = map(string)
  default     = {}
}

variable "bgp_peers_private" {
  description = "Map of BGP peers for private virtual interfaces"
  type = map(object({
    vif_key          = string
    bgp_asn          = number
    address_family   = optional(string)
    amazon_address   = optional(string)
    customer_address = optional(string)
    bgp_auth_key     = optional(string)
  }))
  default = {}
}

variable "bgp_peers_public" {
  description = "Map of BGP peers for public virtual interfaces"
  type = map(object({
    vif_key          = string
    bgp_asn          = number
    address_family   = optional(string)
    amazon_address   = string
    customer_address = string
    bgp_auth_key     = optional(string)
  }))
  default = {}
}

variable "bgp_peers_transit" {
  description = "Map of BGP peers for transit virtual interfaces"
  type = map(object({
    vif_key          = string
    bgp_asn          = number
    address_family   = optional(string)
    amazon_address   = optional(string)
    customer_address = optional(string)
    bgp_auth_key     = optional(string)
  }))
  default = {}
}

variable "macsec_keys" {
  description = "Map of MACsec keys for connection encryption"
  type = map(object({
    secret_arn = optional(string)
    ckn        = optional(string)
    cak        = optional(string)
  }))
  default   = {}
  sensitive = true
}
