# Images

The module runs four images it does not make. This directory makes or copies
them; each is checked before it reaches a registry the runners use.

| Image | What it is | Made by | Module input | Rebuild when |
|---|---|---|---|---|
| Manager | The official `gitlab/gitlab-runner:alpine-v<version>` plus `fleeting-plugin-aws`, `docker-credential-ecr-login` and an entrypoint that writes `config.toml` | [manager/build.sh](manager/build.sh) | `manager_image` | Runner, plugin or credential helper version; entrypoint change; base image patches |
| Helper | GitLab's `gitlab-runner-helper:x86_64-v<version>`, unchanged | [mirror.sh](mirror.sh) | `helper_image` | Runner version, before the manager |
| Collector (optional) | The AWS Distro for OpenTelemetry collector, unchanged | [mirror.sh](mirror.sh) | `monitoring.metrics_collector_image` | Its own releases |
| Job instance AMI (optional) | Amazon Linux 2023 (ECS-optimized works as is) with Docker for `ec2-user`, the ECS agent off, bounded logs, the helper pre-pulled, a Docker Hub mirror | [job-host/gitlab-runner-job-host.yaml](job-host/gitlab-runner-job-host.yaml) through `modules/ami-builder` ([../examples/job-host-ami](../examples/job-host-ami)) | `ami_id` | Monthly patches; runner version (the pre-pulled helper) |

## Manager

```bash
cp manager/versions.env.example manager/versions.env   # fill in; commit it
manager/build.sh manager/versions.env
```

| What | How it is checked |
|---|---|
| Base image | Must be the Alpine flavour of `RUNNER_VERSION`; a digest pins it further |
| `fleeting-plugin-aws` | Downloaded over HTTPS, SHA-256 from the release's `release.sha256`; static (`CGO_ENABLED=0`), so it runs on Alpine |
| `docker-credential-ecr-login` | `apk add` from the Alpine community repository (Linux builds ship as distribution packages); apk checks the package signature; `ALPINE_MIRROR` points apk at your mirror |
| The result | The build runs `gitlab-runner --version`, `fleeting-plugin-aws -version` and `docker-credential-ecr-login -v`, so a binary that cannot run fails the build |

The image keeps the official image's `dumb-init` as PID 1 and hands over to its
`/entrypoint`, which adds a private CA to the system trust store. It stops with
SIGTERM instead of the official SIGQUIT: Fargate kills a task at most 120 s
after the stop signal, so waiting for jobs would end in SIGKILL.

What the entrypoint refuses at start, with a message in the manager log: a
token that is not `glrt-…`, a token with characters a token never has, an SSH
key that is not a private key.

## Helper and collector

```bash
./mirror.sh <mirror>/gitlab/gitlab-runner-helper:x86_64-v18.6.1 <ECR repository>
./mirror.sh <mirror>/aws-observability/aws-otel-collector:<version> <ECR repository>
```

Both are copied unchanged. The helper's tag must be `…x86_64-v<x.y.z>`, which
the runner looks up exactly; `mirror.sh` and the module's `helper_image`
validation both refuse anything else. The collector reference is printed pinned
by digest.

## Job instance AMI

Optional. The module's user data does the same at boot on the ECS-optimized
AMI; the AMI does it once, pre-pulls the helper so no job waits for it, and its
test phase proves `ec2-user` reaches Docker before the image is published. It
holds no credentials: the test phase fails the build if a registry login is left
in it.
