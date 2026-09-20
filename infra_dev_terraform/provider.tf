terraform {

    backend "s3" {
        bucket  = "infra_dev_terraform_state_project_vyra"
        key     = "infra_dev/.terraform/terraform.tfstate"
        region  = "us-east-1"
        encrypt = true
    }

    required_version = ">= 1.0.0"

    required_providers {
        aws = {
        source  = "hashicorp/aws"
        version = "6.41.0"
        }
        archive = {
        source  = "hashicorp/archive"
        version = "~> 2.4"
        }
    }
}

provider "aws" {
  region = "us-east-1"
}