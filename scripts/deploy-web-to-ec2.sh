#!/usr/bin/env bash
set -euo pipefail

GIT_REF="${1:-main}"
if [[ ! "$GIT_REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  echo "invalid git ref: $GIT_REF" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/infrastructure"
REPOSITORY_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
AWS_REGION="$(terraform -chdir="$INFRA_DIR" output -raw aws_region)"
INSTANCE_ID="$(terraform -chdir="$INFRA_DIR" output -raw app_instance_id)"
DYNAMODB_TABLE_NAME="$(terraform -chdir="$INFRA_DIR" output -raw trade_market_listings_table_name)"
PUBLIC_IP="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --no-cli-pager)"
SITE_URL="http://${PUBLIC_IP}"
LOG_GROUP_NAME="$(terraform -chdir="$INFRA_DIR" output -raw cloudwatch_log_group_name)"
CHECKOUT_DIR="/opt/wynnmarket"

if [[ ! "$REPOSITORY_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]]; then
  echo "the origin remote must be an HTTPS GitHub repository" >&2
  exit 2
fi

if [[ ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "the EC2 instance does not have a public IPv4 address" >&2
  exit 1
fi

shell_quote() {
  jq --raw-input --raw-output '@sh'
}

repository_q="$(printf '%s' "$REPOSITORY_URL" | shell_quote)"
ref_q="$(printf '%s' "$GIT_REF" | shell_quote)"
region_q="$(printf '%s' "$AWS_REGION" | shell_quote)"
table_q="$(printf '%s' "$DYNAMODB_TABLE_NAME" | shell_quote)"
site_q="$(printf '%s' "$SITE_URL" | shell_quote)"
log_group_q="$(printf '%s' "$LOG_GROUP_NAME" | shell_quote)"
checkout_q="$(printf '%s' "$CHECKOUT_DIR" | shell_quote)"

remote_command="$(cat <<EOF
set -euo pipefail
dnf install -y git
if [[ ! -d ${checkout_q}/.git ]]; then
  mkdir -p ${checkout_q}
  git clone --no-checkout ${repository_q} ${checkout_q}
fi
current_origin=\"\$(git -C ${checkout_q} remote get-url origin)\"
[[ \"\$current_origin\" == ${repository_q} ]]
git -C ${checkout_q} fetch --prune origin ${ref_q}
git -C ${checkout_q} checkout --detach FETCH_HEAD
AWS_REGION=${region_q} \\
WYNNMARKET_DYNAMODB_TABLE=${table_q} \\
WYNNMARKET_SITE_URL=${site_q} \\
LOG_GROUP_NAME=${log_group_q} \\
${checkout_q}/scripts/run-web-on-ec2.sh
EOF
)"

parameters="$(jq --null-input --compact-output \
  --arg command "$remote_command" \
  '{commands: [$command]}')"

command_id="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Deploy WynnMarket web from ${GIT_REF}" \
  --parameters "$parameters" \
  --query 'Command.CommandId' \
  --output text \
  --no-cli-pager)"

echo "SSM command: ${command_id}"
set +e
aws ssm wait command-executed \
  --region "$AWS_REGION" \
  --command-id "$command_id" \
  --instance-id "$INSTANCE_ID"
wait_status=$?
set -e

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$command_id" \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json \
  --no-cli-pager

if (( wait_status != 0 )); then
  exit "$wait_status"
fi

echo "WynnMarket web URL: $SITE_URL"
