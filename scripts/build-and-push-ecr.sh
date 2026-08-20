#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-latest}"
PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/infrastructure"

REPOSITORY_URL="$(terraform -chdir="${INFRA_DIR}" output -raw ecr_repository_url)"
REGISTRY_URL="${REPOSITORY_URL%%/*}"
AWS_REGION="$(terraform -chdir="${INFRA_DIR}" output -raw aws_region)"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY_URL}"

docker build \
  --platform "${PLATFORM}" \
  --file "${ROOT_DIR}/docker/Dockerfile" \
  --tag "${REPOSITORY_URL}:${TAG}" \
  "${ROOT_DIR}"

docker push "${REPOSITORY_URL}:${TAG}"
