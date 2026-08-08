terraform {
  backend "s3" {
    bucket = "terraform-remote-state-vaikuntam"
    key = "wynnmarket/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "Terraform"
  }
}

provider "aws" {
  region = "us-east-1"
}