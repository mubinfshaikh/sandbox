# Shared by every unit: S3 state per unit + AWS provider.
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

remote_state {
  backend  = "s3"
  generate = { path = "backend.tf", if_exists = "overwrite_terragrunt" }
  config = {
    bucket       = "tfstate-${local.env.name}-${get_aws_account_id()}-${local.env.region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.env.region
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    terraform {
      required_version = ">= 1.10"
      required_providers {
        aws  = { source = "hashicorp/aws", version = "~> 6.67" }
        helm = { source = "hashicorp/helm", version = "~> 3.3" }
      }
    }
    provider "aws" {
      region = "${local.env.region}"
      default_tags { tags = { Project = "${local.env.name}", ManagedBy = "terragrunt" } }
    }
  EOT
}
