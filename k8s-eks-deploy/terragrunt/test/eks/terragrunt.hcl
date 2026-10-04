include "root" { path = find_in_parent_folders("root.hcl") }

locals { env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals }

terraform { source = "${get_repo_root()}/k8s-eks-deploy/terraform/modules/eks" }

dependency "network" {
  config_path                             = "../network"
  mock_outputs                            = { vpc_id = "vpc-mock", private_subnets = ["subnet-mock1", "subnet-mock2"] }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name               = local.env.name
  kubernetes_version = "1.37"
  vpc_id             = dependency.network.outputs.vpc_id
  subnet_ids         = dependency.network.outputs.private_subnets
  ecr_repo           = "sample-app"
}
