data "aws_availability_zones" "available" { state = "available" }

locals { azs = slice(data.aws_availability_zones.available.names, 0, 2) }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name            = var.name
  cidr            = var.cidr
  azs             = local.azs
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.cidr, 4, i)]
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.cidr, 4, i + 8)]

  # ponytail: one NAT for the whole VPC (~$35/mo); one per AZ if an AZ outage must not stop egress
  enable_nat_gateway = true
  single_nat_gateway = true

  # tags EKS uses to place internet-facing / internal load balancers
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
