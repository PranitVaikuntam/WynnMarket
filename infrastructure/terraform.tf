terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
  }

  backend "s3" {
    bucket         = "terraform-remote-state-vaikuntam"
    key            = "wynnmarket/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "Terraform"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      project = "wynnmarket"
    }
  }
}
