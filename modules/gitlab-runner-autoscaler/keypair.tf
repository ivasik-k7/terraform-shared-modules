resource "aws_key_pair" "managers" {
  count = local.create && length(local.pools) > 0 ? 1 : 0

  key_name   = "${var.name}-runner-managers"
  public_key = var.ssh_public_key
  tags       = local.tags
}
