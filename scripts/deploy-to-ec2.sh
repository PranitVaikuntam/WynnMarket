#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: $0 IMAGE_TAG}"
if [[ ! "$TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid image tag: $TAG" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/infrastructure"
AWS_REGION="$(terraform -chdir="${INFRA_DIR}" output -raw aws_region)"
INSTANCE_ID="$(terraform -chdir="${INFRA_DIR}" output -raw app_instance_id)"

command_id="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Deploy WynnMarket image ${TAG}" \
  --parameters "commands=[\"sudo /usr/local/sbin/wynnmarket-deploy ${TAG}\"]" \
  --query 'Command.CommandId' \
  --output text \
  --no-cli-pager)"

echo "SSM command: ${command_id}"
aws ssm wait command-executed \
  --region "$AWS_REGION" \
  --command-id "${command_id}" \
  --instance-id "$INSTANCE_ID"

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "${command_id}" \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json \
  --no-cli-pager
