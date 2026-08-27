#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r command; do
  case "${command}" in
    launch*) echo "WynnMarket initialized." ;;
    connect*)
      if [[ -n "${STUB_HEALTH_MARKER:-}" ]]; then
        mkdir -p "$(dirname "${STUB_HEALTH_MARKER}")"
        date +%s > "${STUB_HEALTH_MARKER}"
        echo "event=scan_heartbeat stub=true"
      fi
      ;;
    disconnect) echo "Disconnected" ;;
    quit) exit 0 ;;
  esac
done
