# WynnMarket

WynnMarket is a Fabric client mod for Minecraft 1.21.11 that scans Wynncraft
Trade Market listings and writes selected listing data to DynamoDB. It uses
Wynntils and Wynnventory for Wynncraft-specific item and market data.

## Repository Layout

```text
fabric/          Fabric mod source, Gradle build, and tests
docker/          HeadlessMC Docker image and entrypoint
infrastructure/  Terraform for DynamoDB, ECR, networking, IAM, and EC2
scripts/         Deployment helpers
```

## Requirements

- Java 21
- Docker
- Terraform
- AWS CLI
- AWS credentials with access to the configured Terraform backend and managed AWS resources
- A Microsoft account that owns Minecraft Java Edition for online HeadlessMC use

The Gradle wrapper downloads the required Gradle version.

## Environment

For local Terraform and ECR publishing, authenticate with AWS using your normal
AWS CLI setup or exported environment variables:

```bash
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=
```

Do not bake AWS credentials into the Docker image. On EC2, the app should use
the instance profile created by Terraform.

The mod reads these runtime variables:

```text
WYNNMARKET_AWS_REGION=us-east-1
WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings
```

The EC2 user-data script passes those values into `docker run` automatically.

Optional Terraform overrides can be provided with `TF_VAR_...` variables:

```text
TF_VAR_aws_region
TF_VAR_dynamodb_table_name
TF_VAR_vpc_cidr
TF_VAR_public_subnet_cidrs
TF_VAR_ecr_repository_name
TF_VAR_app_instance_type
TF_VAR_app_image_tag
TF_VAR_enable_app_instance
```

## Build And Test

Run tests:

```bash
cd fabric
./gradlew test
```

Build the mod and stage standalone runtime mods:

```bash
cd fabric
./gradlew build
cd ..
```

The Docker image consumes:

```text
fabric/build/libs/wynnmarket-1.0.0.jar
fabric/build/standaloneMods/
```

## Docker

Build a local image from the repository root:

```bash
docker build \
  --platform linux/amd64 \
  -f docker/Dockerfile \
  -t wynnmarket-headless:latest \
  .
```

The image is based on HeadlessMC 2.9.0. During build it downloads Minecraft
1.21.11, installs Fabric, and copies the mod jars into:

```text
/headlessmc/HeadlessMC/run/mods
```

The Dockerfile does not copy `.env` into the image. The entrypoint will source
`/headlessmc/.env` only if that file exists, which is useful for local
experiments but should not be used for AWS credentials in ECR images.

Run locally:

```bash
docker run --name wynnmarket-local -d \
  -e WYNNMARKET_AWS_REGION=us-east-1 \
  -e WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
  wynnmarket-headless:latest
```

Open a shell in the container, start HeadlessMC, then run the manual login and
launch commands:

```bash
docker exec -it wynnmarket-local bash
hmc
```

At the HeadlessMC prompt:

```text
login
launch 1 -lwjgl
```

Restart and re-enter the same local container:

```bash
docker start wynnmarket-local
docker exec -it wynnmarket-local bash
```

## AWS Infrastructure

Terraform creates:

- DynamoDB table for listings
- VPC with a public subnet for the EC2 container host
- ECR repository for the container image
- IAM role and instance profile for EC2
- Optional EC2 instance that pulls and runs the ECR image

Terraform state uses this configured S3 backend:

```text
s3://terraform-remote-state-vaikuntam/wynnmarket/terraform.tfstate
```

Initialize and validate:

```bash
cd infrastructure
terraform init
terraform fmt -check
terraform validate
```

Create/update base infrastructure without launching EC2:

```bash
terraform apply
```

Useful outputs:

```bash
terraform output ecr_repository_url
terraform output trade_market_listings_table_name
terraform output app_instance_id
terraform output app_instance_public_ip
```

## Publish To ECR

After Terraform has created the ECR repository, build and push the image:

```bash
./scripts/build-and-push-ecr.sh latest
```

The helper reads Terraform outputs, logs Docker into ECR, builds the image for
`linux/amd64`, and pushes it to the ECR repository. Override the platform only
if the EC2 architecture changes:

```bash
DOCKER_PLATFORM=linux/arm64 ./scripts/build-and-push-ecr.sh latest
```

## Launch EC2

Launch the EC2 container host:

```bash
cd infrastructure
terraform apply -var='enable_app_instance=true' -var='app_image_tag=latest'
```

The instance user-data script installs Docker, logs into ECR, pulls the image,
and runs:

```bash
docker run \
  --detach \
  --restart unless-stopped \
  --name wynnmarket \
  --env WYNNMARKET_AWS_REGION=us-east-1 \
  --env WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
  <ecr-repository-url>:latest
```

This starts the container and keeps it alive with Bash. Minecraft login and
launch are still manual. After the container is running, open a shell in it,
start HeadlessMC, and run the login/launch commands yourself:

```bash
sudo docker exec -it wynnmarket bash
hmc
```

At the HeadlessMC prompt:

```text
login
launch 1 -lwjgl
```

One launched, use these commands to get inside wynncraft
```
connect play.wynncraft.com
gui
click 1
```

Check the instance and container through SSM:

```bash
aws ssm describe-instance-information \
  --region us-east-1 \
  --filters Key=InstanceIds,Values=$(terraform output -raw app_instance_id)
```

```bash
aws ssm send-command \
  --region us-east-1 \
  --instance-ids "$(terraform output -raw app_instance_id)" \
  --document-name AWS-RunShellScript \
  --parameters commands='["docker ps -a", "docker logs --tail 120 wynnmarket"]'
```

Stop and remove the EC2 instance when it is not needed:

```bash
cd infrastructure
terraform apply -var='enable_app_instance=false'
```

## Current Deployment Notes

The latest successful deployment used:

```text
Region: us-east-1
ECR repository: 844338287289.dkr.ecr.us-east-1.amazonaws.com/wynnmarket
Image tag: latest
Image digest: sha256:2a8dbaba15340634afd0883e55f24aad17836323c82ea02bc20818c2cca7aa8e
EC2 instance: i-0bbe5c45591f84a49
```

## Cleanup

Destroy all managed infrastructure:

```bash
cd infrastructure
terraform destroy
```

This removes managed AWS resources, including the EC2 instance when enabled.
Review the Terraform plan carefully before confirming.

docker run --name wynnmarket-local -it \
  -e WYNNMARKET_AWS_REGION=us-east-1 \
  -e WYNNMARKET_DYNAMODB_TABLE=wynnmarket-trade-market-listings \
  844338287289.dkr.ecr.us-east-1.amazonaws.com/wynnmarket bash