locals {
  billing_views = local.create ? var.billing_views : {}
  shared_views  = { for k, v in local.billing_views : k => v if length(v.share_with) > 0 }
  view_shares = merge([for k, v in local.shared_views : {
    for a in v.share_with : "${k}/${a}" => { view = k, account = a }
  }]...)

  primary_view_arn = one(flatten([for d in data.aws_billing_views.primary : [for v in d.billing_view : v.arn if v.billing_view_type == "PRIMARY"]]))
}

data "aws_billing_views" "primary" {
  count = length(local.billing_views) > 0 ? 1 : 0

  billing_view_types = ["PRIMARY"]
}

# ---------------------------------------------------------------------------
# Custom billing views: a slice of the organization's cost data, filtered on
# one dimension (accounts or one tag key), derived from the primary view
# https://registry.terraform.io/providers/hashicorp/aws/6.57.1/docs/resources/billing_view
# ---------------------------------------------------------------------------

resource "aws_billing_view" "this" {
  for_each = local.billing_views

  name         = "${var.name}-${each.key}"
  description  = each.value.description != "" ? each.value.description : "${var.name}: ${length(each.value.accounts) > 0 ? "${length(each.value.accounts)} accounts" : "${each.value.tag.key} = ${join(", ", each.value.tag.values)}"}"
  source_views = [local.primary_view_arn]
  tags         = local.tags

  data_filter_expression {
    dynamic "dimensions" {
      for_each = length(each.value.accounts) > 0 ? [1] : []
      content {
        key    = "LINKED_ACCOUNT"
        values = each.value.accounts
      }
    }
    dynamic "tags" {
      for_each = each.value.tag != null ? [each.value.tag] : []
      content {
        key    = tags.value.key
        values = tags.value.values
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.primary_view_arn != null
      error_message = "No PRIMARY billing view was found to derive ${each.key} from. Billing views are created from the management account's primary view; run this module there."
    }
  }
}

resource "aws_ram_resource_share" "views" {
  for_each = local.shared_views

  name                      = "${var.name}-${each.key}-billing-view"
  allow_external_principals = false
  tags                      = local.tags
}

resource "aws_ram_resource_association" "views" {
  for_each = local.shared_views

  resource_arn       = aws_billing_view.this[each.key].arn
  resource_share_arn = aws_ram_resource_share.views[each.key].arn
}

resource "aws_ram_principal_association" "views" {
  for_each = local.view_shares

  principal          = each.value.account
  resource_share_arn = aws_ram_resource_share.views[each.value.view].arn
}
