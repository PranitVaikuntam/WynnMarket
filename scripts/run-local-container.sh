#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-wynnmarket-headless:local}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_AUTH="${LOCAL_AUTH_FILE:-${ROOT_DIR}/auth/.accounts.json}"
LOCAL_AUTH_DIR="${ROOT_DIR}/auth-local"
CONTAINER_NAME="${LOCAL_CONTAINER_NAME:-wynnmarket-local-test}"

[[ -s "${SOURCE_AUTH}" ]] || {
  echo "Missing auth file: ${SOURCE_AUTH}" >&2
  exit 2
}

mkdir -p "${LOCAL_AUTH_DIR}"
cp "${SOURCE_AUTH}" "${LOCAL_AUTH_DIR}/.accounts.json"
chmod 600 "${LOCAL_AUTH_DIR}/.accounts.json"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker_args=(
  run
  --rm
  --name "${CONTAINER_NAME}"
  --mount "type=bind,source=${LOCAL_AUTH_DIR},target=/headlessmc/HeadlessMC/auth"
  --env "SERVER_ADDRESS=${SERVER_ADDRESS:-play.wynncraft.com}"
  --env "WYNNMARKET_STARTUP_TIMEOUT_SECONDS=${WYNNMARKET_STARTUP_TIMEOUT_SECONDS:-600}"
  --env "WYNNMARKET_SCAN_TIMEOUT_SECONDS=${WYNNMARKET_SCAN_TIMEOUT_SECONDS:-600}"
  --env "ALSOFT_DRIVERS=null"
  "${TAG}"
)

exec docker "${docker_args[@]}"
