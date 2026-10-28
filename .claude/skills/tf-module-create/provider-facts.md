# Where a fact comes from

A module decision rests on facts about Terraform, the AWS provider and AWS.
Each kind has one source that counts. Recall is a lead, never evidence.

| Fact | Source that counts | How |
|---|---|---|
| Argument exists, its type, required / optional / computed, deprecated | Provider schema at the resolved version | `terraform init -backend=false && terraform providers schema -json > <scratch>/schema.json`, then `jq '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas["aws_x"].block'` |
| Argument forces replacement (`ForceNew` / `RequiresReplace`) | Provider source at the pinned tag | The schema JSON does **not** carry it. Read `internal/service/<svc>/<resource>.go` at tag `v<version>` in hashicorp/terraform-provider-aws |
| Default value, allowed enum values, validators | Provider source at the pinned tag | Not in the schema JSON either |
| Behaviour differs between aws 5.x and 6.x | Both: validate and test with the v5 end pinned (`= 5.100.0`) and the newest 6.x | The `<module>-gates` CI jobs show the pattern: copy to a temp dir, `sed` the constraint, `terraform test` |
| Language semantics on the floor (eager `\|\|`/`&&` on 1.9, `optional()`, `moved`/`removed`) | An experiment on the floor binary, or the module's `tests/lint_validations.py` | A scratch config with `terraform_data` and `validate`; no AWS needed |
| AWS service behaviour (limits, which key region, which principal calls KMS) | AWS documentation, quoted with the page | Say which page. If it needs an API call to prove, it is "Not checked" |
| What a policy document renders to | An offline render | A config with mock credentials and `skip_*` flags, `create = false` where data sources would call AWS; see `modules/agent-warden/tests/render` |

## What `mock_provider` cannot prove

- **Replacement.** A change the real provider replaces plans as an in-place
  update under a mock. Assert a proxy (the version or hash moves) and say it
  is a proxy.
- **Data sources.** Mocked data sources return synthetic values, and
  `override_data` does not inherit `mock_data` defaults. A policy built by
  `data.aws_iam_policy_document` is not its real JSON under a mock.
- **AWS acceptance.** A green plan says nothing about whether the API accepts
  the request. That needs an apply, which is the human's call.

Write the gap down in the test file or under "Not checked"; never imply the
coverage exists.
