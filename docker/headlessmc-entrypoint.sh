#!/usr/bin/env bash
set -euo pipefail

if [[ -f /headlessmc/.env ]]; then
	set -a
	source /headlessmc/.env
	set +a
fi

exec "$@"
