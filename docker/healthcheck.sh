#!/usr/bin/env bash
set -euo pipefail

marker="${WYNNMARKET_HEALTH_MARKER:-/tmp/wynnmarket/last-valid-scan}"
timeout="${WYNNMARKET_SCAN_TIMEOUT_SECONDS:-600}"
[[ -s "${marker}" ]] || exit 1
epoch=$(tr -cd '0-9' < "${marker}")
[[ "${epoch}" =~ ^[0-9]+$ ]] || exit 1
age=$(( $(date +%s) - epoch ))
(( age >= 0 && age <= timeout ))
