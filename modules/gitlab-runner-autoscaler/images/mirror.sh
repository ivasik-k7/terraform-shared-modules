#!/usr/bin/env bash
# Copies an image you do not build into ECR, unchanged:
#   the runner helper   <mirror>/gitlab/gitlab-runner-helper:x86_64-v<runner_version>
#   the collector       <mirror>/aws-observability/aws-otel-collector:<version>
#
#   ./mirror.sh <source image> <ECR repository URL>
#
# Prints the reference to give the module: the helper by its version tag
# (helper_image), anything else pinned by digest (monitoring.metrics_collector_image).
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <source image> <ECR repository URL>" >&2; exit 64; }
source_image="$1"
repository="$2"

tag="${source_image##*:}"
[ "$tag" != "$source_image" ] && [ "$tag" != "latest" ] || { echo "the source image needs a version tag, not latest or none" >&2; exit 64; }

# The runner looks the helper up by exactly x86_64-v<x.y.z> (or a flavour
# prefix such as ubuntu-x86_64-v<x.y.z>).
case "$source_image" in
  *gitlab-runner-helper:*)
    case "$tag" in
      *x86_64-v[0-9]*.[0-9]*.[0-9]*) ;;
      *) echo "the helper tag ($tag) is not …x86_64-v<x.y.z>" >&2; exit 64 ;;
    esac
    ;;
esac

docker pull --platform linux/amd64 "$source_image"
docker tag "$source_image" "$repository:$tag"

registry="${repository%%/*}"
region="$(echo "$registry" | cut -d. -f4)"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
docker push "$repository:$tag"
docker logout "$registry" >/dev/null

# RepoDigests also holds the source registry's entry; take the one pushed here.
digest="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$repository:$tag" | grep -F "$repository@" | head -n1 | sed 's/.*@//')"
echo
case "$source_image" in
  # helper_image must name the version tag the runner looks for.
  *gitlab-runner-helper:*) echo "helper_image = \"$repository:$tag\"" ;;
  *) echo "\"$repository@$digest\"   # $tag" ;;
esac
