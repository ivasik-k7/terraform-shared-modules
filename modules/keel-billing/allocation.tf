resource "aws_ce_cost_allocation_tag" "this" {
  for_each = local.create ? toset(var.cost_allocation_tags) : toset([])

  tag_key = each.value
  status  = "Active"
}

resource "aws_ce_cost_category" "this" {
  for_each = local.create ? var.cost_categories : {}

  name          = each.key
  rule_version  = "CostCategoryExpression.v1"
  default_value = each.value.default_value
  tags          = local.tags

  dynamic "rule" {
    for_each = each.value.rules
    content {
      value = rule.value.value
      type  = "REGULAR"

      rule {
        dynamic "dimension" {
          for_each = length(rule.value.accounts) > 0 ? [1] : []
          content {
            key           = "LINKED_ACCOUNT"
            values        = rule.value.accounts
            match_options = ["EQUALS"]
          }
        }
        dynamic "tags" {
          for_each = rule.value.tag_key != "" ? [1] : []
          content {
            key           = rule.value.tag_key
            values        = rule.value.tag_values
            match_options = ["EQUALS"]
          }
        }
      }
    }
  }

  # An inherited-value rule takes the category value from the resource's tag.
  dynamic "rule" {
    for_each = each.value.inherit_from_tag != "" ? [1] : []
    content {
      type = "INHERITED_VALUE"
      inherited_value {
        dimension_name = "TAG"
        dimension_key  = each.value.inherit_from_tag
      }
    }
  }

  dynamic "split_charge_rule" {
    for_each = each.value.split_charges
    content {
      source  = split_charge_rule.value.source
      targets = split_charge_rule.value.targets
      method  = split_charge_rule.value.method
    }
  }

  depends_on = [aws_ce_cost_allocation_tag.this]
}
