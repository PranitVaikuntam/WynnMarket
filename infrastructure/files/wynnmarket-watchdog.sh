#!/usr/bin/env bash
set -euo pipefail

# Watchdog for the WynnMarket scraper container. One pass per invocation; a
# systemd timer supplies the cadence. A restart is never good enough here: the
# container's writable layer holds HeadlessMC runtime state, so recovery means
# delete and recreate, which is exactly what wynnmarket-deploy already does.
#
# Repeated recreates inside a rolling window trip a latch: the container is
# stopped and left down rather than crash-looping. A manual redeploy re-arms it.
#
# This script takes no Terraform interpolation. Configuration comes from
# /etc/wynnmarket/container.env at runtime, with defaults for standalone runs.

CONFIG_FILE="${WYNNMARKET_CONFIG_FILE:-/etc/wynnmarket/container.env}"
STATE_DIR="${WYNNMARKET_STATE_DIR:-/var/lib/wynnmarket}"
DEPLOY_COMMAND="${WYNNMARKET_DEPLOY_COMMAND:-/usr/local/sbin/wynnmarket-deploy}"
HISTORY_FILE="${STATE_DIR}/recreate-history"
LATCH_FILE="${STATE_DIR}/watchdog-tripped"
LOCK_FILE="${STATE_DIR}/watchdog.lock"

if [[ -r "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CONTAINER_NAME="${CONTAINER_NAME:-wynnmarket}"
MAX_RECREATES="${WATCHDOG_MAX_RECREATES:-3}"
WINDOW_SECONDS="${WATCHDOG_WINDOW_SECONDS:-3600}"
LOG_GROUP_NAME="${LOG_GROUP_NAME:-}"
AWS_REGION="${AWS_REGION:-}"
AUTH_FILE="${AUTH_FILE:-}"

for value in "${MAX_RECREATES}" "${WINDOW_SECONDS}"; do
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "event=configuration_error reason=invalid_positive_integer value=${value}" >&2
    exit 64
  fi
done

NOW="$(date +%s)"
CW_EVENTS=()

# --- logging -----------------------------------------------------------------
# Every line goes to stderr for journalctl, and is buffered for a single
# CloudWatch flush at exit so one pass costs at most one API call.

log() {
  local line="$1"
  printf '%s\n' "${line}" >&2
  if [[ -n "${LOG_GROUP_NAME}" ]]; then
    CW_EVENTS+=("${line}")
  fi
}

instance_id() {
  local token
  token="$(curl -fsS -X PUT -m 2 \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
    http://169.254.169.254/latest/api/token 2>/dev/null)" || return 1
  curl -fsS -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
}

flush_cloudwatch() {
  (( ${#CW_EVENTS[@]} > 0 )) || return 0
  [[ -n "${LOG_GROUP_NAME}" ]] || return 0
  command -v aws >/dev/null 2>&1 || return 0

  local stream events region_args=()
  stream="watchdog/$(instance_id || echo "$(hostname)")"
  [[ -n "${AWS_REGION}" ]] && region_args=(--region "${AWS_REGION}")

  # PutLogEvents has not required a sequence token since 2023.
  aws logs create-log-stream "${region_args[@]}" \
    --log-group-name "${LOG_GROUP_NAME}" \
    --log-stream-name "${stream}" >/dev/null 2>&1 || true

  events="$(printf '%s\n' "${CW_EVENTS[@]}" \
    | jq -Rc --argjson ts "$(( NOW * 1000 ))" \
        '{timestamp: $ts, message: .}' | jq -sc '.')" || return 0

  aws logs put-log-events "${region_args[@]}" \
    --log-group-name "${LOG_GROUP_NAME}" \
    --log-stream-name "${stream}" \
    --log-events "${events}" >/dev/null 2>&1 \
    || echo "event=cloudwatch_publish_failed stream=${stream}" >&2
}
trap flush_cloudwatch EXIT

# --- auth volume -------------------------------------------------------------
# user_data does not re-run after a reboot, so the volume holding
# .accounts.json can be attached but unmounted. Mounting by mountpoint needs an
# /etc/fstab entry; warn rather than fail while that is still missing.

ensure_auth_mount() {
  [[ -n "${AUTH_FILE}" ]] || return 0
  local dir
  dir="$(dirname "${AUTH_FILE}")"

  if mountpoint -q "${dir}" 2>/dev/null; then
    return 0
  fi
  if mount "${dir}" >/dev/null 2>&1; then
    log "event=auth_volume_remounted path=${dir}"
    return 0
  fi
  log "event=auth_volume_not_mounted path=${dir} reason=no_fstab_entry"
}

# --- container state ---------------------------------------------------------

CONTAINER_ID=""
CONTAINER_STATUS="missing"
RESTART_COUNT=0
HEALTH_STATUS="none"
EXIT_CODE=0

read_container_state() {
  local raw
  raw="$(docker inspect --format \
    '{{.Id}} {{.State.Status}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.State.ExitCode}}' \
    "${CONTAINER_NAME}" 2>/dev/null)" || return 0
  read -r CONTAINER_ID CONTAINER_STATUS RESTART_COUNT HEALTH_STATUS EXIT_CODE <<<"${raw}"
}

health_output() {
  docker inspect --format \
    '{{range .State.Health.Log}}{{.Output}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null \
    | tr '\n\r\t' '   ' | tr -s ' ' | cut -c1-500
}

# --- give-up latch -----------------------------------------------------------

latch_container_id() {
  [[ -r "${LATCH_FILE}" ]] || return 0
  awk -F= '/^container_id=/ {print $2}' "${LATCH_FILE}" | head -n1
}

# A container whose ID differs from the one recorded at give-up time means
# somebody redeployed. Re-arm so the deploy path needs no knowledge of us.
try_rearm() {
  local recorded
  recorded="$(latch_container_id)"
  if [[ -n "${CONTAINER_ID}" && "${CONTAINER_ID}" != "${recorded}" ]]; then
    rm -f "${LATCH_FILE}" "${HISTORY_FILE}"
    log "event=watchdog_rearmed container_id=${CONTAINER_ID:0:12}"
    return 0
  fi
  return 1
}

give_up() {
  local reason="$1"
  docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  {
    printf 'tripped_at=%s\n' "${NOW}"
    printf 'reason=%s\n' "${reason}"
    printf 'container_id=%s\n' "${CONTAINER_ID}"
  } >"${LATCH_FILE}"
  log "event=watchdog_gave_up reason=${reason} recreates=${MAX_RECREATES} window_seconds=${WINDOW_SECONDS} container_id=${CONTAINER_ID:0:12}"
}

# --- recreate ----------------------------------------------------------------

recent_recreates() {
  [[ -r "${HISTORY_FILE}" ]] || return 0
  awk -v cutoff="$(( NOW - WINDOW_SECONDS ))" \
    '/^[0-9]+$/ && $1 >= cutoff' "${HISTORY_FILE}"
}

recreate() {
  local reason="$1"
  local history count

  history="$(recent_recreates)"
  count="$(printf '%s\n' "${history}" | grep -c '^[0-9]' || true)"

  if (( count >= MAX_RECREATES )); then
    give_up "${reason}"
    return 0
  fi

  # Prune the window down and record this attempt.
  { [[ -n "${history}" ]] && printf '%s\n' "${history}"; printf '%s\n' "${NOW}"; } \
    >"${HISTORY_FILE}.tmp"
  mv "${HISTORY_FILE}.tmp" "${HISTORY_FILE}"

  log "event=container_recreate_started reason=${reason} attempt=$(( count + 1 ))/${MAX_RECREATES}"
  if "${DEPLOY_COMMAND}" >/dev/null 2>&1; then
    read_container_state
    log "event=container_recreated reason=${reason} container_id=${CONTAINER_ID:0:12}"
  else
    log "event=container_recreate_failed reason=${reason} command=${DEPLOY_COMMAND}"
  fi
}

# --- main --------------------------------------------------------------------

main() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "event=configuration_error reason=docker_not_found" >&2
    exit 69
  fi

  ensure_auth_mount
  read_container_state

  if [[ -f "${LATCH_FILE}" ]]; then
    if ! try_rearm; then
      return 0
    fi
    read_container_state
  fi

  case "${CONTAINER_STATUS}" in
    missing)
      log "event=container_missing name=${CONTAINER_NAME}"
      recreate container_missing
      ;;
    exited | dead)
      log "event=container_exited status=${CONTAINER_STATUS} exit_code=${EXIT_CODE}"
      recreate container_exited
      ;;
    running)
      if (( RESTART_COUNT > 0 )); then
        # Docker's restart policy resurrected the container in place, keeping
        # the dirty writable layer. Replace it with a clean one.
        log "event=container_dirty_restart restart_count=${RESTART_COUNT} health=${HEALTH_STATUS}"
        recreate dirty_restart
      elif [[ "${HEALTH_STATUS}" == "unhealthy" ]]; then
        log "event=container_unhealthy container_id=${CONTAINER_ID:0:12} healthcheck_output=\"$(health_output)\""
        recreate unhealthy
      fi
      # starting / healthy / no healthcheck: nothing to do.
      ;;
    *)
      log "event=container_state_unhandled status=${CONTAINER_STATUS} health=${HEALTH_STATUS}"
      ;;
  esac
}

mkdir -p "${STATE_DIR}"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "event=watchdog_pass_skipped reason=already_running" >&2
  exit 0
fi

main
