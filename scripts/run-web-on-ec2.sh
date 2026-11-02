#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
DYNAMODB_TABLE_NAME="${WYNNMARKET_DYNAMODB_TABLE:-wynnmarket-trade-market-listings}"
CONTAINER_NAME="${WYNNMARKET_WEB_CONTAINER_NAME:-wynnmarket-web}"
REFRESH_SECONDS="${WYNNMARKET_REFRESH_SECONDS:-60}"
SITE_URL="${WYNNMARKET_SITE_URL:-}"

if [[ ! "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  echo "invalid web container name: $CONTAINER_NAME" >&2
  exit 2
fi

if [[ ! "$REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( REFRESH_SECONDS < 30 )); then
  echo "WYNNMARKET_REFRESH_SECONDS must be an integer of at least 30" >&2
  exit 2
fi

if [[ -z "$SITE_URL" ]]; then
  metadata_token="$(curl -fsS --request PUT \
    --header 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
    http://169.254.169.254/latest/api/token)"
  public_ip="$(curl -fsS \
    --header "X-aws-ec2-metadata-token: $metadata_token" \
    http://169.254.169.254/latest/meta-data/public-ipv4)"
  SITE_URL="http://${public_ip}"
fi

if [[ ! "$SITE_URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "invalid WYNNMARKET_SITE_URL: $SITE_URL" >&2
  exit 2
fi

commit="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)"
image="wynnmarket-web:${commit}"

docker build --pull --tag "$image" "$ROOT_DIR/web"
docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker_args=(
  --detach
  --restart unless-stopped
  --name "$CONTAINER_NAME"
  --publish 80:3000
  --env "AWS_REGION=$AWS_REGION"
  --env "WYNNMARKET_DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME"
  --env "WYNNMARKET_REFRESH_SECONDS=$REFRESH_SECONDS"
  --env "WYNNMARKET_SITE_URL=$SITE_URL"
  --label "wynnmarket.commit=$commit"
)

if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
  docker_args+=(
    --log-driver awslogs
    --log-opt "awslogs-region=$AWS_REGION"
    --log-opt "awslogs-group=$LOG_GROUP_NAME"
    --log-opt "awslogs-stream=web-$(hostname)"
  )
fi

docker run "${docker_args[@]}" "$image" >/dev/null

for attempt in $(seq 1 45); do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER_NAME")"
  if [[ "$health" == "healthy" ]]; then
    echo "WynnMarket web is healthy at $SITE_URL"
    exit 0
  fi
  if [[ "$health" == "exited" || "$health" == "dead" ]]; then
    docker logs --tail 100 "$CONTAINER_NAME" || true
    echo "web container stopped before becoming healthy" >&2
    exit 1
  fi
  sleep 2
done

docker logs --tail 100 "$CONTAINER_NAME" || true
echo "web container did not become healthy before the deadline" >&2
exit 1
