# complete

Every input, shaped like a migrated on-premises application on one cluster:

| Workload | Kind | Shows |
|---|---|---|
| `api` | service | Two containers (an init-style check that must succeed first), EFS through an access point, an ALB, Service Connect under its own discovery name, deployment alarms, autoscaling on CPU and ALB requests with London business-hours schedules, an inline task policy |
| `worker` | service | The image shortcut on `balanced` capacity, scaled on SQS backlog, as a Service Connect client, with ECS Exec for on-call; its pipeline deploys its revisions (`ignore_task_definition_changes`) |
| `reconcile` | scheduled | 02:00 London time on `spot_preferred`, failed invocations kept in an SQS dead-letter queue, logs kept seven years |
| `migrate` | task | No service; the pipeline runs `output.run_migrations` |
| `search` | service | A managed gp3 EBS volume restored from a snapshot, encrypted with the cluster's storage key, registered in Cloud Map for clients outside ECS |
| `shipper` | daemon | One log shipper per EC2 container instance, reading the host's Docker logs, logging to the platform's existing group |

It sets every key input (logs, secrets, Fargate ephemeral storage, managed
storage, ECS Exec, the topic), so `kms_key_policy_requirements` lists every
entry the module can produce, and `required_tag_keys` makes the cost tags
mandatory. Two checks are acknowledged: `shell_access_is_intended`, for the
worker's ECS Exec, and `containers_stay_on_their_side`, for the shipper's host
path. `output.governance` (`shell_access`, `host_access`) shows a reviewer both.

What fails in it: the ARNs are placeholders, so it plans (CI plans it against a
mocked provider) and would fail at apply.
