include "root" { path = find_in_parent_folders("root.hcl") }

locals { env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals }

terraform { source = "${get_repo_root()}/k8s-eks-deploy/terraform/modules/network" }

inputs = {
  name = local.env.name
  cidr = "10.20.0.0/16"
}
