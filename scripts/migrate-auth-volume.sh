#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra_dir="${repo_root}/infrastructure"
region="$(terraform -chdir="${infra_dir}" output -raw aws_region)"
instance_id="$(terraform -chdir="${infra_dir}" output -raw app_instance_id)"
volume_id="$(terraform -chdir="${infra_dir}" output -raw auth_volume_id)"
container_name="${WYNNMARKET_CONTAINER_NAME:-wynnmarket-local}"

if [[ -z "${instance_id}" || -z "${volume_id}" ]]; then
  echo "The app instance and auth volume must exist before migration." >&2
  exit 1
fi

commands=$(jq -nc \
  --arg volume "${volume_id}" \
  --arg container "${container_name}" \
  '[
    "set -euo pipefail",
    "serial=\"" + ($volume | gsub("-"; "")) + "\"",
    "device=\"/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${serial}\"",
    "for attempt in $(seq 1 60); do [[ -b \"${device}\" ]] && break; sleep 2; done",
    "[[ -b \"${device}\" ]]",
    "if ! blkid \"${device}\" >/dev/null 2>&1; then mkfs.xfs \"${device}\"; fi",
    "mkdir -p /mnt/wynnmarket-auth",
    "mountpoint -q /mnt/wynnmarket-auth || mount \"${device}\" /mnt/wynnmarket-auth",
    "docker cp " + $container + ":/headlessmc/HeadlessMC/auth/.accounts.json /mnt/wynnmarket-auth/.accounts.json",
    "test -s /mnt/wynnmarket-auth/.accounts.json",
    "chmod 600 /mnt/wynnmarket-auth/.accounts.json",
    "jq -e . /mnt/wynnmarket-auth/.accounts.json >/dev/null",
    "sync",
    "echo event=auth_migration_complete volume=" + $volume
  ]')

parameters=$(jq -nc --argjson commands "${commands}" '{commands: $commands}')
command_id=$(aws ssm send-command \
  --region "${region}" \
  --instance-ids "${instance_id}" \
  --document-name AWS-RunShellScript \
  --comment "Migrate HeadlessMC auth file to dedicated encrypted EBS volume" \
  --parameters "${parameters}" \
  --query 'Command.CommandId' \
  --output text \
  --no-cli-pager)

aws ssm wait command-executed \
  --region "${region}" \
  --command-id "${command_id}" \
  --instance-id "${instance_id}"

aws ssm get-command-invocation \
  --region "${region}" \
  --command-id "${command_id}" \
  --instance-id "${instance_id}" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json \
  --no-cli-pager

echo "Auth state migrated. Set auth_state_migrated=true only after reviewing the successful command output."
