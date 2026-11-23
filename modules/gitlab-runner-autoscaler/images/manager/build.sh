#!/usr/bin/env bash
# Builds the manager image and pushes it to ECR.
#
#   cp versions.env.example versions.env   # fill it in, commit it
#   ./build.sh versions.env
#
# The plugin binary is checked against its SHA-256 before it enters the image;
# the ECR credential helper is an apk package, checked by apk's signatures.
# Needs docker (BuildKit), curl, sha256sum and the AWS CLI.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
env_file="${1:-$here/versions.env}"
[ -f "$env_file" ] || { echo "usage: $0 <versions.env>" >&2; exit 64; }
ALPINE_MIRROR=""
ECR_LOGIN_VERSION=""
# shellcheck disable=SC1090
. "$env_file"

for v in RUNNER_VERSION BASE_IMAGE PLUGIN_VERSION PLUGIN_URL PLUGIN_SHA256 TARGET_REPOSITORY IMAGE_REVISION; do
  [ -n "${!v:-}" ] || { echo "$v is empty in $env_file" >&2; exit 64; }
done
case "$BASE_IMAGE" in
  *"alpine-v${RUNNER_VERSION}"*) ;;
  *) echo "BASE_IMAGE ($BASE_IMAGE) is not the Alpine flavour of RUNNER_VERSION $RUNNER_VERSION (…:alpine-v$RUNNER_VERSION)" >&2; exit 64 ;;
esac

context="$(mktemp -d)"
trap 'rm -f "$context"/*; rmdir "$context"' EXIT

curl --fail --silent --show-error --location --proto '=https' --output "$context/fleeting-plugin-aws" "$PLUGIN_URL"
echo "$PLUGIN_SHA256  $context/fleeting-plugin-aws" | sha256sum --check --strict -
cp "$here/Dockerfile" "$here/entrypoint.sh" "$context/"

tag="${TARGET_REPOSITORY}:${RUNNER_VERSION}-${IMAGE_REVISION}"
docker build --pull --platform linux/amd64 \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg RUNNER_VERSION="$RUNNER_VERSION" \
  --build-arg PLUGIN_VERSION="$PLUGIN_VERSION" \
  --build-arg ALPINE_MIRROR="$ALPINE_MIRROR" \
  --build-arg ECR_LOGIN_VERSION="$ECR_LOGIN_VERSION" \
  --tag "$tag" "$context"

registry="${TARGET_REPOSITORY%%/*}"
region="$(echo "$registry" | cut -d. -f4)"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
docker push "$tag"
docker logout "$registry" >/dev/null

digest="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$tag" | grep -F "$TARGET_REPOSITORY@" | head -n1)"
echo
echo "manager_image = \"$tag\""
echo "# or pinned by digest: \"$digest\""
