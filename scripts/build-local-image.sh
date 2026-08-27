#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-wynnmarket-headless:local}"
PLATFORM="${DOCKER_PLATFORM:-$(docker info --format '{{.OSType}}/{{.Architecture}}')}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Building the Fabric mod..."
(
  cd "${ROOT_DIR}/fabric"
  ./gradlew build
)

echo "Building local Docker image ${TAG}..."
docker build \
  --platform "${PLATFORM}" \
  --file "${ROOT_DIR}/docker/Dockerfile" \
  --tag "${TAG}" \
  "${ROOT_DIR}"

echo "Built ${TAG}"
