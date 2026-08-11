# Terraform

Infrastructure configuration for the non-Minecraft side of the project belongs here.

Run Terraform commands from this directory:

```sh
terraform init
terraform plan
terraform apply
```

Use `terraform.tfvars` in this directory for local deployment values. Keep real
tfvars files out of git; `terraform.tfvars.example` documents the expected
shape.
