# -----------------------------------------------------------------------------
# AWS Certificate Manager (ACM) - Certificate Import Module
# Purpose: Import one or multiple external certificates into ACM
# -----------------------------------------------------------------------------

locals {
  processed_certificates = {
    for key, cert in var.certificates : key => {
      certificate_body  = cert.certificate_body != null ? cert.certificate_body : (cert.certificate_body_path != null ? file(cert.certificate_body_path) : null)
      private_key       = cert.private_key != null ? cert.private_key : (cert.private_key_path != null ? file(cert.private_key_path) : null)
      certificate_chain = cert.certificate_chain != null ? cert.certificate_chain : (cert.certificate_chain_path != null ? file(cert.certificate_chain_path) : null)
      name              = cert.name
      tags              = cert.tags
    }
  }

  default_tags = {
    ManagedBy = "terraform"
    Type      = "imported"
  }
}

resource "aws_acm_certificate" "this" {
  for_each = local.processed_certificates

  certificate_body  = each.value.certificate_body
  private_key       = each.value.private_key
  certificate_chain = each.value.certificate_chain

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.default_tags,
    var.tags_all,
    var.tags,
    each.value.tags,
    each.value.name != null ? { Name = each.value.name } : { Name = each.key }
  )
}

