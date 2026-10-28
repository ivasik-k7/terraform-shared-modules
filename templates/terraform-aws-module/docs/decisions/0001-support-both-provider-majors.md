# 0001. Support aws provider 5.x and 6.x

- Status: accepted
- Date: 2026-10-26

## Context

Consuming workspaces upgrade the provider on their own schedule, and a module
that requires 6.x forces every caller to upgrade at once. Between the majors,
`aws_region.name` is deprecated in 6.x and `aws_region.region` does not exist
in 5.x; `endpoint` exists in both.

## Decision

`version = ">= 5.90.0, < 7.0.0"`. The region is parsed from
`aws_region.endpoint`. CI runs every test on aws 5.100.0 (pinned) and the
newest 6.x, on Terraform 1.9.8 and latest.

## Consequences

Arguments that exist in only one major cannot be used until the floor moves;
raising the floor is a major release. The CI matrix doubles.
