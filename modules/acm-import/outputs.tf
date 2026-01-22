
output "certificates" {
  description = "Map of all imported certificates with their details"
  value = {
    for key, cert in aws_acm_certificate.this : key => {
      arn                       = cert.arn
      id                        = cert.id
      domain_name               = cert.domain_name
      status                    = cert.status
      type                      = cert.type
      subject_alternative_names = cert.subject_alternative_names
      not_after                 = cert.not_after
      not_before                = cert.not_before
      key_algorithm             = cert.key_algorithm
      pending_renewal           = cert.pending_renewal
      renewal_eligibility       = cert.renewal_eligibility
      renewal_summary           = cert.renewal_summary
    }
  }
}

output "certificate_arns" {
  description = "Map of certificate keys to their ARNs"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.arn
  }
}

output "certificate_ids" {
  description = "Map of certificate keys to their IDs"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.id
  }
}

output "certificate_domain_names" {
  description = "Map of certificate keys to their primary domain names"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.domain_name
  }
}

output "certificate_expiration_dates" {
  description = "Map of certificate keys to their expiration dates"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.not_after
  }
}

output "certificate_subject_alternative_names" {
  description = "Map of certificate keys to their SANs"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.subject_alternative_names
  }
}

output "certificate_key_algorithms" {
  description = "Map of certificate keys to their key algorithms"
  value = {
    for key, cert in aws_acm_certificate.this : key => cert.key_algorithm
  }
}

output "certificate_arns_list" {
  description = "List of all certificate ARNs"
  value       = [for cert in aws_acm_certificate.this : cert.arn]
}

output "certificate_count" {
  description = "Total number of certificates imported"
  value       = length(aws_acm_certificate.this)
}
