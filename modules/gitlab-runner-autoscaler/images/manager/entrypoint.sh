#!/bin/sh
# Writes config.toml, the SSH key, the CA and the Docker credential helper
# configuration from the task's environment and secrets, then hands over to the
# official image's entrypoint, which trusts the CA system-wide and runs the runner.
set -eu

: "${CONFIG_TOML_B64:?CONFIG_TOML_B64 is not set}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN is not set}"
: "${FLEETING_SSH_KEY:?FLEETING_SSH_KEY is not set}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/run/fleeting/id}"
CONFIG=/etc/gitlab-runner/config.toml

case "$RUNNER_TOKEN" in
  glrt-*) ;;
  *)
    echo "RUNNER_TOKEN is not a runner authentication token (glrt-...): write it to the parameter or secret in the pool's token_arn, then restart the service." >&2
    exit 64
    ;;
esac
if printf '%s' "$RUNNER_TOKEN" | grep -q '[^A-Za-z0-9_.-]'; then
  echo "RUNNER_TOKEN holds characters a runner token never has." >&2
  exit 64
fi
case "$FLEETING_SSH_KEY" in
  *"PRIVATE KEY-----"*) ;;
  *)
    echo "FLEETING_SSH_KEY is not a private key (PEM or OpenSSH): check the secret in ssh_private_key_secret_arn." >&2
    exit 64
    ;;
esac

umask 077
mkdir -p "$(dirname "$SSH_KEY_PATH")" /etc/gitlab-runner "${HOME:-/root}/.docker"

# OpenSSH refuses a key without its final newline; Secrets Manager may drop it.
printf '%s\n' "$FLEETING_SSH_KEY" >"$SSH_KEY_PATH"

printf '%s' "$CONFIG_TOML_B64" | base64 -d | sed "s/__RUNNER_TOKEN__/${RUNNER_TOKEN}/" >"$CONFIG"

# The official entrypoint adds this file to the system trust store.
if [ -n "${CA_CERTIFICATE_B64:-}" ]; then
  mkdir -p /etc/gitlab-runner/certs
  printf '%s' "$CA_CERTIFICATE_B64" | base64 -d >/etc/gitlab-runner/certs/ca.crt
fi

if [ -n "${DOCKER_CONFIG_B64:-}" ]; then
  printf '%s' "$DOCKER_CONFIG_B64" | base64 -d >"${HOME:-/root}/.docker/config.json"
fi

unset RUNNER_TOKEN FLEETING_SSH_KEY CONFIG_TOML_B64 CA_CERTIFICATE_B64 DOCKER_CONFIG_B64

exec /entrypoint run --config "$CONFIG" --working-directory /home/gitlab-runner
