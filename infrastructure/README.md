# Terraform

Infrastructure configuration for the non-Minecraft side of the project belongs here.

The repository-level `.env.example` documents the centralized local config.
The real `.env` file is ignored by git.

Run Terraform commands from this directory:

```sh
set -a
source ../.env
set +a
terraform init
terraform plan
terraform apply
```

Use the repository-level `.env` file for local deployment values. Terraform
automatically reads the `TF_VAR_*` entries after the file is loaded into your
shell environment.

The mod writes trade market listing data directly to DynamoDB using local AWS
credentials.
