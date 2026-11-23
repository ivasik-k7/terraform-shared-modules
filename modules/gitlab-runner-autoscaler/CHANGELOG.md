# Changelog: gitlab-runner-autoscaler

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `gitlab-runner-autoscaler-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- Pools of GitLab runners on the docker-autoscaler executor: per pool, a manager
  service on ECS Fargate (`modules/ecs`) and an Auto Scaling group shaped for
  fleeting-plugin-aws (`modules/asg-group`).
- Manager and instance security groups; SSH from managers to instances only.
- Runner tokens read from an SSM parameter or Secrets Manager secret made
  outside the module (`pools[*].token_arn`); `pools[*].enabled` to stop a pool.
- Manager task role scoped to its own group by name prefix and pool tag; ECR
  pulls through `docker-credential-ecr-login` on the manager.
- S3 cache (`cache`, through `modules/s3` or an existing bucket): a prefix per
  pool, presigned by the pool's manager, regional endpoint, tar+zstd, expiry.
- AWS access for jobs (`pools[*].aws_access`): instance role policies and roles
  to assume, `output.job_role_trust_policies`, check `jobs_hold_aws_credentials`;
  every instance role explicitly denied the runner tokens and SSH key.
- Monitoring (`monitoring`): manager-error and system-failure metric filters and
  alarms, fleet-at-ceiling and instances-without-manager alarms, a dashboard,
  and an optional collector sidecar for runner and fleeting metrics.
- `docker_registry_mirror` for Docker Hub images on the instances.
- `images/manager`, `images/mirror.sh`, `images/job-host`: image build, mirror and
  AMI component.
- Check `privileged_jobs_get_their_own_instance`.
- Outputs `network_contract`, `kms_key_policy_requirements`,
  `deployer_requirements`, `governance`, `verify_commands`, `config_toml`,
  `alarm_names`, `dashboard_name`, `cache_bucket`.
- `docs/ARCHITECTURE.md` (rollout and operations) and `docs/RESEARCH.md`
  (findings with sources).
