#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
stub="${test_dir}/hmc-stub"
cp "${repo_root}/docker/test-fixtures/hmc-stub.sh" "${stub}"
chmod +x "${stub}"

WYNNMARKET_HMC_COMMAND="${stub}" \
WYNNMARKET_REQUIRE_AUTH=false \
WYNNMARKET_RUNTIME_DIR="${test_dir}/runtime" \
WYNNMARKET_HEALTH_MARKER="${test_dir}/health/marker" \
WYNNMARKET_STARTUP_TIMEOUT_SECONDS=8 \
WYNNMARKET_SCAN_TIMEOUT_SECONDS=5 \
WYNNMARKET_SUPERVISOR_INTERVAL_SECONDS=1 \
STUB_HEALTH_MARKER="${test_dir}/health/marker" \
"${repo_root}/docker/headlessmc-entrypoint.sh" > "${test_dir}/output" 2>&1 &
supervisor_pid=$!

for _ in {1..8}; do
  grep -q 'event=service_healthy' "${test_dir}/output" 2>/dev/null && break
  sleep 1
done
grep -q 'event=launch_requested' "${test_dir}/output"
grep -q 'event=connect_requested' "${test_dir}/output"
grep -q 'event=service_healthy' "${test_dir}/output"
kill -TERM "${supervisor_pid}" 2>/dev/null || true
wait "${supervisor_pid}" 2>/dev/null || true

set +e
WYNNMARKET_HMC_COMMAND="${stub}" \
WYNNMARKET_REQUIRE_AUTH=false \
WYNNMARKET_RUNTIME_DIR="${test_dir}/stalled-runtime" \
WYNNMARKET_HEALTH_MARKER="${test_dir}/stalled-health/marker" \
WYNNMARKET_STARTUP_TIMEOUT_SECONDS=2 \
WYNNMARKET_SCAN_TIMEOUT_SECONDS=2 \
WYNNMARKET_SUPERVISOR_INTERVAL_SECONDS=1 \
STUB_HEALTH_MARKER="" \
"${repo_root}/docker/headlessmc-entrypoint.sh" > "${test_dir}/stalled-output" 2>&1
stalled_exit=$?
set -e
[[ "${stalled_exit}" -eq 71 ]]
grep -q 'event=startup_timeout' "${test_dir}/stalled-output"
echo "entrypoint smoke test passed"
