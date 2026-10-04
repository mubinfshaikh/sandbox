include "root" { path = find_in_parent_folders("root.hcl") }

locals { env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals }

terraform { source = "${get_repo_root()}/k8s-eks-deploy/terraform/modules/argocd" }

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_name                       = "mock"
    cluster_endpoint                   = "https://mock.example.com"
    cluster_certificate_authority_data = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The helm provider needs the cluster, so it is generated here rather than in root.hcl.
generate "helm_provider" {
  path      = "helm_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--region", "${local.env.region}", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
        }
      }
    }
  EOT
}

inputs = {
  repo_url                  = "https://github.com/mubinfshaikh/sandbox.git"
  repo_branch               = "docker-ec2-asg-loadbalancer"
  argocd_chart_version      = "10.9.6"
  argocd_apps_chart_version = "2.0.6"
}
