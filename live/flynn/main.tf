data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  azs             = ["us-east-2a"]
  az_count        = length(local.azs)
  subnet_newbits  = var.subnet_prefix - var.vpc_cidr_prefix
  private_subnets = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)]
  public_subnets  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + local.az_count)]
  repositories    = toset(["flynn/playwright-synthetics"])
}
module "alpha_vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "6.6.0"
  name               = "thegrid-alpha"
  cidr               = var.vpc_cidr
  azs                = local.azs
  private_subnets    = local.private_subnets
  public_subnets     = local.public_subnets
  enable_nat_gateway = true
  single_nat_gateway = true
}

module "k3s" {
  source    = "../../modules/k3s"
  subnet_id = module.alpha_vpc.public_subnets[0]
  vpc_id    = module.alpha_vpc.vpc_id
  allowed_ingress_ranges = [
    "74.99.165.44/32"
  ]
}

module "ecr" {
  for_each        = local.repositories
  source          = "../../modules/ecr"
  repository_name = each.key
}
