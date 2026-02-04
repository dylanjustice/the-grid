data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  azs             = data.aws_availability_zones.available.names
  az_count        = length(local.azs)
  subnet_newbits  = var.subnet_prefix - var.vpc_cidr_prefix
  private_subnets = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)]
  public_subnets  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + local.az_count)]
}

module "argocd_cluster" {
  source             = "../../modules/getting-started-argocd"
  region             = var.region
  kubernetes_version = "1.34"
}
