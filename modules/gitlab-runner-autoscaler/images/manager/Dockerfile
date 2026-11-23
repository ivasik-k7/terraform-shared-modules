# The official GitLab Runner image, Alpine flavour, from a mirror the network can
# reach: <registry>/gitlab/gitlab-runner:alpine-v<runner_version>. build.sh
# passes it; there is no default on purpose.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG RUNNER_VERSION
ARG PLUGIN_VERSION
ARG ALPINE_MIRROR=""
ARG ECR_LOGIN_VERSION=""
LABEL org.opencontainers.image.title="gitlab-runner-autoscaler manager" \
      org.opencontainers.image.version="${RUNNER_VERSION}" \
      com.gitlab.fleeting-plugin-aws.version="${PLUGIN_VERSION}"

# Linux builds of the ECR credential helper ship as distribution packages, and
# apk checks their signatures against the keys already in the image.
# https://github.com/awslabs/amazon-ecr-credential-helper#alpine-linux
RUN if [ -n "${ALPINE_MIRROR}" ]; then \
      sed -i -E "s#^https?://[^/]+/alpine#${ALPINE_MIRROR}#" /etc/apk/repositories; \
    fi \
 && apk add --no-cache "docker-credential-ecr-login${ECR_LOGIN_VERSION:+=${ECR_LOGIN_VERSION}}"

# Built with CGO_ENABLED=0, so it runs on Alpine. build.sh fetched and checked it.
# A plugin on PATH needs no `gitlab-runner fleeting install`, which would reach
# registry.gitlab.com.
COPY fleeting-plugin-aws /usr/local/bin/fleeting-plugin-aws
COPY entrypoint.sh /usr/local/bin/runner-entrypoint
RUN chmod 0755 /usr/local/bin/fleeting-plugin-aws /usr/local/bin/runner-entrypoint \
 && gitlab-runner --version \
 && fleeting-plugin-aws -version \
 && docker-credential-ecr-login -v

# The base image stops with SIGQUIT, which waits for running jobs; Fargate kills
# a task stopTimeout (at most 120 s) after the stop signal, so wait-for-jobs ends
# in SIGKILL. SIGTERM fails the jobs and deletes the instances within the
# runner's shutdown_timeout.
# https://docs.gitlab.com/runner/commands/#signals
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/dumb-init", "/usr/local/bin/runner-entrypoint"]
