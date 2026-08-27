# WynnMarket

WynnMarket is an unattended Minecraft 1.21.11/Fabric client that enters Wynncraft's Trade Market, scans new listings, and writes the existing `pk`/`sk` listing format to DynamoDB. The production client runs in HeadlessMC 2.10.0 on an EC2 Docker host with Wynntils 4.2.8 and Wynnventory 2.2.2.

## Runtime behavior

The container supervisor launches `fabric:1.21.11 -lwjgl`, waits for the mod, and sends `connect play.wynncraft.com`. The mod accepts the server resource pack, waits for a valid player and target, performs the loading-exit click and Auction House click with bounded retries, verifies the Trade Market screen, and starts scanning. It logs structured `event=...` markers for each transition.

A valid scan atomically updates `/tmp/wynnmarket/last-valid-scan`. The container exits if the first scan misses the startup deadline or a marker becomes more than ten minutes old. Docker's `unless-stopped` policy then restarts the entire launch/connect sequence. The Docker health check is healthy only while that marker is fresh.

Runtime settings and defaults:

```text
WYNNMARKET_SERVER_ADDRESS=play.wynncraft.com
WYNNMARKET_STARTUP_TIMEOUT_SECONDS=600
WYNNMARKET_SCAN_TIMEOUT_SECONDS=600
WYNNMARKET_HEALTH_MARKER=/tmp/wynnmarket/last-valid-scan
WYNNMARKET_AWS_REGION=us-east-1
WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings
```

## Build and test

Requirements are Java 21, Docker, Terraform, AWS CLI, and authenticated AWS access. Build artifacts and credentials are never copied from `.env` into the image.

```bash
cd fabric
./gradlew clean test build
cd ..
docker/test-entrypoint.sh
```

The shell smoke test stubs HeadlessMC, verifies automatic launch/connect/health, and verifies that a missing initial scan terminates the supervisor. Build the image with:

```bash
docker build --platform linux/amd64 -f docker/Dockerfile -t wynnmarket-headless:latest .
```

The image requires a nonempty persisted account file mounted at:

```text
/headlessmc/HeadlessMC/auth/.accounts.json
```

## Infrastructure

Terraform manages DynamoDB, ECR, the EC2 host and instance role, an encrypted 1-GiB auth EBS volume, CloudWatch Logs, alarms, SNS, and EC2 automatic recovery. Container output is retained in `/wynnmarket/container` for 14 days. Alarms notify on both ALARM and recovery for:

- missing valid-scan heartbeats;
- DynamoDB write failures;
- EC2 host system-status failures (with EC2 recovery action).

SSM access remains enabled. The instance role can pull its ECR image, write the existing DynamoDB table, write only its log group, and use SSM.

Initialize and validate:

```bash
terraform -chdir=infrastructure init
terraform -chdir=infrastructure fmt -check -recursive
terraform -chdir=infrastructure validate
```

Always pass `enable_app_instance=true` while the production host should exist; its safe default is false.

## Staged deployment

The app host always uses the unattended startup path. Do not enable the app host until the auth migration succeeds.

1. Create and attach the encrypted volume without replacing the current instance:

   ```bash
  terraform -chdir=infrastructure plan \
    -var='enable_app_instance=true'
  terraform -chdir=infrastructure apply \
    -var='enable_app_instance=true'
   ```

2. Copy the current container's account file directly to the attached volume. The current source container defaults to `wynnmarket-local`; override `WYNNMARKET_CONTAINER_NAME` if needed.

   ```bash
   ./scripts/migrate-auth-volume.sh
   ```

   The script never prints the account file. It formats only the exact Terraform-managed auth volume when blank, copies `.accounts.json`, validates JSON, and applies mode `0600`.

3. Configure the email address for SNS alarm notifications:

   ```bash
   export TF_VAR_alert_email=you@example.com
   ```

   After applying Terraform, open the SNS subscription confirmation email and choose **Confirm subscription**.

4. Publish a versioned image after the Gradle build:

   ```bash
   ./scripts/build-and-push-ecr.sh unattended-1
   ```

5. Review the replacement plan, then enable the app host with the migration gate:

   ```bash
   terraform -chdir=infrastructure plan \
    -var='enable_app_instance=true' \
    -var='auth_state_migrated=true' \
    -var='app_image_tag=unattended-1'
   terraform -chdir=infrastructure apply \
    -var='enable_app_instance=true' \
    -var='auth_state_migrated=true' \
    -var='app_image_tag=unattended-1'
   ```

Terraform installs the host-side deployment script at /usr/local/sbin/wynnmarket-deploy during initial provisioning. The independent encrypted EBS volume remains separate and is bind-mounted as the single account file.

For later image deployments, do not run Terraform. Push a new versioned image and run:

    ./scripts/build-and-push-ecr.sh unattended-2
    ./scripts/deploy-to-ec2.sh unattended-2

This pulls the image and recreates only the Docker container, preserving the auth volume and container configuration.

## Operations

Read recent logs:

```bash
aws logs tail /wynnmarket/container --region us-east-1 --since 30m
```

Inspect the host and container through SSM:

```bash
INSTANCE_ID=$(terraform -chdir=infrastructure output -raw app_instance_id)
aws ssm send-command --region us-east-1 \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["docker ps -a","docker inspect --format={{json_.State.Health}} wynnmarket"]'
```

Useful structured markers are `startup_state`, `resource_pack_accept`, `target_clicked`, `scan_heartbeat`, `dynamodb_write_failure`, `reconnect_requested`, `service_healthy`, and `scan_watchdog_expired`.

### Reauthentication

Microsoft refresh tokens normally renew unattended. If the token is revoked or permanently expires, stop the workload, mount the auth volume into a temporary HeadlessMC container, perform the one-time `login` device flow, and write only the resulting `.accounts.json` back to the mounted volume. Never place the file in Git, an image, Terraform variables/state, SSM command output, or CloudWatch Logs. Restart the production container after validation.

### Recovery tests

- Stop the container and verify `unless-stopped` starts it again.
- Temporarily prevent new scan markers and verify exit/restart after `WYNNMARKET_SCAN_TIMEOUT_SECONDS`.
- Confirm the missing-heartbeat alarm sends an outage email and the subsequent heartbeat sends recovery email.
- Use the EC2 console/CloudWatch alarm test facility to validate notifications; do not intentionally impair the host outside a maintenance window.
- Query DynamoDB for records with timestamps after the fresh container start before accepting deployment.

Point-in-time recovery remains enabled on the DynamoDB table. EC2 system-status failures trigger automatic recovery; application failures are handled by the container watchdog and Docker restart policy.
