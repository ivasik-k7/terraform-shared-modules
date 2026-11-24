# Research findings behind Keel

What the Keel modules rely on, where it comes from, and how firmly it is
established. **Unverified** is a belief, with the check that would settle it.

| Mark | Meaning |
|---|---|
| **Source** | Read in code at the version named while the modules were written |
| **Docs** | Read in AWS or HashiCorp documentation while the modules were written |
| **Unverified** | Not proven |

Versions read: hashicorp/aws provider `v6.57.1` and the AWS SDK for Go v2
service modules it pins (costexplorer v1.67.0, budgets v1.46.0, organizations
v1.53.0, bcmdataexports v1.18.0); CID data collection `main` at `77be83f`
(data exports template 0.13.0); CID framework `main` at `b17bcc5` (cid-cfn.yml
4.4.21). Documentation read in November 2026.

## Provider and APIs

| # | Finding | Mark | Source |
|---|---|---|---|
| 1.1 | The provider at 6.57.1 has every resource Keel uses: budgets and budget actions, anomaly monitors and subscriptions, cost categories and allocation tags, BCM data exports, organization policies, Bedrock inference profiles, Cost Optimization Hub and Compute Optimizer enrollment. | Source | `terraform providers schema -json` at 6.57.1 |
| 1.2 | Anomaly monitor dimensions: `SERVICE`, `LINKED_ACCOUNT`, `TAG`, `COST_CATEGORY`. For `TAG` and `COST_CATEGORY` an AWS managed monitor needs `{ "Tags": { "Key": … } }` or `{ "CostCategories": { "Key": … } }`. | Source + Docs | SDK costexplorer enums; API_AnomalyMonitor |
| 1.3 | AWS managed monitors track up to 5,000 values of their dimension and pick up new accounts and values on their own; subscriptions on them use one threshold for all values. | Docs | Cost Management guide, "Getting started with Cost Anomaly Detection" |
| 1.4 | Subscription thresholds use `ANOMALY_TOTAL_IMPACT_ABSOLUTE` and `ANOMALY_TOTAL_IMPACT_PERCENTAGE` with `GREATER_THAN_OR_EQUAL`; frequencies `DAILY`, `IMMEDIATE`, `WEEKLY`; subscribers `EMAIL` or `SNS`. | Source | SDK costexplorer enums |
| 1.5 | Individual (IMMEDIATE) anomaly alerts require an SNS topic; daily summaries go by e-mail. | Docs | "Getting started with Cost Anomaly Detection" |
| 1.6 | Cost Anomaly Detection publishes `Anomaly Detected` events (source `aws.ce`) to EventBridge with `detail.impact.totalImpact`, in its home Region. The event is tied to an immediate alert: "When an immediate alert is detected, the subscriber receives an event with the `Anomaly Detected` detail type." | Docs | Cost Management guide, "Using EventBridge with Cost Anomaly Detection" (cad-eventbridge.html) |
| 1.6a | An anomaly matching several immediate subscriptions emits one event per subscription, which is why `keel-billing` keeps one. | **Unverified** | Two immediate subscriptions with different floors; count the events for one anomaly |
| 1.7 | That home region is us-east-1, so the forwarding rule must be there. | **Unverified** | Trigger or wait for an anomaly; see which region's default bus receives it |
| 1.8 | The provider requires `metrics` and `filter_expression` together on `aws_budgets_budget`, and `metrics` conflicts with `cost_types`. | Source | provider `budgets/budget.go` (`RequiredWith`, `ConflictsWith`); a `terraform validate` that failed without the filter |
| 1.9 | Budget metrics: `BlendedCost`, `UnblendedCost`, `AmortizedCost`, `NetUnblendedCost`, `NetAmortizedCost` (and usage metrics). | Source | SDK budgets enums |
| 1.10 | In a budget's `filter_expression`, a tag filter names the tag key without the `user:` prefix. | Docs | provider docs, `aws_budgets_budget` examples |
| 1.11 | Budget actions: `APPLY_IAM_POLICY`, `APPLY_SCP_POLICY`, `RUN_SSM_DOCUMENTS`; approval `AUTOMATIC` or `MANUAL`. | Source | SDK budgets enums |
| 1.12 | The budget action's role needs only `iam:AttachRolePolicy` and `iam:DetachRolePolicy` on the target roles, scoped to the lock policy by `iam:PolicyARN`. | **Unverified** | Let the lock fire in a sandbox; CloudTrail shows the calls and any denial |
| 1.13 | Organization policy types include `BEDROCK_POLICY`, `TAG_POLICY`, `SERVICE_CONTROL_POLICY`, `RESOURCE_CONTROL_POLICY`, `AISERVICES_OPT_OUT_POLICY`. | Source | SDK organizations enums; provider validates with the enum |
| 1.14 | Cost Optimization Hub preferences: savings estimation `AfterDiscounts` or `BeforeDiscounts`; member discount visibility `All` or `None`. | Source | SDK costoptimizationhub enums |
| 1.15 | The provider has a `tag_policy_compliance` setting (`error`, `warning`, `disabled`) that checks required tag keys from organization tag policies at plan. | Source | provider schema at 6.57.1 |

## SNS for budgets and anomalies

| # | Finding | Mark | Source |
|---|---|---|---|
| 2.1 | Budgets publish to SNS as `budgets.amazonaws.com`, conditioned on `aws:SourceAccount` and `aws:SourceArn` `arn:aws:budgets::<account>:*`. | Docs | "Creating an Amazon SNS topic for budget notifications" |
| 2.2 | Anomaly Detection publishes as `costalerts.amazonaws.com`, conditioned on `aws:SourceAccount`; with an encrypted topic it needs `kms:GenerateDataKey*` and `kms:Decrypt`. | Docs | "Creating an Amazon SNS topic for anomaly notifications" |
| 2.3 | Budgets to an encrypted topic need the same KMS permissions for `budgets.amazonaws.com`. | **Unverified** (the budgets page says encryption needs additional permissions without listing them) | Send a test notification to an encrypted topic |

## Exports and Cloud Intelligence Dashboards

| # | Finding | Mark | Source |
|---|---|---|---|
| 3.1 | Data Exports can deliver to a bucket in another account; the bucket policy lets `bcm-data-exports.amazonaws.com` `s3:PutObject` with `aws:SourceArn` `arn:aws:bcm-data-exports:us-east-1:<source>:export/*` and `aws:SourceAccount`. | Docs | "Setting up an Amazon S3 bucket for data exports" |
| 3.2 | FOCUS 1.2 with AWS columns is table `FOCUS_1_2_AWS`, with 60 columns and a `TIME_GRANULARITY` setting. | Docs | Data Exports table dictionary |
| 3.3 | CUR 2.0 columns that appear only with a table setting: `line_item_resource_id` (INCLUDE_RESOURCES), `split_line_item_*` (INCLUDE_SPLIT_COST_ALLOCATION_DATA), `capacity_reservation_*` (INCLUDE_CAPACITY_RESERVATION_DATA), `line_item_iam_principal` (INCLUDE_IAM_PRINCIPAL_DATA, data from 8 April 2026, Bedrock only), `cost_analytics_*` (INCLUDE_STANDARDIZED_COST_AND_RATE). | Docs | CUR 2.0 table dictionary |
| 3.4 | AWS's CID data pipeline is one CloudFormation template for both sides (`data-exports-aggregation.yaml`): the source side creates the exports (natively in us-east-1, through a Lambda-backed resource elsewhere), the destination side the bucket `<prefix>-<account>-data-exports`, the Glue database `<prefix>_data_export` and the tables. `LegacyLocalBucket = no` is for new deployments. | Source | the template at 0.13.0 |
| 3.5 | AWS's own Terraform for CID wraps the published templates in `aws_cloudformation_stack`, from `https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn/…` by version, and deploys plugin dashboards one after another. | Source | CID framework `terraform/cicd-deployment` |
| 3.6 | The versioned template URLs Keel defaults to (data exports 0.13.0, cid-cfn and cid-plugin 4.4.21) exist. | Source | HTTP HEAD, 200 |
| 3.7 | `cid-cfn.yml` accepts only `yes` for `PrerequisitesQuickSight` and `PrerequisitesQuickSightPermissions` (Enterprise subscription, at least 10 GB SPICE, S3 and Athena access). | Source | `cid-cfn.yml` 4.4.21 (`AllowedPattern: 'yes'`) |
| 3.8 | Plugin dashboard IDs: `trends-dashboard`, `datatransfer-cost-analysis-dashboard`, `aws-marketplace`, `amazon-connect-cost-insight-dashboard`, `scad-containers-cost-allocation`, `focus-dashboard`, `cora`. | Source | CID framework `terraform/cicd-deployment/locals.tf` |
| 3.9 | The dashboards template's Lambda and the Quick Sight assets need no VPC path: they run in AWS's service network. | **Unverified** | Deploy in an account with no internet egress for workloads |

## AI meters

| # | Finding | Mark | Source |
|---|---|---|---|
| 4.1 | Bedrock publishes `InputTokenCount`, `OutputTokenCount` and cache token counts per `ModelId` every minute in `AWS/Bedrock`. | **Unverified** (stated in the practice plan's research) | `aws cloudwatch list-metrics --namespace AWS/Bedrock` |
| 4.2 | Whether those metrics are split by application inference profile, and which `ModelId` value a profile's calls carry. | **Unverified** | The same command after calls through a profile |
| 4.3 | The cost of calls through an application inference profile carries the profile's tags in the bill. | **Unverified** | CUR 2.0 a day after tagged calls |
| 4.4 | A metric math alarm can hold at most ten metrics, so the burn meter prices at most five models (input and output each). | **Unverified** | Create the alarm with six models |

## HCP Terraform cost gate

| # | Finding | Mark | Source |
|---|---|---|---|
| 5.1 | The `tfrun` import exposes `cost_estimate.prior_monthly_cost`, `proposed_monthly_cost` and `delta_monthly_cost`, as strings. | Docs | HCP Terraform `tfrun` import reference |
| 5.2 | The Sentinel `decimal` import: `decimal.new(x)`, with `less_than_or_equals` (also `lte`). | Docs | Sentinel `decimal` import reference |
| 5.3 | The policy file has not been run. | **Unverified** | `sentinel test` with mock data, or a soft-mandatory run |

## Guardrails

| # | Finding | Mark | Source |
|---|---|---|---|
| 7.1 | Tag policy syntax: `tag_key`, `tag_value`, `enforced_for` and `report_required_tag_for`, each with `@@assign`; one `*` per tag value; `<service>:ALL_SUPPORTED` for every supported type of a service. | Docs | Organizations guide, "Tag policy examples" |
| 7.2 | `enforced_for` prevents non-compliant tagging operations; `report_required_tag_for` is what IaC tools check for required keys. | Docs | same page, examples 1 and 4 |
| 7.3 | Policy size: SCP 10,240 characters, tag policy 10,000; at most ten SCPs attached directly to a root, OU or account. | Docs | Organizations quotas |
| 7.4 | Each default `deny_untagged` action accepts an `aws:RequestTag` condition on the resource type given. | **Unverified** | The Service Authorization Reference, action by action; a denied create in a pilot OU |
| 7.5 | SCPs do not apply to principals in the management account. | **Unverified** (not re-read) | Organizations guide, SCPs |
| 7.6 | A call through an inference profile is authorized against the profile and the model in each Region it may route to; the Converse APIs are authorized as `bedrock:InvokeModel`. | **Unverified** | Bedrock guide, inference profile permissions; a call through a cross-Region profile under the SCP |

## Control plane

| # | Finding | Mark | Source |
|---|---|---|---|
| 8.1 | EventBridge patterns support numeric ranges (`[">=", a, "<", b]`), `suffix`, `anything-but` with `suffix`, `prefix` and `exists`. | Docs | EventBridge guide, "Content filtering" |
| 8.2 | Uploading an object with an Object Lock retention needs a `Content-MD5` or `x-amz-sdk-checksum-algorithm` header. | Docs | S3 guide, "Managing Object Lock" |
| 8.3 | Data Firehose writes to a bucket with a default Object Lock retention (sends that header). | **Unverified** | `verify_commands.test_signal`, then the evidence prefix; the failed-delivery alarm fires if not |
| 8.4 | The Firehose role's trust takes `sts:ExternalId` equal to the account ID. | **Unverified** | Firehose guide, "Grant access to S3"; the first delivery |
| 8.5 | Every event carries `"version": "0"`, so the evidence rule matches all of them. | **Unverified** | The test signal in the evidence bucket |
| 8.6 | A rule can forward to an event bus in another account and Region with a role. | **Unverified** | An anomaly from the management account (us-east-1) arriving on the FinOps bus |

## Limits and signals

| # | Finding | Mark | Source |
|---|---|---|---|
| 9.1 | Commitment budgets (Savings Plans and RI coverage and utilization) measure against `100` `PERCENTAGE` with subscription costs only; RI budgets name one service. | Docs | provider docs, `aws_budgets_budget` at 6.57.1 |
| 9.2 | A commitment budget on an organization that holds no commitments stays quiet rather than alerting at 0%. | **Unverified** | Create one before the first purchase |
| 9.3 | A custom anomaly monitor watches one tag key, one cost category or `LINKED_ACCOUNT`, with up to ten values. | Docs | API_AnomalyMonitor |
| 9.4 | Custom anomaly monitors and their subscriptions work in a member account, on that account's spend. | **Unverified** | `keel-team` with `anomaly = {}` in a member account |
| 9.5 | Budget `auto_adjust_data` with `HISTORICAL` takes `budget_adjustment_period` in budget periods. | Source | provider schema at 6.57.1 |
| 9.6 | An EventBridge pipe can target only the default event bus of its own account and Region; a custom bus is refused. | Docs | EventBridge guide, "Event bus targets for pipes" (eb-pipes-event-target.html) |
| 9.7 | A pipe parses an SQS body that is JSON, so a filter on `body.TopicArn` matches SNS envelopes; `$.detail.body.Message` reaches the message in the control plane's input transformer. | **Unverified** | `verify_commands.test_warning`, then the control plane's HIGH topic |
| 9.8 | Budgets publish to an SNS topic in another Region than the account's home Region. | **Unverified** | Not relied on: `keel-team` points budgets at its own call's Region |

## Regions and FinOps Agent

| # | Finding | Mark | Source |
|---|---|---|---|
| 10.1 | AWS FinOps Agent is in preview; "organization setup and organization-wide agents run" in US East (N. Virginia). Where it stores data and where inference runs is not stated on what-is.html or the organization access page. | Docs + **Unverified** (storage and inference location) | setting-up-organization-access.html; find the data-location statement before a residency approval |
| 10.2 | Organization access is through the service-linked role `AWSServiceRoleForFinOpsAgent`, which SCPs do not restrict; it "reads cost, usage, and resource data in each member account, including AWS CloudTrail events, Amazon CloudWatch metrics, and CloudWatch Logs configuration"; "Everyone who can use an organization-wide agent can read data for every member account"; accounts cannot be excluded. | Docs | setting-up-organization-access.html |
| 10.2a | "Turning on trusted access directly in AWS Organizations does not complete AWS FinOps Agent organization setup." The console's setup needs `finops-agent:GetOrganizationAccess`, `finops-agent:UpdateOrganizationAccess`, `organizations:EnableAWSServiceAccess` (condition on the service principal) and `iam:CreateServiceLinkedRole`. | Docs | setting-up-organization-access.html |
| 10.3 | The agent creates its own EventBridge rule for anomaly events. | Docs | finops-agent user guide |
| 10.4 | AWS AI services opt-out: `{"services":{"default":{"opt_out_policy":{"@@assign":"optOut"}}}}`, at most 2,500 characters. | Docs | Organizations guide, orgs_manage_policies_ai-opt-out_syntax.html; Organizations quotas |
| 10.5 | `aws_organizations_aws_service_access` and `aws_billing_view` exist at 6.57.1. AWS recommends enabling trusted access through the service's own console or API, and the resource fights `aws_service_access_principals` on the organization resource. | Docs | provider docs at 6.57.1 |
| 10.6 | Registering the agent's delegated administrator by `organizations register-delegated-administrator` after the console setup is accepted. | **Unverified** | The first registration; `list-delegated-administrators` |
| 10.7 | A billing view's `data_filter_expression` takes `dimensions` with key `LINKED_ACCOUNT`, or `tags`; `source_views` names the views it derives from. | Docs | provider docs, `aws_billing_view` at 6.57.1 |
| 10.8 | Billing views are shared through AWS RAM, and an account they are shared with reads them in Cost Explorer. | **Unverified** | Share a view with the FinOps account; open Cost Explorer there |

## Team operations

| # | Finding | Mark | Source |
|---|---|---|---|
| 11.1 | Bedrock's invocation logging role trusts `bedrock.amazonaws.com` with `aws:SourceAccount` and `aws:SourceArn` `arn:aws:bedrock:<region>:<account>:*`, and writes `logs:CreateLogStream` and `logs:PutLogEvents` to the stream `aws/bedrock/modelinvocations`. | Docs | Bedrock guide, model-invocation-logging.html |
| 11.2 | With text, image, embedding and video delivery all off, Bedrock still logs each call's metadata (model, identity, token counts). | **Unverified** (the page lists the fields but not what is logged with no data type selected) | `verify_commands.invocation_logging`, then a call and the log group |
| 11.3 | CloudWatch Logs encrypts a log group with a key allowing `logs.<region>.amazonaws.com` `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:Describe*`, conditioned `ArnEquals` on `kms:EncryptionContext:aws:logs:arn`; the key must be in the same Region. | Docs | CloudWatch Logs guide, encrypt-log-data-kms.html |
| 11.4 | Service Quotas only raises: "The new value must be greater than the current value." | Docs | Service Quotas guide, request-quota-increase.html |
| 11.5 | EventBridge Scheduler calls any API as a universal target `arn:aws:scheduler:::aws-sdk:<service>:<apiAction>`, with the request as input. | Docs | Scheduler guide, managing-targets-universal.html |
| 11.6 | Automation with tag targets resolves any tagged resource unless the runbook sets a target type; for EC2 the target parameter receives the instance ID. Whether `AWS-StopEC2Instance` sets `/AWS::EC2::Instance` is not stated. | Docs + **Unverified** | Systems Manager guide, running-automations-map-targets.html; `aws ssm describe-document --name AWS-StopEC2Instance` |
| 11.7 | `AWS-StopRdsInstance` and `AWS-StartRdsInstance` take `InstanceId` ("ID of the Amazon RDS instance") and `AutomationAssumeRole`. | Docs | Automation runbook reference |
| 11.8 | The caller of a tag-targeted automation needs `tag:GetResources`; the scheduler and automation roles carry it. | **Unverified** (neither page lists caller permissions) | The first scheduled run; CloudTrail |
| 11.9 | RDS starts a stopped DB instance after seven days. | **Unverified** (not re-read) | RDS guide, "Stopping a DB instance" |

## Audit of 24 November 2026

| # | Finding | Mark | Source |
|---|---|---|---|
| 12.1 | "If an Amazon SQS message doesn't satisfy your filter criteria, EventBridge automatically removes the message from the queue." Pipes sharing a queue lose each other's messages. | Docs | eb-pipes-event-filtering.html |
| 12.2 | A pipe's input transformer parses a JSON SQS `body`; string variables are quoted by Pipes; extracted values are not escaped, so an object (`<$.body>`) is inserted unquoted; a missing path becomes an empty string. | Docs | eb-pipes-input-transformation.html |
| 12.3 | AWS managed monitors: AWS services per account, 1; additional ones (linked account, cost allocation tag, or cost category) per management account, 1; in total per management account, 2. Customer managed monitors track up to 10 linked accounts or tag values, and 1 cost category value. | Docs | management-limits.html |
| 12.4 | Whether a management account already holds an automatically created AWS services monitor, which would leave room for none. | **Unverified** | `aws ce get-anomaly-monitors` in the management account |
| 12.5 | The CID data exports template sets each export's `S3Region: !Ref AWS::Region` and delivers to `<prefix>-<destination>-data-exports`; its `ResourcePrefix` is `^[a-z0-9]+[a-z0-9-]{1,61}[a-z0-9]+$`, MaxLength 37; the bucket's lifecycle expires noncurrent versions only. | Source | data-exports-aggregation.yaml 0.13.0, lines 82-83, 314-323, 789-924 |
| 12.6 | `aws_cloudformation_stack` takes `region` at 6.57.1 and later. | Source | provider schema |
| 12.7 | CreateInferenceProfile: name `([0-9a-zA-Z][ _-]?)+`, at most 64; description `([0-9a-zA-Z:.][ _-]?)+`, at most 200. | Docs | API_CreateInferenceProfile.html |
| 12.8 | `lambda:GetFunctionConfiguration` returns "The function's environment variables". | Docs | API_GetFunctionConfiguration.html |
| 12.9 | AWS's budget action role example trusts `budgets.amazonaws.com` with `aws:SourceAccount` and `aws:SourceArn` `arn:aws:budgets::<account>:budget/*`. | Docs | billing-example-policies.html |
| 12.10 | A budget notification needs 1 to 11 subscribers (one SNS, ten e-mail). | Docs | API_budgets_NotificationWithSubscribers.html |
| 12.11 | Notifications per budget: CreateBudget says "up to five notifications", its array allows 10. | **Unverified** | A budget with six notifications |
| 12.12 | USAGE and commitment budgets "do not have CostTypes" (API reference); the provider's example sets them on commitment budgets. | **Unverified** | Create a commitment budget in a sandbox |
| 12.13 | Tag policy: the policy key "must match the value for the tag key, except for the case treatment". | Docs | orgs_manage_policies_example-tag-policies.html |
| 12.14 | Scheduler schedule names: `[0-9a-zA-Z-_.]+`, at most 64. | Docs | API_CreateSchedule.html |
| 12.16 | The provider refuses `monitor_dimension` with `monitor_specification` ("conflicts with"), so it cannot declare the TAG or COST_CATEGORY managed monitors the API defines with a key (1.2); `keel-billing` watches cost category values with customer managed monitors instead. | Source | `terraform test` at aws 6.73.0: `"monitor_dimension": conflicts with monitor_specification`; provider docs at 6.57.1 give no keyed dimensional example |
| 12.15 | A cross-account `PutEvents` from a rule's target role carries that role's ARN in `aws:PrincipalArn`, so the control plane's bus policy can admit keel-signals' roles only. | **Unverified** | The first signal from a member account; a denied PutEvents in CloudTrail if not |

## CID templates, reviewed

| # | Finding | Mark | Source |
|---|---|---|---|
| 13.1 | sha256 of the reviewed copies, fetched from `https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn/` on 24 November 2026: `data-exports/0.13.0/data-exports-aggregation.yaml` 1eba08e62689ecc5feb81ce452e6216ad736897c6d66510be605e5da02855009; `4.4.21/cid-cfn.yml` 4ff3367615fe05dea571a0c4960d446a9e6f395c311b0d0fffc487b99422d455; `4.4.21/cid-plugin.yml` c130bbb1f75ee23b2d71d34f1ede5d8f94f4e286cd7f12cc5388a40c0b91f2c5. | Source | `sha256sum` of the downloaded files |
| 13.2 | `cid-cfn.yml` takes the Lambda layer from the region map's AWS bucket when `LambdaLayerBucketPrefix` is AWS's name, otherwise from `<prefix>-<region>`, key `cid-resource-lambda-layer/cid-4.4.21.zip`. The data exports template and `cid-plugin.yml` carry their code inline and fetch none. | Source | cid-cfn.yml 4.4.21 lines 214-217, 360, 2138-2150; data-exports 0.13.0 `ZipFile` code |
| 13.3 | The data exports template has no retention parameter; it recommends HOURLY granularity "unless your AWS invoice is more then $50M". | Source | data-exports 0.13.0 parameters, lines 133-139 |
| 13.4 | `template_body` is limited to 51,200 bytes, so templates of this size deploy from a URL; CloudFormation reads a mirrored template, and the layer, from the caller's bucket as from AWS's. | **Unverified** (size limit from memory; mirror never deployed) | CloudFormation quotas page; a stack from the mirror in a sandbox |

## Prices used in descriptions and COSTS.md

| # | Finding | Mark | Source |
|---|---|---|---|
| 6.1 | Budgets are free; budget actions cost $0.10 a day each after the first two; anomaly detection, Cost Optimization Hub and Compute Optimizer are free; Data Exports cost S3 storage; the dashboards cost about $100-200 a month for a small Quick Sight deployment. | **Unverified** here (from the platform options deck, checked 23 November 2026) | AWS pricing pages |
