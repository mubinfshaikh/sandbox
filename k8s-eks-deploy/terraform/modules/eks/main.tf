module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  # EKS Auto Mode: AWS manages nodes, load balancers and storage - no node groups to maintain
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }
}

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}
