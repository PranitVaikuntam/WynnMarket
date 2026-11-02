#!/usr/bin/env bash
set -euo pipefail

# This script is the entrypoint for the HeadlessMC Docker container. Environment variables are passed in from the terraform template, and are not defined in this script.
STARTUP_TIMEOUT_SECONDS="${WYNNMARKET_STARTUP_TIMEOUT_SECONDS:-600}"
SCAN_TIMEOUT_SECONDS="${WYNNMARKET_SCAN_TIMEOUT_SECONDS:-600}"
HEALTH_MARKER="${WYNNMARKET_HEALTH_MARKER:-/tmp/wynnmarket/last-valid-scan}"
HMC_COMMAND="${WYNNMARKET_HMC_COMMAND:-hmc}"
LAUNCH_TARGET="${WYNNMARKET_LAUNCH_TARGET:-fabric:1.21.11}"
AUTH_FILE="${WYNNMARKET_AUTH_FILE:-/headlessmc/HeadlessMC/auth/.accounts.json}"
REQUIRE_AUTH="${WYNNMARKET_REQUIRE_AUTH:-true}"
RUNTIME_DIR="${WYNNMARKET_RUNTIME_DIR:-/tmp/wynnmarket}"
COMMAND_FIFO="${RUNTIME_DIR}/commands.fifo"
OUTPUT_FIFO="${RUNTIME_DIR}/output.fifo"
SUPERVISOR_INTERVAL_SECONDS="${WYNNMARKET_SUPERVISOR_INTERVAL_SECONDS:-2}"
LOG4J_CONFIG="${WYNNMARKET_LOG4J_CONFIG:-/headlessmc/log4j2-wynnmarket.xml}"
OPENAL_LIBRARY="${WYNNMARKET_OPENAL_LIBRARY:-}"

for value in "${STARTUP_TIMEOUT_SECONDS}" "${SCAN_TIMEOUT_SECONDS}" "${SUPERVISOR_INTERVAL_SECONDS}"; do
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "event=configuration_error reason=invalid_positive_integer value=${value}" >&2
    exit 64
  fi
done

if [[ "${REQUIRE_AUTH}" == "true" && ! -s "${AUTH_FILE}" ]]; then
  echo "event=authentication_missing file=${AUTH_FILE}" >&2
  exit 65
fi

mkdir -p "${RUNTIME_DIR}" "$(dirname "${HEALTH_MARKER}")"
rm -f "${COMMAND_FIFO}" "${HEALTH_MARKER}"
mkfifo "${COMMAND_FIFO}"

GAME_MODS_DIR="${WYNNMARKET_GAME_DIR:-/root/.minecraft}/mods"
mkdir -p "${GAME_MODS_DIR}"
if compgen -G "/headlessmc/HeadlessMC/run/mods/*.jar" > /dev/null; then
  cp -f /headlessmc/HeadlessMC/run/mods/*.jar "${GAME_MODS_DIR}/"
  echo "event=mods_staged directory=${GAME_MODS_DIR}"
fi

if [[ -f "${LOG4J_CONFIG}" ]]; then
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Dlog4j.configurationFile=${LOG4J_CONFIG}"
  echo "event=logging_configured log4j_config=${LOG4J_CONFIG}"
fi

if [[ -n "${OPENAL_LIBRARY}" ]]; then
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Dorg.lwjgl.openal.libname=${OPENAL_LIBRARY}"
  echo "event=audio_configured openal_library=${OPENAL_LIBRARY}"
fi

HMC_PID=""
cleanup() {
  if [[ -n "${HMC_PID}" ]] && kill -0 "${HMC_PID}" 2>/dev/null; then
    printf 'quit\n' >&3 2>/dev/null || true
    kill -TERM "${HMC_PID}" 2>/dev/null || true
    wait "${HMC_PID}" 2>/dev/null || true
  fi
  exec 4<&- 2>/dev/null || true
  exec 4>&- 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  rm -f "${COMMAND_FIFO}" "${OUTPUT_FIFO}"
}
trap cleanup EXIT INT TERM

echo "event=supervisor_start server=${SERVER_ADDRESS} launch=${LAUNCH_TARGET} startup_timeout_seconds=${STARTUP_TIMEOUT_SECONDS} scan_timeout_seconds=${SCAN_TIMEOUT_SECONDS}"
mkfifo "${OUTPUT_FIFO}"
# Open the FIFO read/write so the HeadlessMC writer cannot block before the
# supervisor starts draining output. All lines are forwarded to stdout.
exec 4<> "${OUTPUT_FIFO}"
"${HMC_COMMAND}" < "${COMMAND_FIFO}" > "${OUTPUT_FIFO}" 2>&1 &
HMC_PID=$!
exec 3> "${COMMAND_FIFO}"

initialized=false
connect_sent=false
requested_reconnects=0
handled_reconnects=0

forward_output() {
  local line="$1"
  printf '%s\n' "${line}"
  if [[ "${line}" == *"WynnMarket initialized"* ]]; then
    initialized=true
  fi
  if [[ "${line}" == *"event=reconnect_requested"* ]]; then
    ((requested_reconnects += 1))
  fi
}

drain_output() {
  local line
  while IFS= read -r -t 1 -u 4 line; do
    forward_output "${line}"
  done
}

send_command() {
  local command="$1"
  kill -0 "${HMC_PID}" 2>/dev/null || return 1
  printf '%s\n' "${command}" >&3
}

send_command "launch ${LAUNCH_TARGET} -lwjgl"
echo "event=launch_requested target=${LAUNCH_TARGET}"

started_at=$(date +%s)
healthy_once=false

while kill -0 "${HMC_PID}" 2>/dev/null; do
  drain_output
  now=$(date +%s)
  if [[ "${initialized}" == "true" && "${connect_sent}" == "false" ]]; then
    send_command "connect ${SERVER_ADDRESS}"
    connect_sent=true
    echo "event=connect_requested server=${SERVER_ADDRESS}"
  fi

  if (( requested_reconnects > handled_reconnects )); then
    echo "event=reconnect_started request_count=${requested_reconnects}"
    send_command "disconnect" || true
    sleep 2
    send_command "connect ${SERVER_ADDRESS}"
    handled_reconnects=${requested_reconnects}
  fi

  if [[ -s "${HEALTH_MARKER}" ]]; then
    marker_epoch=$(tr -cd '0-9' < "${HEALTH_MARKER}")
    if [[ "${marker_epoch}" =~ ^[0-9]+$ ]]; then
      marker_age=$(( now - marker_epoch ))
      if (( marker_age <= SCAN_TIMEOUT_SECONDS )); then
        if [[ "${healthy_once}" == "false" ]]; then
          echo "event=service_first_healthy marker_age_seconds=${marker_age}"
          healthy_once=true
        fi
      else
        echo "event=scan_watchdog_expired marker_age_seconds=${marker_age} limit_seconds=${SCAN_TIMEOUT_SECONDS}" >&2
        exit 70
      fi
    fi
  elif (( now - started_at >= STARTUP_TIMEOUT_SECONDS )); then
    echo "event=startup_timeout elapsed_seconds=$((now - started_at))" >&2
    exit 71
  fi
  sleep "${SUPERVISOR_INTERVAL_SECONDS}"
done

drain_output
set +e
wait "${HMC_PID}"
exit_code=$?
set -e
echo "event=headlessmc_exit exit_code=${exit_code}" >&2
exit "${exit_code}"
