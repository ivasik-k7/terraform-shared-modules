# complete

Three pools behind one call:

| Pool | Jobs | Instances |
|---|---|---|
| `docker` | Unprivileged, 4 per instance, 50 per instance lifetime | On-demand, one warm in office hours |
| `build` | Privileged (`docker:dind` builds), one per instance, instance deleted after the job | Spot above one on-demand instance |
| `deploy` | Assume `ci-deploy-workloads` in AWS; a protected runner in GitLab | On-demand |

Also: an existing cache bucket with its key and a 4 GiB archive limit, the
runner metrics collector sidecar, a Docker Hub mirror, a private CA for GitLab,
customer keys, an extra security group for jobs that reach a database, a
permissions boundary and required tags.

`build` mounts `/certs/client` so `docker:dind` with `DOCKER_TLS_CERTDIR=/certs`
shares its client certificates with the job. The role `ci-deploy-workloads`
must carry `job_role_trust_policies["deploy"]` as its trust policy.

What fails in it: nothing at plan. Spot under Capacity Rebalancing and the
collector's configuration path are unverified
([../../docs/RESEARCH.md](../../docs/RESEARCH.md), 2.9 and 7.1).
